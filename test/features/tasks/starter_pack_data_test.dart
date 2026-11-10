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

    test('the round 9 ten, in play order', () {
      expect(tasks.map((t) => t.id), [
        'starter-09-v3', // oven selfie: no props, 30 s (clearer copy)
        'starter-03', // rename an object: sit still and type
        'starter-04', // hide in plain sight: one photo
        'starter-02-v3', // GATHER shapes -> REVEAL the tower
        'starter-11', // the sofa's one-star review (from the daily pool)
        'starter-06', // famous painting from arm's reach
        'starter-07', // three-line fridge horror
        'starter-12', // win an argument with a door (from the daily pool)
        'starter-13', // sell us a glass of tap water (from the daily pool)
        'starter-08-v2', // most things on your head
      ]);
    });

    test('cut and rewritten tasks keep resolving for older games', () {
      final retired = StarterPackData.retiredTasks().map((t) => t.id).toSet();
      expect(retired, {
        'starter-09-v2', // old oven copy
        'starter-02-v2', // old tower (no gather)
        'starter-01-v2', // egg on a spoon (cut)
        'starter-05-v2', // worst sandwich (cut)
        'starter-10-v2', // autobiography trailer (cut)
      });
      // No id is both live and retired, and every id ever dealt resolves.
      expect(retired.intersection(tasks.map((t) => t.id).toSet()), isEmpty);
      final all = StarterPackData.allTasks();
      expect(all.map((t) => t.id).toSet().length, all.length);
      for (final t in all) {
        expect(StarterPackData.byId(t.id), t, reason: t.id);
      }
      expect(StarterPackData.byId('starter-99'), isNull);
      // A retired task's data is untouched (older games hold it inline).
      expect(StarterPackData.byId('starter-01-v2')!.title,
          'Egg on a spoon, to the far wall and back');
    });

    test('the cut tasks are not in the ten', () {
      final titles = tasks.map((t) => t.title.toLowerCase()).join(' | ');
      expect(titles, isNot(contains('egg')));
      expect(titles, isNot(contains('sandwich')));
      expect(titles, isNot(contains('autobiography')));
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

    test('video is still the main medium: five of the ten are clips', () {
      final videoIds = tasks
          .where((t) => t.submissionType == SubmissionType.video)
          .map((t) => t.id)
          .toSet();
      expect(
        videoIds,
        {'starter-09-v3', 'starter-02-v3', 'starter-12', 'starter-13',
         'starter-08-v2'},
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
      expect(byId['starter-11'], SubmissionType.text);
      expect(byId['starter-04'], SubmissionType.photo);
      expect(byId['starter-06'], SubmissionType.photo);
      for (final id in const [
        'starter-09-v3',
        'starter-02-v3',
        'starter-12',
        'starter-13',
        'starter-08-v2',
      ]) {
        expect(byId[id], SubmissionType.video, reason: id);
      }
    });

    test('the timers match the product table', () {
      expect(
        {for (final t in tasks) t.id: t.durationSeconds},
        {
          'starter-09-v3': 30,
          'starter-03': 60,
          'starter-04': 120,
          'starter-02-v3': 90,
          'starter-11': 90,
          'starter-06': 180,
          'starter-07': 90,
          'starter-12': 90,
          'starter-13': 90,
          'starter-08-v2': 60,
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

    test('task 1 says what it means: you, the oven, a selfie', () {
      final oven = tasks.first;
      expect(oven.title, 'Selfie: you just remembered the oven is on');
      expect(oven.description, contains('the oven is on'));
      expect(oven.description, isNot(contains('3 a.m.')));
      expect(oven.twist, contains('exactly one word'));
    });

    group('gather -> reveal', () {
      final gatherTasks = tasks.where((t) => t.hasGatherPhase).toList();

      test('task 4 is the one starter misdirect: gather shapes, then a tower',
          () {
        expect(gatherTasks.map((t) => t.id), ['starter-02-v3']);
        final tower = tasks[3];
        expect(tower.id, 'starter-02-v3');
        expect(tower.gatherSeconds, 60);
        expect(tower.gatherPrompt, startsWith('You have 60 s.'));
        expect(tower.gatherPrompt, contains('different shapes'));
        expect(tower.title, contains('tallest tower'));
        expect(tower.description, contains('only the things you just gathered'));
      });

      test('the teaser never spoils the real task', () {
        for (final t in gatherTasks) {
          expect(t.teaserTitle, t.gatherTitle, reason: t.id);
          expect(t.teaserDescription, t.gatherPrompt, reason: t.id);
          expect(t.teaserSeconds, t.gatherSeconds, reason: t.id);
          final teaser = '${t.teaserTitle} ${t.teaserDescription}'.toLowerCase();
          expect(teaser, isNot(contains('tower')), reason: t.id);
          expect(teaser, isNot(contains(t.title.toLowerCase())), reason: t.id);
        }
      });

      test('an ordinary task teases itself', () {
        final rename = tasks[1];
        expect(rename.hasGatherPhase, isFalse);
        expect(rename.teaserTitle, rename.title);
        expect(rename.teaserDescription, rename.description);
        expect(rename.teaserSeconds, rename.durationSeconds);
      });
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
      // The v3 oven reuses the v2 clip, so its entry 0 keeps the clip's line.
      expect(StarterPackData.houseEntries['starter-09-v3']!.first.text,
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

    test('the seeded house clips point at house/<clipTaskId>.mp4', () {
      for (final MapEntry(key: taskId, value: clip)
          in StarterPackData.houseClipTaskIds.entries) {
        final task = StarterPackData.byId(taskId)!;
        expect(task.submissionType, SubmissionType.video, reason: taskId);
        expect(StarterPackData.houseVideoPath(clip), 'house/$clip.mp4');
        expect(
          StarterPackData.houseVideoUrl(clip),
          contains('house%2F$clip.mp4?alt=media'),
        );
        // Public read, no download token in the URL.
        expect(StarterPackData.houseVideoUrl(clip), isNot(contains('token')));
        // Only clips that were actually uploaded (the round 8 six).
        expect(const {
          'starter-01-v2',
          'starter-02-v2',
          'starter-05-v2',
          'starter-08-v2',
          'starter-09-v2',
          'starter-10-v2',
        }, contains(clip));
      }
    });

    test('the poster and game names are the product ones', () {
      expect(StarterPackData.housePosterName, "Greg's assistant");
      expect(StarterPackData.gameName, 'Your First Ten');
    });
  });
}
