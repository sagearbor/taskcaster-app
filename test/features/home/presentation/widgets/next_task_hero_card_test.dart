import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/features/home/presentation/widgets/next_task_hero_card.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('hasTask mode shows the task title, timer pill and Start',
      (tester) async {
    var tapped = false;
    await tester.pumpWidget(wrap(NextTaskHeroCard(
      mode: NextTaskHeroMode.hasTask,
      taskTitle: 'Rename a household object',
      timerSeconds: 60,
      onPrimary: () => tapped = true,
    )));

    expect(find.text('Rename a household object'), findsOneWidget);
    expect(find.text('⏱ 60 s'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);

    await tester.tap(find.text('Start'));
    expect(tapped, isTrue);
  });

  testWidgets('allDone mode offers to play with friends', (tester) async {
    await tester.pumpWidget(wrap(NextTaskHeroCard(
      mode: NextTaskHeroMode.allDone,
      onPrimary: () {},
    )));

    expect(find.textContaining('done all ten'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
  });

  testWidgets('noStarterGame mode invites the user to start', (tester) async {
    await tester.pumpWidget(wrap(NextTaskHeroCard(
      mode: NextTaskHeroMode.noStarterGame,
      onPrimary: () {},
    )));

    expect(find.textContaining('first ten tasks are waiting'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
  });

  testWidgets('renders with no overflow at 390x844 @3x and 360x640 @2x',
      (tester) async {
    final card = NextTaskHeroCard(
      mode: NextTaskHeroMode.hasTask,
      taskTitle: 'The face of someone who has just remembered the oven is '
          'on — in another country',
      timerSeconds: 30,
      onPrimary: () {},
    );

    tester.view.physicalSize = const Size(390, 844) * 3.0;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(wrap(card));
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(360, 640) * 2.0;
    tester.view.devicePixelRatio = 2.0;
    await tester.pumpWidget(wrap(card));
    expect(tester.takeException(), isNull);
  });
}
