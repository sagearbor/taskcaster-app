import '../../../../core/models/submission.dart';
import '../../../tasks/data/datasources/starter_pack_data.dart';
import '../../domain/models/feed_post.dart';
import '../../domain/repositories/feed_repository.dart';
import '../datasources/feed_remote_data_source.dart';

class FeedRepositoryImpl implements FeedRepository {
  final FeedRemoteDataSource remoteDataSource;

  FeedRepositoryImpl(this.remoteDataSource);

  /// Uid the seeded entries are posted under.
  static const String houseUserId = 'house';

  /// Deterministic document id for a task's house entry, so seeding twice
  /// overwrites rather than duplicates.
  static String houseIdFor(String taskId) => 'house-$taskId';

  /// Posts with this many grades or more are already well fed, so boosting
  /// skips them.
  static const int boostBelowGrades = 3;

  @override
  Future<String> createPost(FeedPost post) {
    final data = post.toMap();
    if (post.id.isEmpty) data.remove('id');
    return remoteDataSource.createPost(data);
  }

  @override
  Stream<List<FeedPost>> watchQueue({
    required String viewerId,
    required Set<String> unlockedTaskIds,
    int limit = 30,
  }) {
    if (unlockedTaskIds.isEmpty) {
      return Stream.value(const <FeedPost>[]);
    }
    return remoteDataSource.watchRecentPosts(limit: limit).map((rows) {
      final posts = rows.map(FeedPost.fromMap).where((p) {
        // REVEAL GATING: you only see a task's entries once you've posted yours.
        if (!unlockedTaskIds.contains(p.taskId)) return false;
        // Never your own post, never one you've already graded.
        if (p.userId == viewerId) return false;
        if (p.graderIds.contains(viewerId)) return false;
        return true;
      }).toList();

      posts.sort(_queueOrder);
      return posts;
    });
  }

  /// Boosted first, then fewest grades, then most taps, then newest.
  static int _queueOrder(FeedPost a, FeedPost b) {
    if (a.boosted != b.boosted) return a.boosted ? -1 : 1;
    final byGrades = a.gradeCount.compareTo(b.gradeCount);
    if (byGrades != 0) return byGrades;
    final byTaps = b.tapCount.compareTo(a.tapCount);
    if (byTaps != 0) return byTaps;
    return b.createdAt.compareTo(a.createdAt);
  }

  @override
  Stream<List<FeedPost>> watchPostsForTask({
    required String gameId,
    required String taskId,
  }) {
    return remoteDataSource.watchPostsForTask(gameId, taskId).map((rows) {
      final posts = rows.map(FeedPost.fromMap).toList();
      // Playback order: oldest first, newest last.
      posts.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return posts;
    });
  }

  @override
  Future<void> tapPost(String postId, {int taps = 1}) =>
      remoteDataSource.tapPost(postId, taps: taps);

  @override
  Stream<Set<String>> watchUnlockedTaskIds(String userId) {
    // Every submission creates a post, so the user's own posts ARE the record
    // of what they have submitted — no game read needed.
    return remoteDataSource
        .watchPostsByUser(userId)
        .map((rows) => rows
            .map((r) => r['taskId'] as String? ?? '')
            .where((id) => id.isNotEmpty)
            .toSet());
  }

  @override
  Future<void> gradePost({
    required String postId,
    required String graderId,
    required int score,
  }) {
    if (score < 1 || score > 5) {
      throw ArgumentError.value(score, 'score', 'Grades run 1..5');
    }
    return remoteDataSource.gradePost(
      postId: postId,
      graderId: graderId,
      score: score,
    );
  }

  @override
  Stream<FeedPost?> watchPost(String postId) {
    return remoteDataSource
        .watchPost(postId)
        .map((row) => row == null ? null : FeedPost.fromMap(row));
  }

  @override
  Stream<List<FeedPost>> watchPostsByUser(String userId) {
    return remoteDataSource.watchPostsByUser(userId).map((rows) {
      final posts = rows.map(FeedPost.fromMap).toList();
      posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return posts;
    });
  }

  @override
  Future<int> gradedCountBy(String userId) =>
      remoteDataSource.gradedCountBy(userId);

  @override
  Future<void> boostPostsOf(String userId) =>
      remoteDataSource.boostPostsOf(userId, belowGradeCount: boostBelowGrades);

  @override
  Future<void> ensureHouseEntries() {
    return remoteDataSource.ensureHouseEntries(houseEntryPosts());
  }

  /// The seeded house entries as raw documents, with deterministic ids.
  /// Exposed so tests (and the Firestore source) can assert the exact shape.
  static List<Map<String, dynamic>> houseEntryPosts() {
    final tasks = StarterPackData.tasks();
    return [
      for (final task in tasks)
        if (StarterPackData.houseEntries[task.id] != null)
          FeedPost(
            id: houseIdFor(task.id),
            gameId: '',
            taskId: task.id,
            taskTitle: task.title,
            rubric: task.rubric,
            userId: houseUserId,
            displayName: StarterPackData.housePosterName,
            mediaType: SubmissionMediaType.text,
            text: StarterPackData.houseEntries[task.id],
            caption: task.twist,
            stamp: Stamps.art,
            isHouse: true,
            // Fixed epoch so the seeds sort last by recency and seeding is
            // byte-for-byte identical every time.
            createdAt: DateTime.utc(2026, 1, 1),
          ).toMap(),
    ];
  }
}
