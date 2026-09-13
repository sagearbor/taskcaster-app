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

    test('every task can be done with a phone: film, snap or write', () {
      for (final task in tasks) {
        expect(
          task.submissionType,
          anyOf(
            SubmissionType.video,
            SubmissionType.photo,
            SubmissionType.text,
          ),
          reason: '${task.id} must not need a pasted link',
        );
      }
    });

    test('video is the default medium: six of the ten are clips', () {
      final videoIds = tasks
          .where((t) => t.submissionType == SubmissionType.video)
          .map((t) => t.id)
          .toList();
      expect(
        videoIds,
        ['starter-01', 'starter-02', 'starter-05', 'starter-08',
         'starter-09', 'starter-10'],
      );
    });

    test('every video task fits the clip cap', () {
      for (final task in tasks) {
        if (task.submissionType != SubmissionType.video) continue;
        // The clip is capped at min(timer, 30 s); a task whose timer is under
        // 30 s shortens the clip, never the other way round.
        expect(task.durationSeconds, isNotNull, reason: task.id);
        expect(task.durationSeconds! > 0, isTrue, reason: task.id);
      }
    });

    test('the submission types match the product table', () {
      final byId = {for (final t in tasks) t.id: t.submissionType};
      // Wordplay stays text; 04 and 06 stay photo on purpose (the still IS
      // the joke); everything else is a clip.
      expect(byId['starter-03'], SubmissionType.text);
      expect(byId['starter-07'], SubmissionType.text);
      expect(byId['starter-04'], SubmissionType.photo);
      expect(byId['starter-06'], SubmissionType.photo);
      for (final id in const [
        'starter-01',
        'starter-02',
        'starter-05',
        'starter-08',
        'starter-09',
        'starter-10',
      ]) {
        expect(byId[id], SubmissionType.video, reason: id);
      }
    });

    test('the timers match the product table', () {
      expect(
        {for (final t in tasks) t.id: t.durationSeconds},
        {
          'starter-01': 30,
          'starter-02': 60,
          'starter-03': 60,
          'starter-04': 120,
          'starter-05': 90,
          'starter-06': 180,
          'starter-07': 90,
          'starter-08': 60,
          'starter-09': 30,
          'starter-10': 30,
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
      expect(first.title, 'Egg on a spoon, to the far wall and back');
      expect(first.description, startsWith('Put an egg'));
      expect(first.description, contains('Film the whole trip'));
      expect(first.rubric, 'Distance covered before disaster, then narration.');
      expect(first.twist, contains('nature documentary'));
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

    test('the seeded house clips point at house/<taskId>.mp4', () {
      for (final task in tasks) {
        if (task.submissionType != SubmissionType.video) continue;
        expect(StarterPackData.houseVideoPath(task.id), 'house/${task.id}.mp4');
        expect(
          StarterPackData.houseVideoUrl(task.id),
          contains('house%2F${task.id}.mp4?alt=media'),
        );
        // Public read, no download token in the URL.
        expect(StarterPackData.houseVideoUrl(task.id), isNot(contains('token')));
      }
    });

    test('the poster and game names are the product ones', () {
      expect(StarterPackData.housePosterName, "Greg's assistant");
      expect(StarterPackData.gameName, 'Your First Ten');
    });
  });
}
