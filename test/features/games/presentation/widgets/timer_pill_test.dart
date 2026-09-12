import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/features/games/presentation/widgets/timer_pill.dart';

void main() {
  testWidgets('TimerPill shows the clock label with seconds', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: TimerPill(seconds: 90))),
    );
    expect(find.text('⏱ 90 s'), findsOneWidget);
  });

  testWidgets('renders with no overflow at 390x844 @3x', (tester) async {
    tester.view.physicalSize = const Size(390, 844) * 3.0;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: TimerPill(seconds: 180))),
    );
    expect(tester.takeException(), isNull);
  });
}
