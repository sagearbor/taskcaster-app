import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/features/games/presentation/widgets/task_reveal_card.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

  testWidgets('shows title, description and timer pill', (tester) async {
    await tester.pumpWidget(wrap(const TaskRevealCard(
      title: 'Rename a household object',
      description: 'Pick any object in the room…',
      timerSeconds: 60,
    )));

    expect(find.text('Rename a household object'), findsOneWidget);
    expect(find.textContaining('Pick any object'), findsOneWidget);
    expect(find.text('⏱ 60 s'), findsOneWidget);
  });

  testWidgets('hides the twist line until one is supplied', (tester) async {
    await tester.pumpWidget(wrap(const TaskRevealCard(
      title: 'T',
      description: 'D',
      timerSeconds: 60,
    )));
    expect(find.byIcon(Icons.bolt), findsNothing);

    await tester.pumpWidget(wrap(const TaskRevealCard(
      title: 'T',
      description: 'D',
      timerSeconds: 60,
      twist: 'No hands in the photo',
    )));
    expect(find.byIcon(Icons.bolt), findsOneWidget);
    expect(find.text('No hands in the photo'), findsOneWidget);
  });

  testWidgets('renders with no overflow at 390x844 @3x and 360x640 @2x',
      (tester) async {
    const longTask = TaskRevealCard(
      title: 'The face of someone who has just remembered the oven is on '
          '— in another country',
      description: 'Selfie. You have just remembered that you left the oven '
          'on. You are currently in a different country. It is 3 a.m. '
          'there. Show us every layer of that realisation in one face.',
      timerSeconds: 30,
      twist: 'No hands in the photo',
    );

    tester.view.physicalSize = const Size(390, 844) * 3.0;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(wrap(longTask));
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(360, 640) * 2.0;
    tester.view.devicePixelRatio = 2.0;
    await tester.pumpWidget(wrap(longTask));
    expect(tester.takeException(), isNull);
  });
}
