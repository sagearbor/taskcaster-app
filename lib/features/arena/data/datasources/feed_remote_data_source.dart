/// Map-based transport for the Arena's `feed_posts` collection, mirroring the
/// shape of `GameRemoteDataSource`: raw documents in, raw documents out, with
/// every model concern left to `FeedRepositoryImpl`.
abstract class FeedRemoteDataSource {
  /// Write a post document. [data] may carry an `id`; when it is null or empty
  /// the store picks one. Returns the id actually written.
  Future<String> createPost(Map<String, dynamic> data);

  /// The newest [limit] posts. The repository applies the reveal gate, the
  /// own-post/already-graded exclusions and the queue ordering client-side —
  /// which is also what keeps this a single-field query with no composite
  /// index.
  Stream<List<Map<String, dynamic>>> watchRecentPosts({int limit = 30});

  /// Every post for one task of one game.
  Stream<List<Map<String, dynamic>>> watchPostsForTask(
    String gameId,
    String taskId,
  );

  /// Every post by one user.
  Stream<List<Map<String, dynamic>>> watchPostsByUser(String userId);

  Stream<Map<String, dynamic>?> watchPost(String postId);

  /// Record a 1..5 grade from [graderId] and bump the denormalized counters in
  /// one atomic step. Throws [StateError] when [graderId] owns the post or has
  /// already graded it.
  Future<void> gradePost({
    required String postId,
    required String graderId,
    required int score,
  });

  /// Increment a post's viewer-tap counter and, when [atSecond] is given, the
  /// `tapSeconds.<atSecond>` bucket, in the SAME write.
  Future<void> tapPost(String postId, {int taps = 1, int? atSecond});

  /// How many posts [userId] has graded.
  Future<int> gradedCountBy(String userId);

  /// Mark [userId]'s posts with fewer than [belowGradeCount] grades as boosted.
  Future<void> boostPostsOf(String userId, {required int belowGradeCount});

  /// Write the seeded house entries. Each map carries its own deterministic
  /// `id`, so re-running this is a no-op rather than a duplicate.
  Future<void> ensureHouseEntries(List<Map<String, dynamic>> posts);
}
