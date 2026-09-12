import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/models/task.dart';
import 'package:taskcaster_app/features/tasks/data/datasources/starter_pack_data.dart';

void main() {
  final tasks = StarterPackData.tasks();

  group('StarterPackData.tasks', () {
    test('is exactly the ten starter tasks', () {
      expect(tasks.length, 10);
    });

    test('ids are starter-01..starter-10, in order', () {
      expect(
        tasks.map((t) => t.id),
        [for (var i = 1; i <= 10; i++) 'starter-${i.toString().padLeft(2, '0')}'],
      );
    });

    test('ids are unique', () {
      expect(tasks.map((t) => t.id).toSet().length, tasks.length);
    });

    test('every task can be done with a phone: photo or text only', () {
      for (final task in tasks) {
        expect(
          task.submissionType,
          anyOf(SubmissionType.photo, SubmissionType.text),
          reason: '${task.id} must not need a video or a link',
        );
      }
    });

    test('the submission types match the product table', () {
      final byId = {for (final t in tasks) t.id: t.submissionType};
      expect(byId['starter-03'], SubmissionType.text);
      expect(byId['starter-07'], SubmissionType.text);
      for (final id in const [
        'starter-01',
        'starter-02',
        'starter-04',
        'starter-05',
        'starter-06',
        'starter-08',
        'starter-09',
        'starter-10',
      ]) {
        expect(byId[id], SubmissionType.photo, reason: id);
      }
    });

    test('the timers match the product table', () {
      expect(
        {for (final t in tasks) t.id: t.durationSeconds},
        {
          'starter-01': 90,
          'starter-02': 120,
          'starter-03': 60,
          'starter-04': 120,
          'starter-05': 180,
          'starter-06': 180,
          'starter-07': 90,
          'starter-08': 60,
          'starter-09': 30,
          'starter-10': 90,
        },
      );
    });

    test('every task carries a rubric, a twist and a real description', () {
      for (final task in tasks) {
        expect(task.rubric, isNotNull, reason: task.id);
        expect(task.rubric!.trim(), isNotEmpty, reason: task.id);
        expect(task.twist, isNotNull, reason: task.id);
        expect(task.twist!.trim(), isNotEmpty, reason: task.id);
        expect(task.title.trim(), isNotEmpty, reason: task.id);
        expect(task.description.length, greaterThan(60), reason: task.id);
      }
    });

    test('every task is in the Starter Pack category and starts unsubmitted',
        () {
      for (final task in tasks) {
        expect(task.category, StarterPackData.category);
        expect(task.submissions, isEmpty);
        expect(task.playerStatuses, isEmpty);
        expect(task.status, TaskStatus.waiting_for_submissions);
        // The gameplay engine is the ordinary submit-and-judge flow; the
        // medium is carried by submissionType.
        expect(task.taskType, TaskType.video);
      }
    });

    test('every task survives a serialization round trip', () {
      for (final task in tasks) {
        expect(Task.fromMap(task.toMap()), task, reason: task.id);
      }
    });

    test('the copy is the product copy', () {
      final first = tasks.first;
      expect(first.title, 'A vegetable that has just received terrible news');
      expect(first.description, startsWith('Find a vegetable.'));
      expect(first.description, contains('emotional truth'));
      expect(first.rubric, 'Emotional truth of the vegetable.');
      expect(first.twist, contains('no text on the vegetable'));
    });
  });

  group('StarterPackData.houseEntries', () {
    test('there is one per task, keyed by task id', () {
      expect(StarterPackData.houseEntries.length, tasks.length);
      for (final task in tasks) {
        expect(StarterPackData.houseEntries.containsKey(task.id), isTrue,
            reason: task.id);
      }
    });

    test('every entry is short, real text — one to three lines', () {
      for (final entry in StarterPackData.houseEntries.entries) {
        final text = entry.value;
        expect(text.trim(), isNotEmpty, reason: entry.key);
        expect(text.length, lessThan(280), reason: entry.key);
        expect('\n'.allMatches(text).length, lessThanOrEqualTo(2),
            reason: entry.key);
      }
    });

    test('the poster and game names are the product ones', () {
      expect(StarterPackData.housePosterName, "Greg's assistant");
      expect(StarterPackData.gameName, 'Your First Ten');
    });
  });
}
