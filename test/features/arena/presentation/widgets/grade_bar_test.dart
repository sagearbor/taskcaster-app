import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/features/arena/presentation/widgets/grade_bar.dart';

void main() {
  testWidgets('renders exactly 5 chips labelled 1..5', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: GradeBar(onGrade: (_) {}))),
    );

    for (var i = 1; i <= 5; i++) {
      expect(find.text('$i'), findsOneWidget);
    }
    expect(find.text('tragic'), findsOneWidget);
    expect(find.text('legendary'), findsOneWidget);
  });

  testWidgets('tapping a chip dispatches its score exactly once',
      (tester) async {
    final grades = <int>[];
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: GradeBar(onGrade: grades.add))),
    );

    await tester.tap(find.text('4'));
    await tester.pump();

    expect(grades, [4]);
  });

  testWidgets('each of the 5 scores can be tapped', (tester) async {
    final grades = <int>[];
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: GradeBar(onGrade: grades.add))),
    );

    for (var i = 1; i <= 5; i++) {
      await tester.tap(find.text('$i'));
      await tester.pump();
    }

    expect(grades, [1, 2, 3, 4, 5]);
  });
}
