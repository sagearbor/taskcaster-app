import '../models/feed_post.dart';

/// The Arena: every submission becomes a [FeedPost], and posting is what
/// unlocks other people's attempts at the same task.
abstract class FeedRepository {
  /// Create a post. [post].id may be empty — the id actually written is
  /// returned.
  Future<String> createPost(FeedPost post);

  /// The grading queue for [viewerId].
  ///
  /// REVEAL GATING: only posts whose taskId is in [unlockedTaskIds] (task ids
  /// the viewer has submitted, in any game). Excludes the viewer's own posts
  /// and posts the viewer has already graded. House posts are included.
  /// Order: boosted first, then fewest grades, then tapCount desc, then newest.
  Stream<List<FeedPost>> watchQueue({
    required String viewerId,
    required Set<String> unlockedTaskIds,
    int limit = 30,
  });

  /// Every entry for one task of one game, oldest first — the "Watch together"
  /// playback order.
  Stream<List<FeedPost>> watchPostsForTask({
    required String gameId,
    required String taskId,
  });

  /// Viewer "that's funny" tap. Fire-and-forget safe: never throws for the
  /// caller's purposes and never blocks playback.
  ///
  /// [atSecond] is the second of the clip the viewer was watching (from
  /// `VideoPolicy.tapBucket`), and null for a post with no timeline. When it
  /// is set, the same write also bumps `tapSeconds.<atSecond>` — the
  /// per-second histogram future automatic editing trims on.
  Future<void> tapPost(String postId, {int taps = 1, int? atSecond});

  /// Task ids [userId] has submitted, i.e. what they have unlocked. Derived
  /// from their own posts (every submission creates one).
  Stream<Set<String>> watchUnlockedTaskIds(String userId);

  /// Record a 1..5 crowd grade. One grade per user per post.
  /// Throws [StateError] when grading your own post or grading twice.
  Future<void> gradePost({
    required String postId,
    required String graderId,
    required int score,
  });

  Stream<FeedPost?> watchPost(String postId);

  /// [userId]'s own posts, newest first.
  Stream<List<FeedPost>> watchPostsByUser(String userId);

  /// How many posts [userId] has graded.
  Future<int> gradedCountBy(String userId);

  /// Grade-to-get-graded: mark [userId]'s still-hungry posts (gradeCount < 3)
  /// as boosted so they sort to the front of everyone's queue.
  Future<void> boostPostsOf(String userId);

  /// Seed the house entries for the Starter Pack. Idempotent.
  Future<void> ensureHouseEntries();
}
