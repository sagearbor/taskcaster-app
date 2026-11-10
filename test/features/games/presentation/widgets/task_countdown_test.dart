import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/theme/app_theme.dart';
import 'package:taskcaster_app/features/games/presentation/widgets/countdown_display.dart';
import 'package:taskcaster_app/features/games/presentation/widgets/task_countdown.dart';

import '../../../../helpers/recording_game_sfx.dart';

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

  group('clock juice (WP-8)', () {
    late RecordingGameSfx sfx;
    setUp(() => sfx = RecordingGameSfx());

    Widget juicy(DateTime Function() now, int duration,
            {bool reduceMotion = false}) =>
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduceMotion),
            child: Scaffold(
              body: TaskCountdown(
                startedAt: t0,
                durationSeconds: duration,
                now: now,
                sfx: sfx,
              ),
            ),
          ),
        );

    Finder flash() => find.byKey(const Key('countdown-time-up-flash'));

    testWidgets('ticks each of the last 5 seconds, then the fanfare at zero',
        (tester) async {
      var now = t0;
      await tester.pumpWidget(juicy(() => now, 10));
      for (var s = 1; s <= 11; s++) {
        now = t0.add(Duration(seconds: s));
        await tester.pump(const Duration(seconds: 1));
      }

      // 10 s clock: 9..6 silent; 5,4,3,2,1 tick; 0 fanfare; -1 silent.
      expect(sfx.played, ['tick', 'tick', 'tick', 'tick', 'tick', 'fanfare']);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('landing mid-countdown does not replay old sounds',
        (tester) async {
      // Reopened with 3 s left: no catch-up ticks for seconds already gone.
      var now = t0.add(const Duration(seconds: 7));
      await tester.pumpWidget(juicy(() => now, 10));
      expect(sfx.played, isEmpty);

      now = t0.add(const Duration(seconds: 8));
      await tester.pump(const Duration(seconds: 1));
      expect(sfx.played, ['tick']);
    });

    testWidgets('the last 10 s are coral and pulse once a second',
        (tester) async {
      var now = t0.add(const Duration(seconds: 1));
      await tester.pumpWidget(juicy(() => now, 30));
      // 29 s left: violet, no pulse.
      expect(find.byType(TweenAnimationBuilder<double>), findsNothing);

      now = t0.add(const Duration(seconds: 22));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('0:08'), findsOneWidget);
      final digits =
          tester.widget<Text>(find.byKey(const Key('countdown-digits')));
      expect(digits.style!.color, AppTheme.coral);

      // Starts at the peak and settles back to 1.0 within the second.
      double scale() => tester
          .widget<Transform>(find
              .ancestor(
                  of: find.byKey(const Key('countdown-digits')),
                  matching: find.byType(Transform))
              .first)
          .transform
          .getMaxScaleOnAxis();
      expect(scale(), closeTo(CountdownDisplay.pulseScale, 0.001));
      await tester.pump(const Duration(milliseconds: 700));
      expect(scale(), closeTo(1.0, 0.001));
    });

    testWidgets('time up flashes the screen once, then clears',
        (tester) async {
      var now = t0.add(const Duration(seconds: 9));
      await tester.pumpWidget(juicy(() => now, 10));
      expect(flash(), findsNothing);

      now = t0.add(const Duration(seconds: 10));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 50));
      expect(flash(), findsOneWidget);
      expect(find.text("Overtime: 30 s grace, then it's LATE"), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 500));
      expect(flash(), findsNothing);
    });

    testWidgets('reduced motion: no pulse and no flash, sounds still play',
        (tester) async {
      var now = t0.add(const Duration(seconds: 1));
      await tester.pumpWidget(juicy(() => now, 3, reduceMotion: true));
      expect(find.byType(TweenAnimationBuilder<double>), findsNothing);

      now = t0.add(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 50));
      expect(flash(), findsNothing);
      expect(sfx.played, ['fanfare']);
    });

    testWidgets('no overflow at 360x640 through the urgent and overtime states',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640) * 2.0;
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var now = t0.add(const Duration(seconds: 25));
      await tester.pumpWidget(juicy(() => now, 30));
      expect(tester.takeException(), isNull);
      now = t0.add(const Duration(seconds: 31));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
    });
  });
}
