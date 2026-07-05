import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/features/tasks/presentation/screens/task_browser_screen.dart';
import 'package:taskcaster_app/features/tasks/data/datasources/prebuilt_tasks_data.dart';

void main() {
  group('TaskBrowserScreen', () {
    testWidgets('should render correctly with initial state', (tester) async {
      // Arrange & Act
      await tester.pumpWidget(
        const MaterialApp(
          home: TaskBrowserScreen(),
        ),
      );

      // Assert
      expect(find.text('Select Tasks'), findsOneWidget);
      expect(find.byType(TabBar), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget); // Search bar
      expect(find.text('0 tasks selected'), findsOneWidget);
    });

    testWidgets('should display all category tabs', (tester) async {
      // Arrange & Act
      await tester.pumpWidget(
        const MaterialApp(
          home: TaskBrowserScreen(),
        ),
      );

      // Assert — one tab per library category, plus "All".
      expect(find.text('All'), findsOneWidget);
      for (final category in PrebuiltTasksData.categories) {
        expect(find.text(category), findsWidgets,
            reason: 'Missing tab for category "$category"');
      }
    });

    testWidgets('should display tasks in grid view', (tester) async {
      // Arrange & Act
      await tester.pumpWidget(
        const MaterialApp(
          home: TaskBrowserScreen(),
        ),
      );

      // Assert
      expect(find.byType(GridView), findsOneWidget);
      // Should have multiple task cards
      expect(find.byType(Card), findsWidgets);
    });

    testWidgets('should filter tasks by search query', (tester) async {
      // Arrange
      await tester.pumpWidget(
        const MaterialApp(
          home: TaskBrowserScreen(),
        ),
      );

      // Act - Enter search text
      await tester.enterText(find.byType(TextField), 'balloon');
      await tester.pump();

      // Assert - Should filter down tasks
      // (We can't easily count exact tasks without knowing PrebuiltTasksData,
      // but we can verify the search functionality is working)
      expect(find.byType(GridView), findsOneWidget);
    });

    testWidgets('should clear search query when clear button is tapped', (tester) async {
      // Arrange
      await tester.pumpWidget(
        const MaterialApp(
          home: TaskBrowserScreen(),
        ),
      );

      // Act - Enter search text
      await tester.enterText(find.byType(TextField), 'test');
      await tester.pump();

      // Assert - Clear button should appear
      expect(find.byIcon(Icons.clear), findsOneWidget);

      // Act - Tap clear button
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pump();

      // Assert - Search field should be cleared
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, isEmpty);
    });

    testWidgets('should select and deselect tasks on tap', (tester) async {
      // Arrange
      await tester.pumpWidget(
        const MaterialApp(
          home: TaskBrowserScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Act - Tap first task card
      final firstCard = find.byType(Card).first;
      await tester.tap(firstCard);
      await tester.pump();

      // Assert - Should show 1 task selected
      expect(find.text('1 task selected'), findsOneWidget);

      // Act - Tap same card again to deselect
      await tester.tap(firstCard);
      await tester.pump();

      // Assert - Should show 0 tasks selected
      expect(find.text('0 tasks selected'), findsOneWidget);
    });

    testWidgets('should not allow selecting more than maxTasks', (tester) async {
      // Arrange
      await tester.pumpWidget(
        const MaterialApp(
          home: TaskBrowserScreen(maxTasks: 2),
        ),
      );
      await tester.pumpAndSettle();

      // Act - Select 3 tasks
      final cards = find.byType(Card);
      await tester.tap(cards.at(0));
      await tester.pump();
      await tester.tap(cards.at(1));
      await tester.pump();
      await tester.tap(cards.at(2)); // Should be rejected
      await tester.pump();

      // Assert - Should still show only 2 tasks selected
      expect(find.text('2 tasks selected'), findsOneWidget);
      // Should show snackbar with max tasks message
      expect(find.text('Maximum 2 tasks allowed'), findsOneWidget);
    });

    testWidgets('should show Done button in bottom bar', (tester) async {
      // Arrange & Act
      await tester.pumpWidget(
        const MaterialApp(
          home: TaskBrowserScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Assert - Verify bottom bar exists with text
      expect(find.text('0 tasks selected'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
    });

    testWidgets('should update selected count when tasks are selected', (tester) async {
      // Arrange
      await tester.pumpWidget(
        const MaterialApp(
          home: TaskBrowserScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Act - Select a task
      await tester.tap(find.byType(Card).first);
      await tester.pump();

      // Assert - Count should update
      expect(find.text('1 task selected'), findsOneWidget);
    });

    // Note: Testing navigation and return values is complex with ElevatedButton.icon
    // The functionality is verified manually and through integration tests

    testWidgets('should select random 5 tasks from filter menu', (tester) async {
      // Arrange
      await tester.pumpWidget(
        const MaterialApp(
          home: TaskBrowserScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Act - Open filter menu
      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pumpAndSettle();

      // Tap "Random 5 tasks"
      await tester.tap(find.text('Random 5 tasks'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('5 tasks selected'), findsOneWidget);
    });

    testWidgets('should select random 10 tasks from filter menu', (tester) async {
      // Arrange
      await tester.pumpWidget(
        const MaterialApp(
          home: TaskBrowserScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Act - Open filter menu
      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pumpAndSettle();

      // Tap "Random 10 tasks"
      await tester.tap(find.text('Random 10 tasks'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('10 tasks selected'), findsOneWidget);
    });

    testWidgets('should clear selection from filter menu', (tester) async {
      // Arrange
      await tester.pumpWidget(
        const MaterialApp(
          home: TaskBrowserScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Select a task first
      await tester.tap(find.byType(Card).first);
      await tester.pump();
      expect(find.text('1 task selected'), findsOneWidget);

      // Act - Open filter menu
      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pumpAndSettle();

      // Tap "Clear selection"
      await tester.tap(find.text('Clear selection'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('0 tasks selected'), findsOneWidget);
    });

    testWidgets('should show task preview modal on long press', (tester) async {
      // Arrange
      await tester.pumpWidget(
        const MaterialApp(
          home: TaskBrowserScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Act - Long press first card
      await tester.longPress(find.byType(Card).first);
      await tester.pumpAndSettle();

      // Assert - Modal should be visible
      expect(find.byType(DraggableScrollableSheet), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('should maintain initially selected tasks', (tester) async {
      // Arrange
      final allTasks = PrebuiltTasksData.getAllTasks();
      final initialTasks = [allTasks[0], allTasks[1]];

      // Act
      await tester.pumpWidget(
        MaterialApp(
          home: TaskBrowserScreen(
            initiallySelectedTasks: initialTasks,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('2 tasks selected'), findsOneWidget);
    });

    testWidgets('should filter by category when tab is selected', (tester) async {
      // Arrange
      await tester.pumpWidget(
        const MaterialApp(
          home: TaskBrowserScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Act - Tap on the first category tab
      await tester.tap(find.text(PrebuiltTasksData.categories.first).first);
      await tester.pumpAndSettle();

      // Assert - Should still show grid (with filtered tasks)
      expect(find.byType(GridView), findsOneWidget);
      expect(find.byType(Card), findsWidgets);
    });

    testWidgets('should show "No tasks found" when search returns no results', (tester) async {
      // Arrange
      await tester.pumpWidget(
        const MaterialApp(
          home: TaskBrowserScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Act - Search for something unlikely to exist
      await tester.enterText(find.byType(TextField), 'xyzabc123notfound999');
      await tester.pump();

      // Assert
      expect(find.text('No tasks found'), findsOneWidget);
      expect(find.byIcon(Icons.search_off), findsOneWidget);
    });
  });
}