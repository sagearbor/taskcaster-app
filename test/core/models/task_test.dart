import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/models/task.dart';
import 'package:taskcaster_app/core/models/submission.dart';

void main() {
  group('Task Model Tests', () {
    late Task videoTask;
    late Task puzzleTask;
    late List<Submission> testSubmissions;

    setUp(() {
      testSubmissions = [
        Submission(
          id: 'sub1',
          userId: 'user1',
          videoUrl: 'https://youtube.com/watch?v=test',
          textAnswer: null,
          score: 5,
          isJudged: true,
          submittedAt: DateTime.now(),
        ),
        Submission(
          id: 'sub2',
          userId: 'user2',
          videoUrl: null,
          textAnswer: 'Test answer',
          score: 0,
          isJudged: false,
          submittedAt: DateTime.now(),
        ),
      ];

      videoTask = Task(
        id: 'task1',
        title: 'Video Task',
        description: 'Record a video',
        taskType: TaskType.video,
        submissions: testSubmissions,
      );

      puzzleTask = Task(
        id: 'task2',
        title: 'Puzzle Task',
        description: 'Solve this riddle',
        taskType: TaskType.puzzle,
        puzzleAnswer: 'keyboard',
        submissions: [],
      );
    });

    test('should create task with all required fields', () {
      expect(videoTask.id, 'task1');
      expect(videoTask.title, 'Video Task');
      expect(videoTask.description, 'Record a video');
      expect(videoTask.taskType, TaskType.video);
      expect(videoTask.submissions, testSubmissions);
    });

    test('should correctly identify task types', () {
      expect(videoTask.isVideoTask, true);
      expect(videoTask.isPuzzleTask, false);

      expect(puzzleTask.isVideoTask, false);
      expect(puzzleTask.isPuzzleTask, true);
    });

    test('should find submission by user ID', () {
      final submission = videoTask.getSubmissionByUser('user1');
      expect(submission, isNotNull);
      expect(submission!.videoUrl, 'https://youtube.com/watch?v=test');

      final nonExistentSubmission = videoTask.getSubmissionByUser('user999');
      expect(nonExistentSubmission, isNull);
    });

    test('should check if user has submitted', () {
      expect(videoTask.hasUserSubmitted('user1'), true);
      expect(videoTask.hasUserSubmitted('user2'), true);
      expect(videoTask.hasUserSubmitted('user999'), false);
    });

    test('should count total submissions', () {
      expect(videoTask.getTotalSubmissions(), 2);
      expect(puzzleTask.getTotalSubmissions(), 0);
    });

    test('should count judged submissions', () {
      expect(videoTask.getJudgedSubmissions(), 1);
      expect(puzzleTask.getJudgedSubmissions(), 0);
    });

    test('should check if all submissions are judged', () {
      expect(videoTask.allSubmissionsJudged, false);
      expect(puzzleTask.allSubmissionsJudged, false); // No submissions

      final allJudgedTask = videoTask.copyWith(
        submissions: testSubmissions.map((s) => s.copyWith(isJudged: true)).toList(),
      );
      expect(allJudgedTask.allSubmissionsJudged, true);
    });

    test('should convert to/from map correctly', () {
      final map = videoTask.toMap();
      final reconstructedTask = Task.fromMap(map);

      expect(reconstructedTask.id, videoTask.id);
      expect(reconstructedTask.title, videoTask.title);
      expect(reconstructedTask.taskType, videoTask.taskType);
      expect(reconstructedTask.submissions.length, videoTask.submissions.length);
    });

    test('should create copy with modified fields', () {
      final modifiedTask = videoTask.copyWith(
        title: 'Modified Title',
        description: 'Modified Description',
      );

      expect(modifiedTask.title, 'Modified Title');
      expect(modifiedTask.description, 'Modified Description');
      expect(modifiedTask.id, videoTask.id); // Unchanged
      expect(modifiedTask.taskType, videoTask.taskType); // Unchanged
    });

    test('should identify AR tasks and round-trip AR fields through map', () {
      final arTask = Task(
        id: 'ar-task',
        title: 'Balloon Pop',
        description: 'Pop as many balloons as you can',
        taskType: TaskType.ar,
        arGameId: 'balloon_pop',
        arResult: 12,
        submissions: const [],
      );

      // Type predicates.
      expect(arTask.isArTask, true);
      expect(arTask.isVideoTask, false);
      expect(arTask.isPuzzleTask, false);

      // Serialization round-trip preserves the AR-specific fields.
      final map = arTask.toMap();
      expect(map['taskType'], 'ar');
      expect(map['arGameId'], 'balloon_pop');
      expect(map['arResult'], 12);

      final restored = Task.fromMap(map);
      expect(restored.taskType, TaskType.ar);
      expect(restored.isArTask, true);
      expect(restored.arGameId, 'balloon_pop');
      expect(restored.arResult, 12);
      expect(restored, equals(arTask));
    });

    test('old serialized tasks without AR keys decode to null/video', () {
      // Simulates legacy data persisted before the AR fields existed.
      final legacyMap = {
        'id': 'legacy',
        'title': 'Legacy task',
        'description': 'No AR keys here',
        'taskType': 'video',
        'submissions': <dynamic>[],
      };

      final restored = Task.fromMap(legacyMap);
      expect(restored.taskType, TaskType.video);
      expect(restored.arGameId, isNull);
      expect(restored.arResult, isNull);
      expect(restored.isArTask, false);
    });

    test('category round-trips through map and copyWith', () {
      final categorized = videoTask.copyWith(category: 'Quick & Silly');
      expect(categorized.category, 'Quick & Silly');

      final map = categorized.toMap();
      expect(map['category'], 'Quick & Silly');

      final restored = Task.fromMap(map);
      expect(restored.category, 'Quick & Silly');
      expect(restored, equals(categorized));

      // Category participates in equality.
      expect(videoTask, isNot(equals(categorized)));
    });

    test('old serialized tasks without a category key decode to null', () {
      final legacyMap = {
        'id': 'legacy',
        'title': 'Legacy task',
        'description': 'No category key here',
        'taskType': 'video',
        'submissions': <dynamic>[],
      };

      final restored = Task.fromMap(legacyMap);
      expect(restored.category, isNull);
    });

    test('should handle puzzle answers correctly', () {
      expect(puzzleTask.puzzleAnswer, 'keyboard');
      expect(videoTask.puzzleAnswer, isNull);
    });

    test('should handle equality correctly', () {
      final identicalTask = Task(
        id: videoTask.id,
        title: videoTask.title,
        description: videoTask.description,
        taskType: videoTask.taskType,
        submissions: videoTask.submissions,
      );

      expect(videoTask, equals(identicalTask));

      final differentTask = videoTask.copyWith(title: 'Different Title');
      expect(videoTask, isNot(equals(differentTask)));
    });
  });
}