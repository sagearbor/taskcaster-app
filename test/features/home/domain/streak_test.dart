import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/models/submission.dart';
import 'package:taskcaster_app/features/arena/domain/models/feed_post.dart';
import 'package:taskcaster_app/features/home/domain/streak.dart';

FeedPost post(DateTime at, {bool isHouse = false, String taskId = 'daily-01'}) =>
    FeedPost(
      id: 'p-${at.toIso8601String()}',
      gameId: 'g',
      taskId: taskId,
      taskTitle: 't',
      userId: 'me',
      displayName: 'Me',
      mediaType: SubmissionMediaType.text,
      text: 'x',
      isHouse: isHouse,
      createdAt: at,
    );

void main() {
  final now = DateTime.utc(2026, 11, 9, 12);
  DateTime daysAgo(int n, {int hour = 10}) =>
      DateTime.utc(2026, 11, 9 - n, hour);

  test('no posts, no streak', () {
    expect(currentStreak(const [], now), 0);
    expect(postedToday(const [], now), isFalse);
    expect(streakAtRisk(const [], now), isFalse);
  });

  test('one post today is a streak of 1 (starter posts count on day one)', () {
    final posts = [post(daysAgo(0), taskId: 'starter-03')];
    expect(currentStreak(posts, now), 1);
    expect(postedToday(posts, now), isTrue);
    expect(streakAtRisk(posts, now), isFalse);
  });

  test('several posts on the same day count once', () {
    final posts = [post(daysAgo(0, hour: 1)), post(daysAgo(0, hour: 9))];
    expect(currentStreak(posts, now), 1);
  });

  test('consecutive days ending today', () {
    final posts = [post(daysAgo(0)), post(daysAgo(1)), post(daysAgo(2))];
    expect(currentStreak(posts, now), 3);
  });

  test('ending yesterday is still alive, and at risk', () {
    final posts = [post(daysAgo(1)), post(daysAgo(2))];
    expect(currentStreak(posts, now), 2);
    expect(postedToday(posts, now), isFalse);
    expect(streakAtRisk(posts, now), isTrue);
  });

  test('ending the day before yesterday is gone', () {
    final posts = [post(daysAgo(2)), post(daysAgo(3))];
    expect(currentStreak(posts, now), 0);
    expect(streakAtRisk(posts, now), isFalse);
  });

  test('a gap breaks the run: only the days after it count', () {
    final posts = [
      post(daysAgo(0)),
      post(daysAgo(1)),
      // daysAgo(2) missing
      post(daysAgo(3)),
      post(daysAgo(4)),
    ];
    expect(currentStreak(posts, now), 2);
  });

  test('order of posts does not matter', () {
    final posts = [post(daysAgo(2)), post(daysAgo(0)), post(daysAgo(1))];
    expect(currentStreak(posts, now), 3);
  });

  test('house posts and unknown timestamps never count', () {
    final posts = [
      post(daysAgo(0), isHouse: true),
      post(FeedPost.unknownCreatedAt),
    ];
    expect(currentStreak(posts, now), 0);
    expect(postedToday(posts, now), isFalse);
  });

  group('UTC day edges', () {
    test('23:59 UTC yesterday then 00:01 UTC today: two days', () {
      final at = DateTime.utc(2026, 11, 9, 0, 1);
      final posts = [
        post(DateTime.utc(2026, 11, 8, 23, 59)),
        post(DateTime.utc(2026, 11, 9, 0, 0, 30)),
      ];
      expect(currentStreak(posts, at), 2);
    });

    test('just after UTC midnight, yesterday-only is at risk not lost', () {
      final at = DateTime.utc(2026, 11, 9, 0, 1);
      final posts = [post(DateTime.utc(2026, 11, 8, 23, 59))];
      expect(currentStreak(posts, at), 1);
      expect(streakAtRisk(posts, at), isTrue);
    });

    test('local times are bucketed by their UTC day', () {
      // Both are 9 Nov in New York, but 9 Nov and 10 Nov in UTC.
      final evening = DateTime.parse('2026-11-09T20:00:00-05:00'); // 10 Nov 01:00Z
      final morning = DateTime.parse('2026-11-09T08:00:00-05:00'); // 9 Nov 13:00Z
      final at = DateTime.utc(2026, 11, 10, 2);
      expect(currentStreak([post(morning), post(evening)], at), 2);
    });

    test('now given in local time is read as UTC', () {
      final posts = [post(DateTime.utc(2026, 11, 10, 1))];
      // 2026-11-09 21:00 at UTC-5 = 10 Nov 02:00Z: the post is "today".
      final localNow = DateTime.parse('2026-11-09T21:00:00-05:00');
      expect(postedToday(posts, localNow), isTrue);
    });
  });
}
