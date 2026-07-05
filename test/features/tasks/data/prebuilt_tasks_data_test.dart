import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/models/task.dart';
import 'package:taskcaster_app/features/tasks/data/datasources/prebuilt_tasks_data.dart';

void main() {
  group('PrebuiltTasksData library integrity', () {
    late List<Task> allTasks;

    setUp(() {
      allTasks = PrebuiltTasksData.getAllTasks();
    });

    test('contains at least 120 tasks', () {
      expect(allTasks.length, greaterThanOrEqualTo(120),
          reason: 'The library must offer at least 120 tasks '
              '(currently ${allTasks.length}).');
    });

    test('contains at least 120 video tasks', () {
      final videoTasks =
          allTasks.where((t) => t.taskType == TaskType.video).toList();
      expect(videoTasks.length, greaterThanOrEqualTo(120));
    });

    test('has no duplicate titles', () {
      final seen = <String>{};
      final duplicates = <String>[];
      for (final task in allTasks) {
        final normalized = task.title.trim().toLowerCase();
        if (!seen.add(normalized)) duplicates.add(task.title);
      }
      expect(duplicates, isEmpty,
          reason: 'Duplicate task titles found: $duplicates');
    });

    test('has no duplicate ids and ids are stable across calls', () {
      final ids = allTasks.map((t) => t.id).toList();
      expect(ids.toSet().length, ids.length,
          reason: 'Task ids must be unique');

      // Stable ids: a second call to getAllTasks() yields the same ids in the
      // same order, so selections persist across screens and rebuilds.
      final secondCall = PrebuiltTasksData.getAllTasks().map((t) => t.id);
      expect(secondCall, orderedEquals(ids));
    });

    test('every task has a non-empty title and description', () {
      for (final task in allTasks) {
        expect(task.title.trim(), isNotEmpty,
            reason: 'Task ${task.id} has an empty title');
        expect(task.description.trim(), isNotEmpty,
            reason: 'Task "${task.title}" has an empty description');
      }
    });

    test('every task carries a valid category', () {
      for (final task in allTasks) {
        expect(task.category, isNotNull,
            reason: 'Task "${task.title}" has no category');
        expect(PrebuiltTasksData.categories, contains(task.category),
            reason:
                'Task "${task.title}" has unknown category "${task.category}"');
      }
    });

    test('every category has at least 10 tasks', () {
      for (final category in PrebuiltTasksData.categories) {
        final count = allTasks.where((t) => t.category == category).length;
        expect(count, greaterThanOrEqualTo(10),
            reason: 'Category "$category" only has $count tasks');
      }
    });

    test('getTasksByCategory returns only tasks of that category', () {
      for (final category in PrebuiltTasksData.categories) {
        final tasks = PrebuiltTasksData.getTasksByCategory(category);
        expect(tasks, isNotEmpty);
        expect(tasks.every((t) => t.category == category), isTrue);
      }
    });

    test('every task starts with no submissions and default status', () {
      for (final task in allTasks) {
        expect(task.submissions, isEmpty);
        expect(task.status, TaskStatus.waiting_for_submissions);
      }
    });

    test('descriptions are meaty enough to be actual briefs', () {
      for (final task in allTasks) {
        expect(task.description.trim().length, greaterThanOrEqualTo(40),
            reason: 'Task "${task.title}" has a suspiciously thin brief');
      }
    });
  });
}
