import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/models/task.dart';
import 'package:taskcaster_app/features/arena/domain/models/feed_post.dart';
import 'package:taskcaster_app/features/tasks/data/datasources/starter_pack_data.dart';

void main() {
  final tasks = StarterPackData.tasks();

  group('StarterPackData.tasks', () {
    test('is exactly the ten starter tasks', () {
      expect(tasks.length, 10);
    });

    test('ids keep their numbers; only the play order changed (WP-05)', () {
      expect(tasks.map((t) => t.id), [
        'starter-09-v2', // oven face: a selfie, no props, 30 s
        'starter-03', // rename an object: sit still and type
        'starter-04', // hide in plain sight: one photo
        'starter-10-v2',
        'starter-06',
        'starter-01-v2', // egg on a spoon: needs props and a walk, so 6+
        'starter-07',
        'starter-02-v2',
        'starter-05-v2',
        'starter-08-v2',
      ]);
    });

    test('the same ten ids as always, so posts and montages still attach', () {
      expect(
        tasks.map((t) => t.id).toSet(),
        {
          for (var i = 1; i <= 10; i++)
            'starter-${i.toString().padLeft(2, '0')}'
                '${const {1, 2, 5, 8, 9, 10}.contains(i) ? '-v2' : ''}',
        },
      );
    });

    test('task 1 needs no props: a 30 s selfie clip', () {
      final first = tasks.first;
      expect(first.submissionType, SubmissionType.video);
      expect(first.durationSeconds, 30);
      expect(first.description, startsWith('Selfie video.'));
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
          .toSet();
      expect(
        videoIds,
        {'starter-01-v2', 'starter-02-v2', 'starter-05-v2', 'starter-08-v2',
         'starter-09-v2', 'starter-10-v2'},
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
        'starter-01-v2',
        'starter-02-v2',
        'starter-05-v2',
        'starter-08-v2',
        'starter-09-v2',
        'starter-10-v2',
      ]) {
        expect(byId[id], SubmissionType.video, reason: id);
      }
    });

    test('the timers match the product table', () {
      expect(
        {for (final t in tasks) t.id: t.durationSeconds},
        {
          'starter-01-v2': 30,
          'starter-02-v2': 60,
          'starter-03': 60,
          'starter-04': 120,
          'starter-05-v2': 90,
          'starter-06': 180,
          'starter-07': 90,
          'starter-08-v2': 60,
          'starter-09-v2': 30,
          'starter-10-v2': 30,
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

    test('the autobiography trailer needs no hand-made props', () {
      final trailer = tasks.firstWhere((t) => t.id == 'starter-10-v2');
      expect(trailer.durationSeconds, 30);
      expect(trailer.description, isNot(contains('cover')));
      expect(trailer.twist, isNot(contains('cover')));
      expect(trailer.twist, contains('out loud'));
    });

    test('the copy is the product copy', () {
      final first = tasks.firstWhere((t) => t.id == 'starter-01-v2');
      expect(first.title, 'Egg on a spoon, to the far wall and back');
      expect(first.description, startsWith('Put an egg'));
      expect(first.description, contains('Film the whole trip'));
      expect(first.rubric, 'Distance covered before disaster, then narration.');
      expect(first.twist, contains('nature documentary'));
    });
  });

  group('StarterPackData.houseEntries', () {
    test('there are four per task, keyed by task id', () {
      expect(StarterPackData.houseEntries.length, tasks.length);
      for (final task in tasks) {
        expect(StarterPackData.houseEntries[task.id], hasLength(4),
            reason: task.id);
      }
    });

    test('entry 0 is the house; the personas follow in a fixed order', () {
      for (final entries in StarterPackData.houseEntries.values) {
        expect(entries.map((e) => e.posterName), [
          StarterPackData.housePosterName,
          StarterPackData.auntPam,
          StarterPackData.theIntern,
          StarterPackData.daveFromAccounts,
        ]);
      }
    });

    test('entry 0 keeps the copy it has always had (its prod doc keeps it)',
        () {
      expect(StarterPackData.houseEntries['starter-09-v2']!.first.text,
          "Layer 4 was 'the cat is also in the oven'.");
      expect(StarterPackData.houseEntries['starter-07']!.first.text,
          startsWith('There are four yoghurts.'));
    });

    test('every entry is short, real text — one to three lines', () {
      for (final MapEntry(key: taskId, value: entries)
          in StarterPackData.houseEntries.entries) {
        for (final entry in entries) {
          final text = entry.text;
          expect(text.trim(), isNotEmpty, reason: taskId);
          expect(text.length, lessThan(280), reason: taskId);
          expect('\n'.allMatches(text).length, lessThanOrEqualTo(2),
              reason: taskId);
          // House copy follows the product voice: no exclamation marks.
          expect(text, isNot(contains('!')), reason: '$taskId: $text');
        }
      }
    });

    test('no two entries share a text, and every take is different', () {
      final texts = [
        for (final entries in StarterPackData.houseEntries.values)
          for (final e in entries) e.text,
      ];
      expect(texts.toSet().length, texts.length);
    });

    test('stamps are real, distinct within a task, and never ART on a video',
        () {
      for (final task in tasks) {
        final entries = StarterPackData.houseEntries[task.id]!;
        for (final e in entries) {
          expect(Stamps.values, contains(e.stamp), reason: task.id);
        }
        expect(entries.map((e) => e.stamp).toSet().length, entries.length,
            reason: task.id);
        // Only entry 0 carries the clip on a video task.
        if (task.submissionType == SubmissionType.video) {
          expect(entries.first.stamp, isNot(Stamps.art), reason: task.id);
        }
      }
    });

    test('starting grades are believable: 4-30 grades, mean 2.1-4.6', () {
      for (final MapEntry(key: taskId, value: entries)
          in StarterPackData.houseEntries.entries) {
        for (final e in entries) {
          expect(e.gradeCount, inInclusiveRange(4, 30), reason: taskId);
          expect(e.meanGrade, inInclusiveRange(2.1, 4.6),
              reason: '$taskId ${e.posterName}');
        }
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
