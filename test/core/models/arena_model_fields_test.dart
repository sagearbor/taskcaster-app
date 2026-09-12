import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/models/game.dart';
import 'package:taskcaster_app/core/models/game_settings.dart';
import 'package:taskcaster_app/core/models/submission.dart';
import 'package:taskcaster_app/core/models/task.dart';

/// Round 7 added fields to four existing models. Every one of them has to
/// survive a toMap/fromMap round trip AND deserialize sensibly from a map
/// written before the field existed — real Firestore documents out there have
/// none of these keys.
void main() {
  group('Task submissionType / rubric / twist', () {
    final task = Task(
      id: 'starter-01',
      title: 'A vegetable that has just received terrible news',
      description: 'Find a vegetable.',
      taskType: TaskType.video,
      submissions: const [],
      submissionType: SubmissionType.photo,
      rubric: 'Emotional truth of the vegetable.',
      twist: 'No text on the vegetable.',
      durationSeconds: 90,
    );

    test('round-trips through toMap/fromMap', () {
      final restored = Task.fromMap(task.toMap());
      expect(restored.submissionType, SubmissionType.photo);
      expect(restored.rubric, 'Emotional truth of the vegetable.');
      expect(restored.twist, 'No text on the vegetable.');
      expect(restored.durationSeconds, 90);
      expect(restored, task);
    });

    test('a map with none of the new keys parses as an unrestricted task', () {
      final legacy = Task.fromMap({
        'id': 'task-1',
        'title': 'Old task',
        'description': 'Written before the Arena existed',
        'taskType': 'video',
        'submissions': <dynamic>[],
      });
      expect(legacy.submissionType, SubmissionType.any);
      expect(legacy.rubric, isNull);
      expect(legacy.twist, isNull);
    });

    test('an unknown submissionType falls back to any', () {
      final odd = Task.fromMap({
        'id': 'task-1',
        'title': 'Odd task',
        'description': 'From a newer client',
        'taskType': 'video',
        'submissions': <dynamic>[],
        'submissionType': 'hologram',
      });
      expect(odd.submissionType, SubmissionType.any);
    });

    test('copyWith carries the new fields', () {
      final copy = task.copyWith(
        submissionType: SubmissionType.text,
        rubric: 'Would you buy it.',
      );
      expect(copy.submissionType, SubmissionType.text);
      expect(copy.rubric, 'Would you buy it.');
      expect(copy.twist, task.twist);
    });

    test('the new fields take part in equality', () {
      expect(task.copyWith(rubric: 'Something else'), isNot(task));
      expect(task.copyWith(submissionType: SubmissionType.any), isNot(task));
    });
  });

  group('Submission Arena fields', () {
    final submittedAt = DateTime.parse('2026-09-12T10:00:00.000');
    final submission = Submission(
      id: 'sub-1',
      userId: 'user-1',
      score: 0,
      isJudged: false,
      submittedAt: submittedAt,
      mediaType: SubmissionMediaType.photo,
      text: null,
      caption: 'No text on the vegetable. · Done in 41 s',
      stamp: 'NAILED IT',
      isLate: false,
      elapsedSeconds: 41,
      feedPostId: 'post-9',
    );

    test('round-trips through toMap/fromMap', () {
      final restored = Submission.fromMap(submission.toMap());
      expect(restored, submission);
      expect(restored.mediaType, SubmissionMediaType.photo);
      expect(restored.stamp, 'NAILED IT');
      expect(restored.feedPostId, 'post-9');
      expect(restored.elapsedSeconds, 41);
    });

    test('a legacy map parses as a not-late video link with no post', () {
      final legacy = Submission.fromMap({
        'id': 'sub-old',
        'userId': 'user-1',
        'videoUrl': 'https://youtu.be/abc',
        'score': 7,
        'isJudged': true,
        'submittedAt': submittedAt.toIso8601String(),
      });
      expect(legacy.mediaType, SubmissionMediaType.link);
      expect(legacy.isLate, isFalse);
      expect(legacy.text, isNull);
      expect(legacy.caption, isNull);
      expect(legacy.stamp, isNull);
      expect(legacy.elapsedSeconds, isNull);
      expect(legacy.feedPostId, isNull);
      expect(legacy.score, 7);
    });

    test('an unknown mediaType falls back to link', () {
      final odd = Submission.fromMap({
        'id': 'sub-odd',
        'userId': 'user-1',
        'score': 0,
        'isJudged': false,
        'submittedAt': submittedAt.toIso8601String(),
        'mediaType': 'hologram',
      });
      expect(odd.mediaType, SubmissionMediaType.link);
    });

    test('copyWith carries the new fields', () {
      final copy = submission.copyWith(isLate: true, stamp: 'SEND HELP');
      expect(copy.isLate, isTrue);
      expect(copy.stamp, 'SEND HELP');
      expect(copy.feedPostId, 'post-9');
    });

    test('the new fields take part in equality', () {
      expect(submission.copyWith(isLate: true), isNot(submission));
      expect(submission.copyWith(feedPostId: 'other'), isNot(submission));
    });
  });

  group('GameSettings crowdJudged / shareToArena', () {
    test('round-trips through toMap/fromMap', () {
      const settings = GameSettings(crowdJudged: true, shareToArena: false);
      final restored = GameSettings.fromMap(settings.toMap());
      expect(restored.crowdJudged, isTrue);
      expect(restored.shareToArena, isFalse);
      expect(restored, settings);
    });

    test('a legacy map is human-judged and shares by default', () {
      final legacy = GameSettings.fromMap({
        'autoAdvanceTasks': true,
        'allowSkips': false,
      });
      expect(legacy.crowdJudged, isFalse);
      expect(legacy.shareToArena, isTrue);
    });

    test('the defaults match the product rules', () {
      const settings = GameSettings();
      expect(settings.crowdJudged, isFalse);
      expect(settings.shareToArena, isTrue);
    });

    test('copyWith carries the new fields', () {
      const settings = GameSettings();
      final copy = settings.copyWith(crowdJudged: true);
      expect(copy.crowdJudged, isTrue);
      expect(copy.shareToArena, isTrue);
    });
  });

  group('Game.isStarter', () {
    Game gameWithKind(String? kind) => Game(
          id: 'g1',
          gameName: 'Your First Ten',
          creatorId: 'u1',
          judgeId: 'u1',
          status: GameStatus.inProgress,
          inviteCode: 'ABC123',
          createdAt: DateTime.parse('2026-09-12T10:00:00.000'),
          players: const [],
          tasks: const [],
          settings: const GameSettings(),
          gameKind: kind,
        );

    test('kindStarter is the literal the data layer writes', () {
      expect(Game.kindStarter, 'starter');
    });

    test('is true only for a starter game', () {
      expect(gameWithKind('starter').isStarter, isTrue);
      expect(gameWithKind('house_hunt').isStarter, isFalse);
      expect(gameWithKind(null).isStarter, isFalse);
    });

    test('survives a round trip', () {
      final restored = Game.fromMap(gameWithKind('starter').toMap());
      expect(restored.isStarter, isTrue);
    });
  });
}
