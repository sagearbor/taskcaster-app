import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../features/arena/domain/models/feed_post.dart';
import '../../di/service_locator.dart';

/// Why a post was reported. [value] is what lands in `reports/{id}.reason`;
/// firestore.rules and functions/src/reports.js accept exactly these four.
enum ReportReason {
  inappropriate('inappropriate', 'Inappropriate'),
  spam('spam', 'Spam'),
  harassment('harassment', 'Harassment'),
  other('other', 'Other');

  const ReportReason(this.value, this.label);

  final String value;
  final String label;
}

/// One entry on the "Blocked players" screen.
class BlockedPlayer {
  /// The block key: a uid, or `house:<persona>` for a house persona.
  final String key;
  final String displayName;

  const BlockedPlayer({required this.key, required this.displayName});

  @override
  bool operator ==(Object other) =>
      other is BlockedPlayer &&
      other.key == key &&
      other.displayName == displayName;

  @override
  int get hashCode => Object.hash(key, displayName);

  @override
  String toString() => 'BlockedPlayer($key, $displayName)';
}

/// The server half of moderation. Separate from FeedRepository so the many
/// hand-written FeedRepository fakes in the tests stay untouched (same reason
/// as ShareStore).
abstract class ModerationStore {
  /// `users/{uid}.blockedUids`, live. Emits an empty list for a user with no
  /// profile doc yet.
  Stream<List<String>> watchBlocked(String uid);

  /// `arrayUnion` / `arrayRemove` on `users/{uid}.blockedUids`.
  Future<void> addBlocked(String uid, String key);
  Future<void> removeBlocked(String uid, String key);

  /// Create `reports/{postId}_{reporterId}` (create-only in the rules).
  Future<void> createReport({
    required String postId,
    required String authorId,
    required String reporterId,
    required ReportReason reason,
  });

  /// Display names for uids we have no cached name for (`users/{uid}`).
  /// Missing users are simply left out.
  Future<Map<String, String>> displayNames(Iterable<String> uids);
}

class FirestoreModerationStore implements ModerationStore {
  FirestoreModerationStore([FirebaseFirestore? firestore]) : _db = firestore;

  final FirebaseFirestore? _db;
  FirebaseFirestore get _firestore => _db ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _user(String uid) =>
      _firestore.collection('users').doc(uid);

  @override
  Stream<List<String>> watchBlocked(String uid) {
    return _user(uid).snapshots().map((snap) {
      final raw = snap.data()?['blockedUids'];
      return raw is List ? raw.whereType<String>().toList() : const <String>[];
    });
  }

  // set(merge) rather than update: a guest may not have a profile doc yet.
  @override
  Future<void> addBlocked(String uid, String key) => _user(uid).set({
        'blockedUids': FieldValue.arrayUnion([key]),
      }, SetOptions(merge: true));

  @override
  Future<void> removeBlocked(String uid, String key) => _user(uid).set({
        'blockedUids': FieldValue.arrayRemove([key]),
      }, SetOptions(merge: true));

