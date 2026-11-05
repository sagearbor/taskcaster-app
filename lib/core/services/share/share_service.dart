import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../../features/arena/domain/models/feed_post.dart';
import '../../di/service_locator.dart';
import 'share_links.dart';

/// The OS share sheet (share_plus), behind a seam for tests.
typedef ShareSheet = Future<void> Function(String text, {String? subject});

/// The two Firestore writes sharing needs. Separate from FeedRepository so the
/// many hand-written FeedRepository fakes in the tests stay untouched.
abstract class ShareStore {
  /// The owner's public-share switch on `feed_posts/{postId}.shareable`
  /// (rules: owner only, bool only — firestore.rules ownerEdit()).
  Future<void> setShareable(String postId, bool shareable);

  /// `share_attributions/{uid}`: this player's first post answered the
  /// challenge [fromPostId]. Create-only in the rules, so a second call for
  /// the same uid is refused there; callers treat it as best-effort.
  Future<void> recordAttribution({
    required String uid,
    required String fromPostId,
    required String postId,
    required String taskId,
  });
}

class FirestoreShareStore implements ShareStore {
  FirestoreShareStore([FirebaseFirestore? firestore]) : _db = firestore;

  final FirebaseFirestore? _db;
  FirebaseFirestore get _firestore => _db ?? FirebaseFirestore.instance;

  @override
  Future<void> setShareable(String postId, bool shareable) => _firestore
      .collection('feed_posts')
      .doc(postId)
      .update({'shareable': shareable});

  @override
  Future<void> recordAttribution({
    required String uid,
    required String fromPostId,
    required String postId,
    required String taskId,
  }) =>
      _firestore.collection('share_attributions').doc(uid).set({
        'fromPostId': fromPostId,
        'postId': postId,
        'taskId': taskId,
        'createdAt': FieldValue.serverTimestamp(),
      });
}

/// Offline / test store: remembers what it was asked to do.
class InMemoryShareStore implements ShareStore {
  final Map<String, bool> shareable = {};
  final Map<String, Map<String, String>> attributions = {};

  @override
  Future<void> setShareable(String postId, bool value) async {
    shareable[postId] = value;
  }

  @override
  Future<void> recordAttribution({
    required String uid,
    required String fromPostId,
    required String postId,
    required String taskId,
  }) async {
    attributions.putIfAbsent(
      uid,
      () => {'fromPostId': fromPostId, 'postId': postId, 'taskId': taskId},
    );
  }
}

/// How a share ended, so the UI can say "Link copied" where there is no
/// share sheet (desktop web).
enum ShareOutcome { sheet, copied, failed }

/// "Share your attempt" / "Share the finale" (audit WP-09).
///
/// Sharing IS the owner's consent: sharing your own friend-game post flips
/// its `shareable` flag on, which is what lets the public /c/ page render it.
/// Starter Pack posts are public by design and need no write.
class ShareService {
  ShareService({
    ShareStore? store,
    ShareSheet? sheet,
    Future<void> Function(String text)? copyToClipboard,
    bool? hasShareSheet,
  })  : _store = store ?? FirestoreShareStore(),
        _sheet = sheet ?? _osShareSheet,
        _copy = copyToClipboard ?? _clipboard,
        _hasSheet = hasShareSheet ?? _platformHasShareSheet();

  final ShareStore _store;
  final ShareSheet _sheet;
  final Future<void> Function(String) _copy;
  final bool _hasSheet;

  /// The locator's instance, or an offline one when nothing is registered
  /// (widget tests that only wire the screens they test).
  static ShareService fromLocator() => sl.isRegistered<ShareService>()
      ? sl<ShareService>()
      : ShareService(store: InMemoryShareStore(), hasShareSheet: false);

  static Future<void> _osShareSheet(String text, {String? subject}) =>
      Share.share(text, subject: subject);

  static Future<void> _clipboard(String text) =>
      Clipboard.setData(ClipboardData(text: text));

  /// Native apps always have a sheet; on the web only phones do
  /// (navigator.share). Desktop web would fall back to a mailto: link, so
  /// copy the link there instead.
  static bool _platformHasShareSheet() {
    if (!kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
  }

  /// Whether [post] is already public without an owner opt-in (mirrors
  /// isShareablePost in functions/src/share_page.js).
  static bool isPublic(FeedPost post) {
    if (post.shareable != null) return post.shareable!;
    return post.isHouse || ShareLinks.isPublicTask(post.taskId);
  }

  /// The text that goes in the sheet: a funny line, then the dare link.
  static String attemptMessage(FeedPost post) {
    final caption = ShareCaptions.forAttempt(
      seed: post.id,
      taskTitle: post.taskTitle,
      elapsedSeconds: post.elapsedSeconds,
      stamp: post.displayStamp,
    );
    return '$caption\n${ShareLinks.challengeUrl(post.id)}';
  }

  /// Shares the player's own [post] as a `/c/` dare link.
  Future<ShareOutcome> shareAttempt(FeedPost post) async {
    // Kick the write off but do NOT await it before the sheet: Safari only
    // allows navigator.share inside the tap's user activation, which an
    // awaited network round trip would use up. The write lands long before
    // anyone taps the link.
    // The error handler is attached right away so a fast failure is never
    // an unhandled async error while the sheet is up.
    final Future<bool> published = isPublic(post)
        ? Future.value(true)
        : _store.setShareable(post.id, true).then((_) => true,
            onError: (Object e) {
            debugPrint('ShareService: could not mark ${post.id} shareable: $e');
            return false;
          });
    final outcome = await _deliver(
      attemptMessage(post),
      subject: 'My TaskCaster attempt',
    );
    return await published ? outcome : ShareOutcome.failed;
  }

  /// Shares THE FINALE of a task.
  Future<ShareOutcome> shareFinale({
    required String montageId,
    required String taskTitle,
  }) {
    final text =
        '${ShareCaptions.forFinale(seed: montageId, taskTitle: taskTitle)}\n'
        '${ShareLinks.finaleUrl(montageId)}';
    return _deliver(text, subject: 'THE FINALE');
  }

  /// Best-effort, never throws: see [ShareStore.recordAttribution].
  Future<void> recordChallengeAttribution({
    required String uid,
    required String fromPostId,
    required String postId,
    required String taskId,
  }) async {
    if (uid.isEmpty || fromPostId == postId) return;
    try {
      await _store.recordAttribution(
        uid: uid,
        fromPostId: fromPostId,
        postId: postId,
        taskId: taskId,
      );
    } catch (e) {
      // Expected for every challenge after a player's first (create-only).
      debugPrint('ShareService: attribution not recorded: $e');
    }
  }

  Future<ShareOutcome> _deliver(String text, {String? subject}) async {
    if (_hasSheet) {
      try {
        await _sheet(text, subject: subject);
        return ShareOutcome.sheet;
      } catch (e) {
        debugPrint('ShareService: share sheet failed, copying instead: $e');
      }
    }
    try {
      await _copy(text);
      return ShareOutcome.copied;
    } catch (e) {
      debugPrint('ShareService: copy failed: $e');
      return ShareOutcome.failed;
    }
  }
}
