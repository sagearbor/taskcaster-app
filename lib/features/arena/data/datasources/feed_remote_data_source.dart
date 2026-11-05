/// Firestore's cap on the number of values in one `whereIn` filter.
const int whereInLimit = 10;

/// One read of the grading queue.
class QueuePage {
  /// Raw post documents, each with its `id`.
  final List<Map<String, dynamic>> rows;

  /// True when at least one chunk came back full, i.e. a bigger limit could
  /// return more rows.
  final bool hasMore;

  const QueuePage(this.rows, {required this.hasMore});
}

/// Map-based transport for the Arena's `feed_posts` collection, mirroring the
/// shape of `GameRemoteDataSource`: raw documents in, raw documents out, with
/// every model concern left to `FeedRepositoryImpl`.
abstract class FeedRemoteDataSource {
  /// Write a post document. [data] may carry an `id`; when it is null or empty
  /// the store picks one. Returns the id actually written.
  Future<String> createPost(Map<String, dynamic> data);

  /// The grading queue's raw rows: posts whose `taskId` is in [taskIds],
  /// ordered fewest grades first, then newest, at most [limit] per chunk of
  /// [whereInLimit] task ids (Firestore's `whereIn` cap). The repository
  /// applies the own-post/already-graded exclusions and the final ordering
  /// client-side, and asks for a bigger [limit] when those exclusions leave
  /// the page short and [QueuePage.hasMore] says there is more to read.
  Stream<QueuePage> watchQueuePage({
    required List<String> taskIds,
    required int limit,
  });

  /// Every post for one task of one game (`gameId` AND `taskId` filtered
  /// server-side).
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
  ///
  /// In-memory only: on Firestore the rules deny every client write to a
  /// house post, and they are seeded with the Admin SDK instead
  /// (`functions/scripts/seed_house_posts.js`), so the Firestore source
  /// implements this as a no-op.
  Future<void> ensureHouseEntries(List<Map<String, dynamic>> posts);
}
