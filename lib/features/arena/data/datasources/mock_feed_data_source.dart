import 'dart:async';

import 'feed_remote_data_source.dart';

/// In-memory Arena, used by mock mode and by tests.
///
/// Deterministic on purpose: ids are `post-1`, `post-2`, … in creation order,
/// and every watch stream emits the current value immediately and then again
/// after each mutation.
class MockFeedDataSource implements FeedRemoteDataSource {
  final List<Map<String, dynamic>> _posts = [];
  final StreamController<void> _changes = StreamController<void>.broadcast();
  int _nextId = 1;

  /// Everything currently stored, as a defensive copy. Test seam.
  List<Map<String, dynamic>> get posts =>
      _posts.map((p) => Map<String, dynamic>.from(p)).toList();

  void dispose() {
    _changes.close();
  }

  Stream<T> _watch<T>(T Function() read) async* {
    yield read();
    yield* _changes.stream.map((_) => read());
  }

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  Map<String, dynamic>? _find(String postId) {
    for (final p in _posts) {
      if (p['id'] == postId) return p;
    }
    return null;
  }

  /// Newest first.
  List<Map<String, dynamic>> _sortedNewestFirst(
    Iterable<Map<String, dynamic>> source,
  ) {
    final list = source.map((p) => Map<String, dynamic>.from(p)).toList();
    list.sort((a, b) => (b['createdAt'] as String? ?? '')
        .compareTo(a['createdAt'] as String? ?? ''));
    return list;
  }

  @override
  Future<String> createPost(Map<String, dynamic> data) async {
    final incoming = Map<String, dynamic>.from(data);
    var id = incoming['id'] as String?;
    if (id == null || id.isEmpty) {
      id = 'post-${_nextId++}';
    }
    incoming['id'] = id;

    final existingIndex = _posts.indexWhere((p) => p['id'] == id);
    if (existingIndex >= 0) {
      _posts[existingIndex] = incoming;
    } else {
      _posts.add(incoming);
    }
    _notify();
    return id;
  }

  @override
  Stream<List<Map<String, dynamic>>> watchRecentPosts({int limit = 30}) {
    return _watch(() => _sortedNewestFirst(_posts).take(limit).toList());
  }

  @override
  Stream<List<Map<String, dynamic>>> watchPostsForTask(
    String gameId,
    String taskId,
  ) {
    return _watch(() => _sortedNewestFirst(
          _posts.where((p) => p['gameId'] == gameId && p['taskId'] == taskId),
        ));
  }

  @override
  Stream<List<Map<String, dynamic>>> watchPostsByUser(String userId) {
    return _watch(
      () => _sortedNewestFirst(_posts.where((p) => p['userId'] == userId)),
    );
  }

  @override
  Stream<Map<String, dynamic>?> watchPost(String postId) {
    return _watch(() {
      final found = _find(postId);
      return found == null ? null : Map<String, dynamic>.from(found);
    });
  }

  @override
  Future<void> gradePost({
    required String postId,
    required String graderId,
    required int score,
  }) async {
    final post = _find(postId);
    if (post == null) {
      throw StateError('Post $postId not found');
    }
    if (post['userId'] == graderId) {
      throw StateError('You cannot grade your own post');
    }
    final graders = List<String>.from(
      (post['graderIds'] as List<dynamic>? ?? const []).map((e) => e as String),
    );
    if (graders.contains(graderId)) {
      throw StateError('Already graded');
    }

    graders.add(graderId);
    post['graderIds'] = graders;
    post['gradeCount'] = (post['gradeCount'] as int? ?? 0) + 1;
    post['gradeSum'] = (post['gradeSum'] as int? ?? 0) + score;
    _notify();
  }

  @override
  Future<void> tapPost(String postId, {int taps = 1, int? atSecond}) async {
    final post = _find(postId);
    if (post == null) return;
    post['tapCount'] = (post['tapCount'] as int? ?? 0) + taps;
    if (atSecond != null) {
      final buckets = Map<String, int>.from(
        (post['tapSeconds'] as Map?)?.map(
              (k, v) => MapEntry('$k', (v as num?)?.toInt() ?? 0),
            ) ??
            const <String, int>{},
      );
      buckets['$atSecond'] = (buckets['$atSecond'] ?? 0) + taps;
      post['tapSeconds'] = buckets;
    }
    _notify();
  }

  @override
  Future<int> gradedCountBy(String userId) async {
    return _posts.where((p) {
      final graders = p['graderIds'] as List<dynamic>? ?? const [];
      return graders.contains(userId);
    }).length;
  }

  @override
  Future<void> boostPostsOf(
    String userId, {
    required int belowGradeCount,
  }) async {
    var changed = false;
    for (final p in _posts) {
      if (p['userId'] != userId) continue;
      if ((p['gradeCount'] as int? ?? 0) >= belowGradeCount) continue;
      if (p['boosted'] == true) continue;
      p['boosted'] = true;
      changed = true;
    }
    if (changed) _notify();
  }

  @override
  Future<void> ensureHouseEntries(List<Map<String, dynamic>> posts) async {
    var changed = false;
    for (final incoming in posts) {
      final id = incoming['id'] as String?;
      if (id == null || id.isEmpty) continue;
      final existing = _find(id);
      if (existing != null) {
        // Idempotent: refresh the seeded copy but keep the counters the crowd
        // has built up, exactly like a set(merge) of the seed fields would.
        final merged = Map<String, dynamic>.from(incoming)
          ..['gradeCount'] = existing['gradeCount'] ?? 0
          ..['gradeSum'] = existing['gradeSum'] ?? 0
          ..['tapCount'] = existing['tapCount'] ?? 0
          ..['tapSeconds'] = existing['tapSeconds'] ?? const <String, int>{}
          ..['boosted'] = existing['boosted'] ?? false
          ..['graderIds'] = existing['graderIds'] ?? const <String>[]
          ..['createdAt'] = existing['createdAt'] ?? incoming['createdAt'];
        _posts[_posts.indexWhere((p) => p['id'] == id)] = merged;
      } else {
        _posts.add(Map<String, dynamic>.from(incoming));
        changed = true;
      }
    }
    if (changed) _notify();
  }
}