  @override
  Future<void> createReport({
    required String postId,
    required String authorId,
    required String reporterId,
    required ReportReason reason,
  }) {
    return _firestore
        .collection('reports')
        .doc(ModerationService.reportDocId(postId, reporterId))
        .set({
      'postId': postId,
      'authorId': authorId,
      'reporterId': reporterId,
      'reason': reason.value,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<Map<String, String>> displayNames(Iterable<String> uids) async {
    final out = <String, String>{};
    for (final uid in uids) {
      try {
        final snap = await _user(uid).get();
        final name = snap.data()?['displayName'];
        if (name is String && name.trim().isNotEmpty) out[uid] = name.trim();
      } catch (e) {
        debugPrint('Moderation: no name for $uid: $e');
      }
    }
    return out;
  }
}

/// Offline / test store: remembers what it was asked to do.
class InMemoryModerationStore implements ModerationStore {
  final Map<String, List<String>> blocked = {};
  final List<Map<String, String>> reports = [];
  final Map<String, String> names = {};
  final StreamController<void> _changes = StreamController<void>.broadcast();

  @override
  Stream<List<String>> watchBlocked(String uid) async* {
    yield List.of(blocked[uid] ?? const []);
    yield* _changes.stream.map((_) => List.of(blocked[uid] ?? const []));
  }

  @override
  Future<void> addBlocked(String uid, String key) async {
    final list = blocked.putIfAbsent(uid, () => []);
    if (!list.contains(key)) list.add(key);
    _changes.add(null);
  }

  @override
  Future<void> removeBlocked(String uid, String key) async {
    blocked[uid]?.remove(key);
    _changes.add(null);
  }

  @override
  Future<void> createReport({
    required String postId,
    required String authorId,
    required String reporterId,
    required ReportReason reason,
  }) async {
    final id = ModerationService.reportDocId(postId, reporterId);
    if (reports.any((r) => r['id'] == id)) {
      throw StateError('Already reported');
    }
    reports.add({
      'id': id,
      'postId': postId,
      'authorId': authorId,
      'reporterId': reporterId,
      'reason': reason.value,
    });
  }

  @override
  Future<Map<String, String>> displayNames(Iterable<String> uids) async => {
        for (final uid in uids)
          if (names[uid] != null) uid: names[uid]!,
      };
}

/// What one account has blocked and reported, as last seen on this device.
class ModerationSnapshot {
  final Set<String> blocked;
  final Set<String> hiddenPosts;
  final Map<String, String> names;

  const ModerationSnapshot({
    this.blocked = const {},
    this.hiddenPosts = const {},
    this.names = const {},
  });
}

/// The device cache, so the feed filters before the profile doc loads (and
/// offline). Keyed per account.
abstract class ModerationCache {
  Future<ModerationSnapshot> read(String uid);
  Future<void> write(String uid, ModerationSnapshot snapshot);
}

class InMemoryModerationCache implements ModerationCache {
  final Map<String, ModerationSnapshot> data = {};

  @override
  Future<ModerationSnapshot> read(String uid) async =>
      data[uid] ?? const ModerationSnapshot();

  @override
  Future<void> write(String uid, ModerationSnapshot snapshot) async {
    data[uid] = snapshot;
  }
}

class SharedPrefsModerationCache implements ModerationCache {
  static String _key(String uid, String part) =>
      'moderation.${uid.isEmpty ? '_' : uid}.$part';

  @override
  Future<ModerationSnapshot> read(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final names = <String, String>{};
      final rawNames = prefs.getString(_key(uid, 'names'));
      if (rawNames != null) {
        final decoded = jsonDecode(rawNames);
        if (decoded is Map) {
          for (final e in decoded.entries) {
            if (e.value is String) names['${e.key}'] = e.value as String;
          }
        }
      }
      return ModerationSnapshot(
        blocked:
            (prefs.getStringList(_key(uid, 'blocked')) ?? const []).toSet(),
        hiddenPosts:
            (prefs.getStringList(_key(uid, 'hiddenPosts')) ?? const []).toSet(),
        names: names,
      );
    } catch (e) {
      debugPrint('Moderation cache read failed: $e');
      return const ModerationSnapshot();
    }
  }

  @override
  Future<void> write(String uid, ModerationSnapshot snapshot) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
          _key(uid, 'blocked'), snapshot.blocked.toList()..sort());
      await prefs.setStringList(
          _key(uid, 'hiddenPosts'), snapshot.hiddenPosts.toList()..sort());
      await prefs.setString(_key(uid, 'names'), jsonEncode(snapshot.names));
    } catch (e) {
      debugPrint('Moderation cache write failed: $e');
    }
  }
}

/// Report and block for user-generated content (App Store guideline 1.2).
///
///  * Reporting a post hides it for the reporter at once (device cache) and
///    writes `reports/{postId}_{uid}`; the onReportCreated Cloud Function logs
///    it and takes the post down for everyone after 3 reports.
///  * Blocking an author hides all their posts for this account. The keys live
///    in `users/{uid}.blockedUids` so the block follows the account, and in
///    the device cache so the feed filters before that doc loads.
///
/// Listeners (the Arena bloc) re-filter on [changes].
class ModerationService {
  ModerationService({ModerationStore? store, ModerationCache? cache})
      : _store = store ?? FirestoreModerationStore(),
        _cache = cache ?? SharedPrefsModerationCache();

  final ModerationStore _store;
  final ModerationCache _cache;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  String? _uid;
  Set<String> _blocked = {};
  Set<String> _hiddenPosts = {};
  Map<String, String> _names = {};
  StreamSubscription<List<String>>? _remoteSub;
  Future<void>? _loading;

  /// Blocks / unblocks made on this device whose account write has not been
  /// confirmed yet (or failed). Laid over every remote snapshot so a slow or
  /// refused write never makes a block flicker off.
  final Set<String> _pendingBlocks = {};
  final Set<String> _pendingUnblocks = {};

  /// The locator's instance, or an offline one when nothing is registered
  /// (widget tests that only wire the screens they test).
  static ModerationService fromLocator() => sl.isRegistered<ModerationService>()
      ? sl<ModerationService>()
      : ModerationService(
          store: InMemoryModerationStore(),
          cache: InMemoryModerationCache(),
        );

  /// `reports/{postId}_{reporterId}`: one report per person per post.
  static String reportDocId(String postId, String reporterId) =>
      '${postId}_$reporterId';

