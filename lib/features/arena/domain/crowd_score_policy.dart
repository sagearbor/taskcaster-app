import 'models/feed_post.dart';

/// When a crowd-graded post's score stops moving and locks into the game.
///
/// Three grades settle it; a single grade settles it after half an hour, so a
/// lone tester still gets a score but one passing stranger cannot decide a
/// fresh post on their own.
class CrowdScorePolicy {
  const CrowdScorePolicy._();

  /// Grades needed to lock a score in immediately.
  static const int finalGrades = 3;

  /// How long a post with at least one grade waits before that grade counts.
  static const Duration soloLock = Duration(minutes: 30);

  static bool isFinal(FeedPost post, {DateTime? now}) {
    if (post.gradeCount >= finalGrades) return true;
    if (post.gradeCount < 1) return false;
    final at = now ?? DateTime.now();
    return at.difference(post.createdAt) >= soloLock;
  }

  /// Task points this post is worth: `round(mean x 2)` clamped to 0..10, and
  /// 0 when nobody has graded it.
  static int points(FeedPost post) => post.crowdPoints ?? 0;
}
