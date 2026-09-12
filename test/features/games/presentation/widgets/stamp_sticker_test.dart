import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/features/games/presentation/widgets/stamp_sticker.dart';

void main() {
  testWidgets('StampSticker shows the stamp text', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: StampSticker(stamp: 'NAILED IT')),
      ),
    );
    expect(find.text('NAILED IT'), findsOneWidget);
  });

  testWidgets('is deterministic for the same stamp text', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(children: [
            StampSticker(stamp: "DON'T ASK"),
            StampSticker(stamp: "DON'T ASK"),
          ]),
        ),
      ),
    );
    final rotations = tester
        .widgetList<Transform>(find.byType(Transform))
        .map((t) => t.transform)
        .toList();
    expect(rotations[0], rotations[1]);
  });

  testWidgets('renders with no overflow at 360x640 @2x', (tester) async {
    tester.view.physicalSize = const Size(360, 640) * 2.0;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: StampSticker(stamp: 'SEND HELP')),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
