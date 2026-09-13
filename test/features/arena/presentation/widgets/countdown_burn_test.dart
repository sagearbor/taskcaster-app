import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/features/arena/presentation/widgets/countdown_burn.dart';

void main() {
  group('CountdownBurn.label', () {
    test('counts down from the timer less the offset', () {
      // Filmed 40 s into a 90 s task: the clip opens showing 50 s left.
      expect(
        CountdownBurn.label(
          timerSeconds: 90,
          clockOffsetSeconds: 40,
          positionSeconds: 0,
        ),
        '0:50',
      );
      expect(
        CountdownBurn.label(
          timerSeconds: 90,
          clockOffsetSeconds: 40,
          positionSeconds: 20,
        ),
        '0:30',
      );
    });

    test('formats past a minute as M:SS', () {
      expect(
        CountdownBurn.label(
          timerSeconds: 180,
          clockOffsetSeconds: 0,
          positionSeconds: 0,
        ),
        '3:00',
      );
      expect(
        CountdownBurn.label(
          timerSeconds: 180,
          clockOffsetSeconds: 5,
          positionSeconds: 10,
        ),
        '2:45',
      );
    });

    test('a null offset counts from the whole timer', () {
      expect(
        CountdownBurn.label(
          timerSeconds: 30,
          clockOffsetSeconds: null,
          positionSeconds: 0,
        ),
        '0:30',
      );
    });

    test('stops at 0:00 for an on-time clip', () {
      expect(
        CountdownBurn.label(
          timerSeconds: 30,
          clockOffsetSeconds: 25,
          positionSeconds: 20,
        ),
        '0:00',
      );
    });

    test('reads LATE once a late clip runs the clock out', () {
      expect(
        CountdownBurn.label(
          timerSeconds: 30,
          clockOffsetSeconds: 25,
          positionSeconds: 20,
          isLate: true,
        ),
        'LATE',
      );
      // Still counting down: not late yet, even on a late post.
      expect(
        CountdownBurn.label(
          timerSeconds: 30,
          clockOffsetSeconds: 0,
          positionSeconds: 5,
          isLate: true,
        ),
        '0:25',
      );
    });

    test('is null when the task has no clock', () {
      expect(
        CountdownBurn.label(
          timerSeconds: null,
          clockOffsetSeconds: 0,
          positionSeconds: 0,
        ),
        isNull,
      );
      expect(
        CountdownBurn.label(
          timerSeconds: 0,
          clockOffsetSeconds: 0,
          positionSeconds: 0,
        ),
        isNull,
      );
    });
  });

  group('CountdownBurn.isBurning', () {
    test('turns on inside the last ten seconds', () {
      bool burning(double position) => CountdownBurn.isBurning(
            timerSeconds: 30,
            clockOffsetSeconds: 0,
            positionSeconds: position,
          );
      expect(burning(0), isFalse);
      expect(burning(19), isFalse);
      expect(burning(20), isTrue);
      expect(burning(29), isTrue);
    });

    test('is false when there is no clock', () {
      expect(
        CountdownBurn.isBurning(
          timerSeconds: null,
          clockOffsetSeconds: 0,
          positionSeconds: 0,
        ),
        isFalse,
      );
    });
  });

  group('CountdownBurn widget', () {
    Future<void> pump(WidgetTester tester, Widget child) =>
        tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: child))));

    testWidgets('renders the clock', (tester) async {
      await pump(
        tester,
        const CountdownBurn(
          timerSeconds: 60,
          clockOffsetSeconds: 10,
          positionSeconds: 5,
        ),
      );
      expect(find.text('0:45'), findsOneWidget);
    });

    testWidgets('renders nothing without a task clock', (tester) async {
      await pump(
        tester,
        const CountdownBurn(
          timerSeconds: null,
          clockOffsetSeconds: null,
          positionSeconds: 0,
        ),
      );
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('shows LATE on a late clip past the clock', (tester) async {
      await pump(
        tester,
        const CountdownBurn(
          timerSeconds: 30,
          clockOffsetSeconds: 29,
          positionSeconds: 10,
          isLate: true,
        ),
      );
      expect(find.text('LATE'), findsOneWidget);
    });
  });
}
