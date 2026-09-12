import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/features/games/presentation/widgets/countdown_display.dart';

void main() {
  group('CountdownDisplay', () {
    Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('shows mm:ss for a normal remaining time', (tester) async {
      await tester.pumpWidget(wrap(const CountdownDisplay(remainingSeconds: 65)));
      expect(find.text('1:05'), findsOneWidget);
    });

    testWidgets('shows LATE chip when isLate is true', (tester) async {
      await tester.pumpWidget(
        wrap(const CountdownDisplay(remainingSeconds: -40, isLate: true)),
      );
      expect(find.text('LATE'), findsOneWidget);
      expect(find.text('0:00'), findsNothing);
    });

    testWidgets('shows an overtime hint at zero but not late yet',
        (tester) async {
      await tester.pumpWidget(
        wrap(const CountdownDisplay(remainingSeconds: -5, isLate: false)),
      );
      expect(find.text('0:00'), findsOneWidget);
      expect(find.textContaining('grace'), findsOneWidget);
    });

    testWidgets('shows Hurry in the last 10 seconds', (tester) async {
      await tester.pumpWidget(wrap(const CountdownDisplay(remainingSeconds: 8)));
      expect(find.text('Hurry'), findsOneWidget);
    });

    testWidgets('renders with no overflow at 390x844 @3x', (tester) async {
      tester.view.physicalSize = const Size(390, 844) * 3.0;
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(wrap(const CountdownDisplay(remainingSeconds: 90)));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders with no overflow at 360x640 @2x', (tester) async {
      tester.view.physicalSize = const Size(360, 640) * 2.0;
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        wrap(const CountdownDisplay(remainingSeconds: -40, isLate: true)),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
