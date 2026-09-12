import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/features/games/presentation/widgets/task_countdown.dart';

void main() {
  testWidgets('shows the remaining time computed from startedAt',
      (tester) async {
    final startedAt = DateTime.now().subtract(const Duration(seconds: 20));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TaskCountdown(startedAt: startedAt, durationSeconds: 90),
      ),
    ));

    // ~70s remaining; allow either 1:09 or 1:10 depending on test timing.
    expect(
      find.textContaining(RegExp(r'1:(09|10)')),
      findsOneWidget,
    );
  });

  testWidgets('shows the full duration the instant it starts',
      (tester) async {
    final startedAt = DateTime.now();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TaskCountdown(startedAt: startedAt, durationSeconds: 10),
      ),
    ));

    expect(find.text('0:10'), findsOneWidget);
  });

  testWidgets('shows LATE once past the grace period', (tester) async {
    final startedAt = DateTime.now().subtract(const Duration(seconds: 200));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TaskCountdown(startedAt: startedAt, durationSeconds: 90),
      ),
    ));

    expect(find.text('LATE'), findsOneWidget);
  });

  testWidgets('cancels its timer on dispose (no pending-timer test failure)',
      (tester) async {
    final startedAt = DateTime.now();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TaskCountdown(startedAt: startedAt, durationSeconds: 30),
      ),
    ));
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    // If the timer weren't cancelled, flutter_test's fake-async pending-timer
    // check at the end of the test would fail.
  });
}
