import 'package:cloud_firestore/cloud_firestore.dart';

import 'feed_remote_data_source.dart';

/// The Arena on Firestore: `feed_posts/{postId}` with a `grades/{graderUid}`
/// subcollection.
///
/// Every query here is a single-field filter (or a plain orderBy), with the
/// reveal gate, own-post/already-graded exclusions and queue ordering applied
/// client-side by `FeedRepositoryImpl` — so NO composite index is needed.
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
    if (id != null && id.isNotEmpty) {
      await _posts.doc(id).set(payload);
      return id;
    }
    final ref = await _posts.add(payload);
    return ref.id;
  }

  @override
  Stream<List<Map<String, dynamic>>> watchRecentPosts({int limit = 30}) {
    return _posts
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(_rows);
  }

  @override
  Stream<List<Map<String, dynamic>>> watchPostsForTask(
    String gameId,
    String taskId,
  ) {
    // Single equality filter, then narrow to the game client-side.
    return _posts
        .where('taskId', isEqualTo: taskId)
        .snapshots()
        .map((s) => _rows(s).where((r) => r['gameId'] == gameId).toList());
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

      tx.set(gradeRef, {
        'score': score,
        'createdAt': DateTime.now().toIso8601String(),
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
      // rules require of a non-owner write.
      if (atSecond != null) 'tapSeconds.$atSecond': FieldValue.increment(taps),
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
      return (data['gradeCount'] as int? ?? 0) < belowGradeCount;
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
    // Deterministic doc ids (`house-<taskId>`) plus set(merge) make re-running
    // this harmless: it refreshes the seeded copy and never duplicates.
    for (final post in posts) {
      final payload = Map<String, dynamic>.from(post);
      final id = payload.remove('id') as String?;
      if (id == null || id.isEmpty) continue;

      final ref = _posts.doc(id);
      final existing = await ref.get();
      if (!existing.exists) {
        // First seed: write the whole document, counters and all.
        await ref.set(payload);
        continue;
      }
      // Re-seed: refresh the copy, but never clobber the counters the crowd
      // has already built up.
      for (final key in const [
        'gradeCount',
        'gradeSum',
        'graderIds',
        'tapCount',
        'tapSeconds',
        'boosted',
        'createdAt',
      ]) {
        payload.remove(key);
      }
      await ref.set(payload, SetOptions(merge: true));
    }
  }
}
