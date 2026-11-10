import '../../arena/domain/models/feed_post.dart';
import '../../tasks/data/datasources/daily_task_data.dart';

/// The 🔥 streak (WP-6): consecutive UTC days on which the player posted at
/// least one entry, ending today or yesterday.
///
/// Derived entirely from the player's own posts (`FeedRepository
/// .watchPostsByUser`), so there is no stored counter to drift and nothing
/// for the backend to do. Any post counts: a Starter Pack task, today's task,
/// a friend game entry. So day one already shows "🔥 1".
///
/// A streak that ended yesterday is still alive (the player has until UTC
/// midnight to keep it); one that ended the day before is 0.
///
/// [now] is any time zone; days are UTC days, like the daily task itself.
int currentStreak(Iterable<FeedPost> myPosts, DateTime now) {
  final days = postDays(myPosts);
  if (days.isEmpty) return 0;

  final today = DailyTaskData.daysSinceEpochUtc(now);
  var day = days.contains(today) ? today : today - 1;
  var streak = 0;
  while (days.contains(day)) {
    streak++;
    day--;
  }
  return streak;
}

/// True when the player has posted anything on [now]'s UTC day.
bool postedToday(Iterable<FeedPost> myPosts, DateTime now) =>
    postDays(myPosts).contains(DailyTaskData.daysSinceEpochUtc(now));

/// True when the streak is alive but today has no post yet: the player
/// loses it at the next UTC midnight unless they post.
bool streakAtRisk(Iterable<FeedPost> myPosts, DateTime now) =>
    !postedToday(myPosts, now) && currentStreak(myPosts, now) > 0;

/// The UTC days (as days since the epoch) on which there is a post. House
/// posts never count, and neither does a post whose `createdAt` is unknown
/// (it parses to the epoch; a pending server timestamp lands moments later).
Set<int> postDays(Iterable<FeedPost> myPosts) {
  return {
    for (final p in myPosts)
      if (!p.isHouse && !p.createdAt.isAtSameMomentAs(FeedPost.unknownCreatedAt))
        DailyTaskData.daysSinceEpochUtc(p.createdAt),
  };
}
