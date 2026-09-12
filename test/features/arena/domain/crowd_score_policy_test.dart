import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/models/submission.dart';
import 'package:taskcaster_app/features/arena/domain/crowd_score_policy.dart';
import 'package:taskcaster_app/features/arena/domain/models/feed_post.dart';

final _created = DateTime.parse('2026-09-12T10:00:00.000Z');

FeedPost post({required int gradeCount, required int gradeSum}) {
  return FeedPost(
    id: 'post-1',
    gameId: 'game-1',
    taskId: 'starter-01',
    taskTitle: 'A vegetable that has just received terrible news',
    userId: 'user-1',
    displayName: 'Alice',
    mediaType: SubmissionMediaType.text,
    createdAt: _created,
    gradeCount: gradeCount,
    gradeSum: gradeSum,
  );
}

void main() {
  group('CrowdScorePolicy.isFinal', () {
    test('an ungraded post is never final, however old', () {
      expect(
        CrowdScorePolicy.isFinal(
          post(gradeCount: 0, gradeSum: 0),
          now: _created.add(const Duration(days: 3)),
        ),
        isFalse,
      );
    });

    test('three grades settle it immediately', () {
      expect(
        CrowdScorePolicy.isFinal(
          post(gradeCount: 3, gradeSum: 9),
          now: _created.add(const Duration(seconds: 5)),
        ),
        isTrue,
      );
    });

    test('more than three grades is still final', () {
      expect(
        CrowdScorePolicy.isFinal(
          post(gradeCount: 7, gradeSum: 20),
          now: _created,
        ),
        isTrue,
      );
    });

    test('one fresh grade does not settle it — a stranger cannot decide alone',
        () {
      expect(
        CrowdScorePolicy.isFinal(
          post(gradeCount: 1, gradeSum: 5),
          now: _created.add(const Duration(minutes: 29)),
        ),
        isFalse,
      );
    });

    test('one grade settles it after 30 minutes, so a lone tester scores', () {
      expect(
        CrowdScorePolicy.isFinal(
          post(gradeCount: 1, gradeSum: 5),
          now: _created.add(const Duration(minutes: 30)),
        ),
        isTrue,
      );
    });

    test('two grades also settle after the solo lock', () {
      expect(
        CrowdScorePolicy.isFinal(
          post(gradeCount: 2, gradeSum: 6),
          now: _created.add(const Duration(hours: 2)),
        ),
        isTrue,
      );
    });

    test('the thresholds are the documented ones', () {
      expect(CrowdScorePolicy.finalGrades, 3);
      expect(CrowdScorePolicy.soloLock, const Duration(minutes: 30));
    });
  });

  group('CrowdScorePolicy.points', () {
    test('an ungraded post is worth nothing', () {
      expect(CrowdScorePolicy.points(post(gradeCount: 0, gradeSum: 0)), 0);
    });

    test('a straight 5 is worth the full 10', () {
      expect(CrowdScorePolicy.points(post(gradeCount: 1, gradeSum: 5)), 10);
    });

    test('the mean is doubled and rounded', () {
      expect(CrowdScorePolicy.points(post(gradeCount: 3, gradeSum: 10)), 7);
      expect(CrowdScorePolicy.points(post(gradeCount: 4, gradeSum: 10)), 5);
    });
  });
}
