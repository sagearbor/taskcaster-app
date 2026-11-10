import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/models/task.dart';
import 'package:taskcaster_app/features/arena/domain/models/feed_post.dart';
import 'package:taskcaster_app/features/tasks/data/datasources/daily_task_data.dart';
import 'package:taskcaster_app/features/tasks/data/datasources/starter_pack_data.dart';

void main() {
  final tasks = DailyTaskData.tasks();

  group('the pool', () {
    test('has exactly 30 tasks with unique daily-NN ids', () {
      expect(tasks.length, 30);
      final ids = tasks.map((t) => t.id).toList();
      expect(ids.toSet().length, 30);
      for (final id in ids) {
        expect(id, matches(RegExp(r'^daily-\d{2}$')));
        expect(DailyTaskData.isDailyTaskId(id), isTrue);
      }
    });

    test('a replaced task keeps its pool slot under a new id (round 9)', () {
      // Slot (index) -> id. The day -> slot rotation never moves, so only
      // the replaced slots changed task; every other day is untouched.
      final ids = tasks.map((t) => t.id).toList();
      const replaced = {
        1: 'daily-31', // was daily-02, the sofa review (now starter-11)
        2: 'daily-32', // was daily-03, left hand meets right hand
        4: 'daily-33', // was daily-05, job for a medieval peasant
        6: 'daily-34', // was daily-07, the door (now starter-12)
        11: 'daily-35', // was daily-12, audience of objects
        17: 'daily-36', // was daily-18, tap water (now starter-13)
        19: 'daily-37', // was daily-20, pet from a kitchen drawer
        22: 'daily-38', // was daily-23, prove you are on a beach
        28: 'daily-39', // was daily-29, an object's worst day
      };
      for (var i = 0; i < 30; i++) {
        expect(ids[i],
            replaced[i] ?? 'daily-${(i + 1).toString().padLeft(2, '0')}',
            reason: 'slot $i');
      }
    });

    test('the weak and the moved tasks are gone from the pool', () {
      final titles = tasks.map((t) => t.title).toSet();
      for (final cut in const [
        'Introduce your left hand to your right hand',
        'Prove you are on a beach',
        'Adopt a pet from one kitchen drawer',
        'Explain your job to a medieval peasant',
        'An audience of objects hears something shocking',
        'An object having the worst day of its life',
      ]) {
        expect(titles, isNot(contains(cut)));
      }
      // Nothing is both a starter task and a daily task.
      final starterTitles =
          StarterPackData.tasks().map((t) => t.title).toSet();
      expect(titles.intersection(starterTitles), isEmpty);
    });

    group('gather -> reveal', () {
      final gather = tasks.where((t) => t.hasGatherPhase).toList();

      test('at least six of the thirty are misdirects', () {
        expect(gather.length, greaterThanOrEqualTo(6));
      });

      test('every gather stage is short, clear and ends in Go.', () {
        for (final t in gather) {
          expect(t.gatherSeconds, inInclusiveRange(30, 60), reason: t.id);
          expect(t.gatherTitle?.trim(), isNotEmpty, reason: t.id);
          expect(t.gatherPrompt, startsWith('You have ${t.gatherSeconds} s.'),
              reason: t.id);
          expect(t.gatherPrompt, endsWith('Go.'), reason: t.id);
          expect('${t.gatherTitle}${t.gatherPrompt}'.contains('!'), isFalse,
              reason: t.id);
        }
      });

      test('the real task uses what was gathered, and the teaser hides it',
          () {
        for (final t in gather) {
          expect(
            '${t.title} ${t.description}'.toLowerCase(),
            anyOf(contains('gathered'), contains('fetched')),
            reason: t.id,
          );
          expect(t.teaserTitle, isNot(t.title), reason: t.id);
          expect(t.teaserDescription, isNot(contains(t.title)), reason: t.id);
        }
      });
    });

    test('every field a crowd needs is set', () {
      for (final t in tasks) {
        expect(t.title.trim(), isNotEmpty, reason: t.id);
        expect(t.description.trim(), isNotEmpty, reason: t.id);
        expect(t.twist?.trim(), isNotEmpty, reason: t.id);
        expect(t.rubric?.trim(), isNotEmpty, reason: t.id);
        expect(t.category, DailyTaskData.category, reason: t.id);
        expect(t.taskType, TaskType.video, reason: '${t.id}: engine');
        expect(t.submissions, isEmpty, reason: t.id);
      }
    });

    test('no exclamation marks anywhere (house style)', () {
      for (final t in tasks) {
        for (final s in [t.title, t.description, t.twist!, t.rubric!]) {
          expect(s.contains('!'), isFalse, reason: '${t.id}: "$s"');
        }
      }
    });

    test('rubrics are one line', () {
      for (final t in tasks) {
        expect(t.rubric!.contains('\n'), isFalse, reason: t.id);
        expect(t.rubric!.length, lessThan(70), reason: t.id);
      }
    });

    test('doable in two minutes: durations are 60..120 s', () {
      for (final t in tasks) {
        expect(t.durationSeconds, inInclusiveRange(60, 120), reason: t.id);
        // ...and within the wider bound the brief allows.
        expect(t.durationSeconds, inInclusiveRange(60, 180), reason: t.id);
      }
    });

    test('mostly photo and text, with eight video tasks', () {
      int count(SubmissionType type) =>
          tasks.where((t) => t.submissionType == type).length;
      expect(count(SubmissionType.video), 8);
      expect(count(SubmissionType.photo), greaterThanOrEqualTo(10));
      expect(count(SubmissionType.text), greaterThanOrEqualTo(10));
      expect(count(SubmissionType.any), 0);
    });

    test('never reuses a starter task id', () {
      for (final t in tasks) {
        expect(t.id.startsWith('starter-'), isFalse);
      }
    });
  });

  group('picking the day', () {
    test('everyone gets the same task on the same UTC day', () {
      final a = DailyTaskData.taskFor(DateTime.utc(2026, 11, 9, 0, 0, 1));
      final b = DailyTaskData.taskFor(DateTime.utc(2026, 11, 9, 23, 59, 59));
      expect(a.id, b.id);
    });

    test('is pool[(daysSinceEpochUtc + 7) % 30]', () {
      final day = DateTime.utc(2026, 11, 9);
      final days = DailyTaskData.daysSinceEpochUtc(day);
      expect(days, 20766);
      expect(DailyTaskData.taskFor(day).id, tasks[(days + 7) % 30].id);
    });

    test('the next UTC day brings a different task', () {
      final today = DailyTaskData.taskFor(DateTime.utc(2026, 11, 9, 23, 59));
      final tomorrow = DailyTaskData.taskFor(DateTime.utc(2026, 11, 10, 0, 1));
      expect(tomorrow.id, isNot(today.id));
    });

    test('30 consecutive days visit every task once', () {
      final start = DateTime.utc(2026, 1, 1);
      final ids = {
        for (var i = 0; i < 30; i++)
          DailyTaskData.taskFor(start.add(Duration(days: i))).id,
      };
      expect(ids.length, 30);
    });

    test('a local time is read as its UTC day', () {
      // 2026-11-09 23:30 at UTC-5 is 2026-11-10 04:30 UTC.
      final local = DateTime.parse('2026-11-09T23:30:00-05:00');
      expect(DailyTaskData.dayKey(local), '20261110');
      expect(DailyTaskData.taskFor(local).id,
          DailyTaskData.taskFor(DateTime.utc(2026, 11, 10)).id);
    });

    test('taskForDayKey matches taskFor', () {
      expect(DailyTaskData.taskForDayKey('20261109').id,
          DailyTaskData.taskFor(DateTime.utc(2026, 11, 9, 15)).id);
    });

    test('dayStart rejects anything but yyyyMMdd', () {
      expect(() => DailyTaskData.dayStart('2026-11-09'), throwsFormatException);
      expect(() => DailyTaskData.dayStart(''), throwsFormatException);
    });
  });

  group('ids, names and the countdown', () {
    test('dayKey is yyyyMMdd in UTC', () {
      expect(DailyTaskData.dayKey(DateTime.utc(2026, 1, 5, 23)), '20260105');
    });

    test('game id is daily_<uid>_<yyyyMMdd>', () {
      expect(DailyTaskData.gameIdFor('abc', '20261109'), 'daily_abc_20261109');
    });

    test('game name reads like a date, not a code', () {
      expect(DailyTaskData.gameNameFor('20261109'), 'Daily task, 9 Nov');
    });

    test('untilNextTask counts to the next UTC midnight', () {
      expect(DailyTaskData.untilNextTask(DateTime.utc(2026, 11, 9, 18, 48)),
          const Duration(hours: 5, minutes: 12));
      expect(DailyTaskData.untilNextTask(DateTime.utc(2026, 12, 31, 23, 59)),
          const Duration(minutes: 1));
    });

    test('formatUntil is short', () {
      expect(DailyTaskData.formatUntil(const Duration(hours: 5, minutes: 12)),
          '5 h 12 m');
      expect(DailyTaskData.formatUntil(const Duration(minutes: 12)), '12 m');
      expect(DailyTaskData.formatUntil(const Duration(seconds: 20)),
          'under a minute');
    });
  });

  group('DailyTaskData.houseEntries', () {
    const personas = [
      StarterPackData.auntPam,
      StarterPackData.theIntern,
      StarterPackData.daveFromAccounts,
    ];

    test('two per task: the house, then the rotating persona', () {
      expect(DailyTaskData.houseEntries.length, tasks.length);
      for (final (i, t) in tasks.indexed) {
        final entries = DailyTaskData.houseEntries[t.id];
        expect(entries, hasLength(2), reason: t.id);
        expect(entries!.map((e) => e.posterName),
            [StarterPackData.housePosterName, personas[i % 3]],
            reason: t.id);
      }
    });

    test('short real text, product voice, nothing repeated', () {
      final texts = <String>[];
      for (final MapEntry(key: id, value: entries)
          in DailyTaskData.houseEntries.entries) {
        for (final e in entries) {
          expect(e.text.trim(), isNotEmpty, reason: id);
          expect(e.text.length, lessThan(280), reason: id);
          expect('\n'.allMatches(e.text).length, lessThanOrEqualTo(2),
              reason: id);
          expect(e.text, isNot(contains('!')), reason: '$id: ${e.text}');
          texts.add(e.text);
        }
      }
      final starterTexts = {
        for (final list in StarterPackData.houseEntries.values)
          for (final e in list) e.text,
      };
      expect(texts.toSet().length, texts.length);
      expect(texts.where(starterTexts.contains), isEmpty);
    });

    test('real, distinct stamps and believable starting grades', () {
      for (final MapEntry(key: id, value: entries)
          in DailyTaskData.houseEntries.entries) {
        for (final e in entries) {
          expect(Stamps.values, contains(e.stamp), reason: id);
          expect(e.gradeCount, inInclusiveRange(4, 30), reason: id);
          expect(e.meanGrade, inInclusiveRange(2.1, 4.6), reason: id);
        }
        expect(entries.map((e) => e.stamp).toSet().length, entries.length,
            reason: id);
      }
    });
  });
}
