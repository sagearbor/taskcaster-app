import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/models/submission.dart';
import 'package:taskcaster_app/features/arena/domain/models/feed_post.dart';

FeedPost buildPost({
  String id = 'post-1',
  int gradeCount = 0,
  int gradeSum = 0,
  int tapCount = 0,
  bool boosted = false,
  List<String> graderIds = const [],
}) {
  return FeedPost(
    id: id,
    gameId: 'game-1',
    taskId: 'starter-01',
    taskTitle: 'A vegetable that has just received terrible news',
    rubric: 'Emotional truth of the vegetable.',
    userId: 'user-1',
    displayName: 'Alice',
    mediaType: SubmissionMediaType.text,
    text: 'A courgette, mid-collapse.',
    caption: 'No text on the vegetable. · Done in 41 s',
    stamp: Stamps.nailedIt,
    createdAt: DateTime.parse('2026-09-12T10:00:00.000Z'),
    elapsedSeconds: 41,
    gradeCount: gradeCount,
    gradeSum: gradeSum,
    boosted: boosted,
    tapCount: tapCount,
    graderIds: graderIds,
  );
}

void main() {
  group('Stamps', () {
    test('has exactly the six product stamps', () {
      expect(Stamps.values, [
        'NAILED IT',
        'TECHNICALLY',
        'NO REGRETS',
        "DON'T ASK",
        'ART',
        'SEND HELP',
      ]);
    });
  });

  group('FeedPost serialization', () {
    test('round-trips every field, graderIds included', () {
      final post = buildPost(
        gradeCount: 2,
        gradeSum: 8,
        tapCount: 4,
        boosted: true,
        graderIds: const ['user-2', 'user-3'],
      );
      final restored = FeedPost.fromMap(post.toMap());
      expect(restored, post);
      expect(restored.graderIds, ['user-2', 'user-3']);
      expect(restored.createdAt, post.createdAt);
    });

    test('a map with only the required keys fills in sane defaults', () {
      final sparse = FeedPost.fromMap({
        'id': 'post-9',
        'gameId': 'game-1',
        'taskId': 'starter-03',
        'taskTitle': 'Rename a household object',
        'userId': 'user-4',
        'displayName': 'Bob',
        'createdAt': '2026-09-12T10:00:00.000Z',
      });
      expect(sparse.mediaType, SubmissionMediaType.link);
      expect(sparse.gradeCount, 0);
      expect(sparse.gradeSum, 0);
      expect(sparse.tapCount, 0);
      expect(sparse.boosted, isFalse);
      expect(sparse.isLate, isFalse);
      expect(sparse.isHouse, isFalse);
      expect(sparse.graderIds, isEmpty);
    });

    test('graderIds is persisted but stays out of equality', () {
      final a = buildPost(graderIds: const []);
      final b = buildPost(graderIds: const ['user-2']);
      expect(a, b);
      expect(a.toMap()['graderIds'], isEmpty);
      expect(b.toMap()['graderIds'], ['user-2']);
    });

    test('copyWith replaces only what it is given', () {
      final post = buildPost();
      final copy = post.copyWith(gradeCount: 1, gradeSum: 4);
      expect(copy.gradeCount, 1);
      expect(copy.gradeSum, 4);
      expect(copy.taskId, post.taskId);
      expect(copy.stamp, post.stamp);
    });
  });

  group('FeedPost.meanGrade / crowdPoints', () {
    test('are null until somebody grades', () {
      final post = buildPost();
      expect(post.meanGrade, isNull);
      expect(post.crowdPoints, isNull);
    });

    test('mean is the plain average', () {
      expect(buildPost(gradeCount: 2, gradeSum: 7).meanGrade, 3.5);
    });

    test('points are round(mean x 2)', () {
      expect(buildPost(gradeCount: 1, gradeSum: 5).crowdPoints, 10);
      expect(buildPost(gradeCount: 1, gradeSum: 1).crowdPoints, 2);
      expect(buildPost(gradeCount: 2, gradeSum: 7).crowdPoints, 7);
      expect(buildPost(gradeCount: 3, gradeSum: 10).crowdPoints, 7);
    });

    test('points clamp to 0..10 even for nonsense counters', () {
      expect(buildPost(gradeCount: 1, gradeSum: 50).crowdPoints, 10);
      expect(buildPost(gradeCount: 1, gradeSum: -4).crowdPoints, 0);
    });
  });

  group("FeedPost.displayStamp (DON'T ASK)", () {
    test('shows the auto-stamp below the tap threshold', () {
      expect(buildPost(tapCount: 2).displayStamp, Stamps.nailedIt);
    });

    test('flips to DON\'T ASK at three taps', () {
      expect(buildPost(tapCount: 3).displayStamp, Stamps.dontAsk);
      expect(buildPost(tapCount: 40).displayStamp, Stamps.dontAsk);
    });
  });
}
