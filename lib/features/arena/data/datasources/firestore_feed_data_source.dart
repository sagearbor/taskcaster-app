import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'feed_remote_data_source.dart';

/// The Arena on Firestore: `feed_posts/{postId}` with a `grades/{graderUid}`
/// subcollection.
///
/// Composite indexes this needs (see firestore.indexes.json):
///   * queue — `taskId` (whereIn) + `gradeCount` ASC + `createdAt` DESC;
///   * Watch together — `gameId` == + `taskId` ==.
/// Own-post/already-graded exclusions and the final queue ordering (boosted,
/// taps) are applied client-side by `FeedRepositoryImpl`.
///
/// `createdAt` is written as `FieldValue.serverTimestamp()` and the rules
/// require exactly that, so no client clock can reorder the Arena. Older
/// documents still hold ISO-8601 strings; `FeedPost.fromMap` reads both.
class FirestoreFeedDataSource implements FeedRemoteDataSource {
  final FirebaseFirestore _firestore;

  FirestoreFeedDataSource({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  static const String _postsCollection = 'feed_posts';
  static const String _gradesCollection = 'grades';

  CollectionReference<Map<String, dynamic>> get _posts =>
      _firestore.collection(_postsCollection);

  static Map<String, dynamic> _withId(
    Map<String, dynamic> data,
    String id,
  ) {
    final out = Map<String, dynamic>.from(data);
    out['id'] = id;
    return out;
  }

  static List<Map<String, dynamic>> _rows(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    return snapshot.docs.map((d) => _withId(d.data(), d.id)).toList();
  }

  @override
  Future<String> createPost(Map<String, dynamic> data) async {
    final payload = Map<String, dynamic>.from(data);
    final id = payload.remove('id') as String?;
    // The server's clock, never the device's — the rules insist on it.
    payload['createdAt'] = FieldValue.serverTimestamp();
    if (id != null && id.isNotEmpty) {
      await _posts.doc(id).set(payload);
      return id;
    }
    final ref = await _posts.add(payload);
    return ref.id;
  }

  @override
  Stream<QueuePage> watchQueuePage({
    required List<String> taskIds,
    required int limit,
  }) {
    if (taskIds.isEmpty) {
      return Stream.value(const QueuePage([], hasMore: false));
    }
    final streams = [
      for (var i = 0; i < taskIds.length; i += whereInLimit)
        _posts
            .where(
              'taskId',
              whereIn: taskIds.sublist(
                i,
                i + whereInLimit > taskIds.length
                    ? taskIds.length
                    : i + whereInLimit,
              ),
            )
            .orderBy('gradeCount')
            .orderBy('createdAt', descending: true)
            .limit(limit)
            .snapshots()
            .map(_rows),
    ];
    return _combineLatest(streams).map((perChunk) => QueuePage(
          [for (final rows in perChunk) ...rows],
          hasMore: perChunk.any((rows) => rows.length >= limit),
        ));
  }

  /// Emits the latest value of every stream once each has emitted at least
  /// once, and again whenever any of them changes.
  static Stream<List<T>> _combineLatest<T>(List<Stream<T>> streams) {
    if (streams.length == 1) return streams.single.map((v) => [v]);
    late final StreamController<List<T>> controller;
    final subs = <StreamSubscription<T>>[];
    final latest = List<T?>.filled(streams.length, null);
    final seen = List<bool>.filled(streams.length, false);

    controller = StreamController<List<T>>(
      onListen: () {
        for (var i = 0; i < streams.length; i++) {
          subs.add(streams[i].listen(
            (value) {
              latest[i] = value;
              seen[i] = true;
              if (seen.every((s) => s)) {
                controller.add(latest.cast<T>().toList());
              }
            },
            onError: controller.addError,
          ));
        }
      },
      onCancel: () async {
        for (final sub in subs) {
          await sub.cancel();
        }
      },
    );
    return controller.stream;
  }

  @override
  Stream<List<Map<String, dynamic>>> watchPostsForTask(
    String gameId,
    String taskId,
  ) {
    // Both filters server-side: only this game's entries are downloaded, not
    // every post of the task app-wide.
    return _posts
        .where('gameId', isEqualTo: gameId)
        .where('taskId', isEqualTo: taskId)
        .snapshots()
        .map(_rows);
  }

  @override
  Stream<List<Map<String, dynamic>>> watchPostsByUser(String userId) {
    return _posts.where('userId', isEqualTo: userId).snapshots().map(_rows);
  }

  @override
  Stream<Map<String, dynamic>?> watchPost(String postId) {
    return _posts.doc(postId).snapshots().map(
          (snap) => snap.exists ? _withId(snap.data()!, snap.id) : null,
        );
  }

  @override
  Future<void> gradePost({
    required String postId,
    required String graderId,
    required int score,
  }) async {
    final postRef = _posts.doc(postId);
    final gradeRef = postRef.collection(_gradesCollection).doc(graderId);

    await _firestore.runTransaction((tx) async {
      // Every read must happen before every write inside a transaction.
      final post = await tx.get(postRef);
      if (!post.exists) {
        throw StateError('Post $postId not found');
      }
      if (post.data()?['userId'] == graderId) {
        throw StateError('You cannot grade your own post');
      }
      final existing = await tx.get(gradeRef);
      if (existing.exists) {
        throw StateError('Already graded');
      }

      // The rules accept the grade doc only in the same commit as this exact
      // counter bump, and the bump only alongside a NEW grade doc.
      tx.set(gradeRef, {
        'score': score,
        'createdAt': FieldValue.serverTimestamp(),
      });
      tx.update(postRef, {
        'gradeCount': FieldValue.increment(1),
        'gradeSum': FieldValue.increment(score),
        'graderIds': FieldValue.arrayUnion([graderId]),
      });
    });
  }

  @override
  Future<void> tapPost(String postId, {int taps = 1, int? atSecond}) async {
    await _posts.doc(postId).update({
      'tapCount': FieldValue.increment(taps),
      // A dotted key is a nested field path, so this bumps one bucket of the
      // tapSeconds map without reading or rewriting the rest of it — and it
      // lands in the same update as tapCount, which is what the Firestore
      // rules require of a tap.
      if (atSecond != null) 'tapSeconds.$atSecond': FieldValue.increment(taps),
      // Names the one bucket this write moves, so the rules can check that it
      // moved by exactly [taps] and that no other bucket changed.
      if (atSecond != null) 'lastTapSecond': '$atSecond',
    });
  }

  @override
  Future<int> gradedCountBy(String userId) async {
    final snap = await _posts.where('graderIds', arrayContains: userId).get();
    return snap.docs.length;
  }

  @override
  Future<void> boostPostsOf(
    String userId, {
    required int belowGradeCount,
  }) async {
    final snap = await _posts.where('userId', isEqualTo: userId).get();
    final hungry = snap.docs.where((d) {
      final data = d.data();
      if (data['boosted'] == true) return false;
      final count = data['gradeCount'];
      return (count is num ? count.toInt() : 0) < belowGradeCount;
    }).toList();
    if (hungry.isEmpty) return;

    final batch = _firestore.batch();
    for (final doc in hungry) {
      batch.update(doc.reference, {'boosted': true});
    }
    await batch.commit();
  }

  @override
  Future<void> ensureHouseEntries(List<Map<String, dynamic>> posts) async {
    // Deliberately a no-op. House posts carry crowd counters like any other
    // post, so the rules deny every client create, rewrite or delete of them
    // (otherwise anyone could reset or vandalise them). They are seeded with
    // the Admin SDK by functions/scripts/seed_house_posts.js, from
    // functions/scripts/house_posts.json, which is generated from
    // FeedRepositoryImpl.houseEntryPosts() and kept in step by a test.
  }
}