  /// Fires whenever what [hides] answers may have changed.
  Stream<void> get changes => _changes.stream;

  Set<String> get blockedKeys => Set.unmodifiable(_blocked);
  Set<String> get hiddenPostIds => Set.unmodifiable(_hiddenPosts);

  /// Should [post] be kept off this viewer's screen?
  bool hides(FeedPost post) =>
      post.hidden ||
      _hiddenPosts.contains(post.id) ||
      _blocked.contains(post.authorKey);

  /// Start (or switch to) [uid]: the device cache right away, then the
  /// account's block list, live. Safe to call repeatedly.
  Future<void> load(String uid) {
    if (_uid == uid && _loading != null) return _loading!;
    _uid = uid;
    return _loading = _load(uid);
  }

  Future<void> _load(String uid) async {
    await _remoteSub?.cancel();
    _remoteSub = null;
    _pendingBlocks.clear();
    _pendingUnblocks.clear();
    final cached = await _cache.read(uid);
    if (_uid != uid) return;
    _blocked = {...cached.blocked};
    _hiddenPosts = {...cached.hiddenPosts};
    _names = {...cached.names};
    _notify();
    if (uid.isEmpty) return;
    // Once the profile doc answers, it is the truth (an unblock on another
    // device must stick). Firestore's latency compensation already folds this
    // device's pending writes into the snapshot.
    _remoteSub = _store.watchBlocked(uid).listen(
      (remote) {
        final next = {...remote, ..._pendingBlocks}
          ..removeAll(_pendingUnblocks);
        if (setEquals(next, _blocked)) return;
        _blocked = next;
        _persist();
        _notify();
      },
      onError: (Object e) => debugPrint('Moderation: block list read: $e'),
    );
  }

  /// Hide [post] for this viewer now, then file the report. Throws when the
  /// report could not be written (the post stays hidden either way).
  Future<void> reportPost({
    required FeedPost post,
    required ReportReason reason,
    required String reporterId,
  }) async {
    _hiddenPosts.add(post.id);
    _persist();
    _notify();
    if (reporterId.isEmpty) return;
    await _store.createReport(
      postId: post.id,
      authorId: post.userId,
      reporterId: reporterId,
      reason: reason,
    );
  }

  /// Hide every post by [post]'s author for this account, now and on every
  /// device the account signs in on.
  Future<void> blockAuthorOf(FeedPost post, {required String uid}) async {
    final key = post.authorKey;
    _blocked.add(key);
    final name = post.displayName.trim();
    if (name.isNotEmpty) _names[key] = name;
    _pendingUnblocks.remove(key);
    _pendingBlocks.add(key);
    _persist();
    _notify();
    if (uid.isEmpty) return;
    await _store.addBlocked(uid, key);
    // Confirmed: the account's list carries it from here on. (On failure it
    // stays pending, so it holds for this session and in the device cache.)
    _pendingBlocks.remove(key);
  }

  Future<void> unblock(String key, {required String uid}) async {
    _blocked.remove(key);
    _pendingBlocks.remove(key);
    _pendingUnblocks.add(key);
    _persist();
    _notify();
    if (uid.isEmpty) return;
    await _store.removeBlocked(uid, key);
    _pendingUnblocks.remove(key);
  }

  /// Everyone this account has blocked, by name (A-Z). Names come from the
  /// device cache, the house persona key, or `users/{uid}` — in that order.
  Future<List<BlockedPlayer>> blockedPlayers() async {
    final missing = _blocked
        .where((k) => !_names.containsKey(k) && !k.startsWith('house:'))
        .toList();
    if (missing.isNotEmpty) {
      try {
        final found = await _store.displayNames(missing);
        if (found.isNotEmpty) {
          _names.addAll(found);
          _persist();
        }
      } catch (e) {
        debugPrint('Moderation: name lookup failed: $e');
      }
    }
    final players = [
      for (final key in _blocked)
        BlockedPlayer(key: key, displayName: nameFor(key)),
    ]..sort((a, b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    return players;
  }

  /// Best name for a block key.
  String nameFor(String key) {
    final cached = _names[key];
    if (cached != null && cached.isNotEmpty) return cached;
    if (key.startsWith('house:')) return key.substring('house:'.length);
    return 'A player';
  }

  void _persist() {
    final uid = _uid;
    if (uid == null) return;
    unawaited(_cache.write(
      uid,
      ModerationSnapshot(
        blocked: {..._blocked},
        hiddenPosts: {..._hiddenPosts},
        names: {..._names},
      ),
    ));
  }

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<void> dispose() async {
    await _remoteSub?.cancel();
    await _changes.close();
  }
}
