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

  double scaleOf(WidgetTester tester, String label) => tester
      .widget<ScaleTransition>(find.ancestor(
        of: find.text(label),
        matching: find.byType(ScaleTransition),
      ))
      .scale
      .value;

  testWidgets('WP-3: the chosen chip scale-bounces 1.0 -> 1.25 -> 1.0',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: GradeBar(onGrade: (_) {}))),
    );

    expect(scaleOf(tester, '4'), 1.0);
    await tester.tap(find.text('4'));
    await tester.pump(); // rebuild with the chip selected
    await tester.pump(const Duration(milliseconds: 99)); // ~the peak
    expect(scaleOf(tester, '4'), closeTo(1.25, 0.02));
    expect(scaleOf(tester, '3'), 1.0, reason: 'only the chosen chip bounces');

    await tester.pump(GradeBar.bounceDuration);
    expect(scaleOf(tester, '4'), 1.0);
  });

  testWidgets('a pre-selected chip does not bounce on first build',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GradeBar(selected: 2, onGrade: (_) {})),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(scaleOf(tester, '2'), 1.0);
  });
}
