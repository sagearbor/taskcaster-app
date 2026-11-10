import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/models/task.dart';
import 'package:taskcaster_app/features/tasks/data/datasources/daily_task_data.dart';

void main() {
  final tasks = DailyTaskData.tasks();

  group('the pool', () {
    test('has exactly 30 tasks with unique daily-NN ids', () {
      expect(tasks.length, 30);
      final ids = tasks.map((t) => t.id).toList();
      expect(ids.toSet().length, 30);
      for (var i = 0; i < 30; i++) {
        expect(ids[i], 'daily-${(i + 1).toString().padLeft(2, '0')}');
        expect(DailyTaskData.isDailyTaskId(ids[i]), isTrue);
      }
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
}
