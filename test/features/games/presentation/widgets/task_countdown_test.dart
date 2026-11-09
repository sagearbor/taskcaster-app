import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/features/games/presentation/widgets/task_countdown.dart';

void main() {
  // A fixed, injected clock: no test depends on the real wall clock.
  final t0 = DateTime.utc(2026, 11, 9, 12);

  Widget countdown(DateTime startedAt, int durationSeconds,
          DateTime Function() now) =>
      MaterialApp(
        home: Scaffold(
          body: TaskCountdown(
            startedAt: startedAt,
            durationSeconds: durationSeconds,
            now: now,
          ),
        ),
      );

  testWidgets('shows the remaining time computed from startedAt',
      (tester) async {
    final startedAt = t0.subtract(const Duration(seconds: 20));
    await tester.pumpWidget(countdown(startedAt, 90, () => t0));

    expect(find.text('1:10'), findsOneWidget);
  });

  testWidgets('shows the full duration the instant it starts',
      (tester) async {
    await tester.pumpWidget(countdown(t0, 10, () => t0));

    expect(find.text('0:10'), findsOneWidget);
  });

  testWidgets('ticks down once a second from the injected clock',
      (tester) async {
    var now = t0;
    await tester.pumpWidget(countdown(t0, 10, () => now));
    expect(find.text('0:10'), findsOneWidget);

    now = t0.add(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('0:07'), findsOneWidget);
  });

  testWidgets('shows LATE once past the grace period', (tester) async {
    final startedAt = t0.subtract(const Duration(seconds: 200));
    await tester.pumpWidget(countdown(startedAt, 90, () => t0));

    expect(find.text('LATE'), findsOneWidget);
  });

  testWidgets('cancels its timer on dispose (no pending-timer test failure)',
      (tester) async {
    await tester.pumpWidget(countdown(t0, 30, () => t0));
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    // If the timer weren't cancelled, flutter_test's fake-async pending-timer
    // check at the end of the test would fail.
  });
}
