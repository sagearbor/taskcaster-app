import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/theme/app_theme.dart';
import 'package:taskcaster_app/features/home/presentation/widgets/next_task_hero_card.dart';
import 'package:taskcaster_app/features/tasks/data/datasources/daily_task_data.dart';

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

  testWidgets('allDone mode: waiting for the crowd, then Challenge friends',
      (tester) async {
    var tapped = false;
    await tester.pumpWidget(wrap(NextTaskHeroCard(
      mode: NextTaskHeroMode.allDone,
      waitingCount: 4,
      onPrimary: () => tapped = true,
    )));

    expect(find.text('Waiting for the crowd: 4'), findsOneWidget);
    expect(find.textContaining('All ten done'), findsOneWidget);
    // No more Play here: Play lives behind the app bar's "+" (WP-05).
    expect(find.text('Play'), findsNothing);
    await tester.tap(find.text('Challenge friends'));
    expect(tapped, isTrue);
  });

  testWidgets('allDone with nothing left to grade says the crowd has spoken',
      (tester) async {
    await tester.pumpWidget(wrap(NextTaskHeroCard(
      mode: NextTaskHeroMode.allDone,
      waitingCount: 0,
      onPrimary: () {},
    )));

    expect(find.text('The crowd has spoken.'), findsOneWidget);
    expect(find.text('Challenge friends'), findsOneWidget);
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

  group('WP-6 daily modes', () {
    testWidgets("dailyTask: TODAY'S TASK, title, timer, streak, Start",
        (tester) async {
      final semantics = tester.ensureSemantics();
      var started = false;
      var secondary = false;
      await tester.pumpWidget(wrap(NextTaskHeroCard(
        mode: NextTaskHeroMode.dailyTask,
        taskTitle: 'Sell us a glass of tap water',
        timerSeconds: 90,
        streak: 4,
        subline: 'Post something today or the 🔥 4 goes out.',
        secondaryLabel: 'Challenge friends',
        onSecondary: () => secondary = true,
        onPrimary: () => started = true,
      )));

      expect(find.text("TODAY'S TASK"), findsOneWidget);
      expect(find.text('Sell us a glass of tap water'), findsOneWidget);
      expect(find.text('⏱ 90 s'), findsOneWidget);
      expect(find.text('🔥 4'), findsOneWidget);
      expect(find.bySemanticsLabel('4-day streak'), findsOneWidget);
      semantics.dispose();
      expect(find.byKey(const Key('hero-subline')), findsOneWidget);

      await tester.tap(find.text('Start'));
      expect(started, isTrue);
      await tester.tap(find.text('Challenge friends'));
      expect(secondary, isTrue);
    });

    testWidgets('dailyDone: done for today, streak, countdown, entries',
        (tester) async {
      var opened = false;
      await tester.pumpWidget(wrap(NextTaskHeroCard(
        mode: NextTaskHeroMode.dailyDone,
        streak: 4,
        nextTaskIn: const Duration(hours: 5, minutes: 12),
        onPrimary: () => opened = true,
      )));

      expect(find.text('Done for today.'), findsOneWidget);
      expect(find.text('🔥 4 days running. New task in 5 h 12 m.'),
          findsOneWidget);
      // No timer pill once it's done.
      expect(find.textContaining('⏱'), findsNothing);
      await tester.tap(find.text("See today's entries"));
      expect(opened, isTrue);
    });

    testWidgets('one day reads as one day', (tester) async {
      await tester.pumpWidget(wrap(NextTaskHeroCard(
        mode: NextTaskHeroMode.dailyDone,
        streak: 1,
        nextTaskIn: const Duration(minutes: 3),
        onPrimary: () {},
      )));
      expect(find.text('🔥 1 day running. New task in 3 m.'), findsOneWidget);
    });

    testWidgets('no streak chip at 0', (tester) async {
      await tester.pumpWidget(wrap(NextTaskHeroCard(
        mode: NextTaskHeroMode.hasTask,
        taskTitle: 'x',
        timerSeconds: 60,
        onPrimary: () {},
      )));
      expect(find.byKey(const Key('hero-streak-chip')), findsNothing);
    });

    for (final dark in [false, true]) {
      testWidgets(
          'every daily task, both daily modes: no overflow at 360x640 '
          '(${dark ? 'dark' : 'light'})', (tester) async {
        tester.view.physicalSize = const Size(360, 640) * 2.0;
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        Widget themed(Widget child) => MaterialApp(
              theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
              home: Scaffold(body: SingleChildScrollView(child: child)),
            );

        for (final task in DailyTaskData.tasks()) {
          await tester.pumpWidget(themed(NextTaskHeroCard(
            mode: NextTaskHeroMode.dailyTask,
            taskTitle: task.title,
            timerSeconds: task.durationSeconds,
            streak: 128,
            subline: 'Post something today or the 🔥 128 goes out.',
            secondaryLabel: 'Or carry on with your first ten (10 of 10)',
            onSecondary: () {},
            onPrimary: () {},
          )));
          expect(tester.takeException(), isNull, reason: task.id);
        }

        await tester.pumpWidget(themed(NextTaskHeroCard(
          mode: NextTaskHeroMode.dailyDone,
          streak: 365,
          nextTaskIn: const Duration(hours: 23, minutes: 59),
          subline: 'Waiting for the crowd: 12',
          secondaryLabel: 'Challenge friends',
          onSecondary: () {},
          onPrimary: () {},
        )));
        expect(tester.takeException(), isNull);
      });
    }
  });
}
