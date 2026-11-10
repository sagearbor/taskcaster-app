import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/config/environment.dart';
import 'package:taskcaster_app/core/di/service_locator.dart';
import 'package:taskcaster_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:taskcaster_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:taskcaster_app/features/home/presentation/screens/home_screen.dart';
import 'package:taskcaster_app/features/home/presentation/widgets/home_invites_section.dart';
import 'package:taskcaster_app/features/home/presentation/widgets/next_task_hero_card.dart';
import 'package:taskcaster_app/core/models/player_task_status.dart';
import 'package:taskcaster_app/core/models/submission.dart';
import 'package:taskcaster_app/core/models/user.dart';
import 'package:taskcaster_app/core/theme/app_theme.dart';
import 'package:taskcaster_app/features/arena/domain/models/feed_post.dart';
import 'package:taskcaster_app/features/arena/domain/repositories/feed_repository.dart';
import 'package:taskcaster_app/features/games/domain/repositories/game_repository.dart';
import 'package:taskcaster_app/features/games/presentation/screens/task_execution_screen.dart';
import 'package:taskcaster_app/features/tasks/data/datasources/daily_task_data.dart';
import 'package:taskcaster_app/features/tasks/data/datasources/starter_pack_data.dart';

void main() {
  setUp(() async {
    await sl.reset();
    await ServiceLocator.init(useMockServices: true);
  });
  tearDown(() => AppConfig.debugLabModesOverride = null);

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Keep the NearbyAutoCastBanner quietly idle during initState (its
    // Android path would hit real permission channels that don't exist under
    // flutter_test). The platform check runs synchronously in cubit.start(),
    // so the override can be cleared right after the first pump — and must
    // be, or the framework's invariant check fails the test.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await tester.pumpWidget(
        BlocProvider<AuthBloc>(
          create: (_) => AuthBloc(authRepository: sl<AuthRepository>()),
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
    // Let the games stream deliver its first snapshot.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets(
      'the invites section self-hides when there are no invites (no empty '
      'shame box)', (tester) async {
    await pumpHome(tester);

    // The widget is mounted (it still needs to watch the invites stream so
    // it can appear the moment an invite arrives) but renders nothing (a
    // zero-size SizedBox.shrink(), hence skipOffstage: false below) — no
    // "Invites from friends" header, no "No invites yet" shame box.
    expect(
      find.byType(HomeInvitesSection, skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('Invites from friends'), findsNothing);
    expect(find.textContaining('No invites yet'), findsNothing);
  });

  testWidgets('the app bar "+" opens the three-row release sheet',
      (tester) async {
    AppConfig.debugLabModesOverride = false;
    await pumpHome(tester);

    // WP-05: no big Play button on the page any more.
    expect(find.widgetWithText(FilledButton, 'Play'), findsNothing);
    await tester.tap(find.byKey(const Key('home-play-plus')));
    await tester.pumpAndSettle();

    expect(find.text('Challenge friends'), findsOneWidget);
    expect(find.text('Join with a code'), findsOneWidget);
    expect(find.text('Drawing Telephone (same room)'), findsOneWidget);
    expect(find.text('Quick Play'), findsNothing);
    expect(find.text('Discover'), findsNothing);
  });

  testWidgets('Challenge friends lands in the new lobby with the invite up',
      (tester) async {
    AppConfig.debugLabModesOverride = false;
    await tester.runAsync(() => sl<AuthRepository>().signInAnonymously());
    await pumpHome(tester);

    await tester.tap(find.byKey(const Key('home-play-plus')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Challenge friends'));
    // Mock repo create + addTasks, then the lobby's share dialog opens on
    // the first loaded frame.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }

    expect(find.text('Share Game Invite'), findsOneWidget);
  });

  testWidgets('Balloon Pop (Lab) offers a Solo / Multiplayer chooser',
      (tester) async {
    AppConfig.debugLabModesOverride = true;
    await pumpHome(tester);

    await tester.tap(find.byKey(const Key('home-play-plus')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Balloon Pop'));
    await tester.pumpAndSettle();

    expect(find.text('Solo'), findsOneWidget);
    expect(find.text('Multiplayer race'), findsOneWidget);
  });

  testWidgets('the games list renders under "Your games"', (tester) async {
    await pumpHome(tester);

    // Seeded mock games from MockGameDataSource, as one plain list.
    expect(find.text('Your games'), findsOneWidget);
    expect(find.text('Jump back in'), findsNothing);
    expect(find.text('Saturday Night Shenanigans'), findsOneWidget);
  });

  testWidgets('at 390x844 exactly one filled button is above the fold',
      (tester) async {
    await pumpHome(tester);
    tester.view.physicalSize = const Size(390, 844) * 3.0;
    tester.view.devicePixelRatio = 3.0;
    await tester.pump(const Duration(milliseconds: 100));

    final filled = find.byType(FilledButton).hitTestable();
    expect(filled, findsOneWidget);
    // ...and it is the hero's.
    expect(
      find.descendant(
          of: find.byType(NextTaskHeroCard), matching: find.byType(FilledButton)),
      findsOneWidget,
    );
    // The Arena row sits right under it, outlined.
    expect(find.widgetWithText(OutlinedButton, 'Arena — grade the crowd'),
        findsOneWidget);
    // Layout overflow is NOT asserted here: the test font (Ahem, square
    // glyphs) overflows the seeded GameCards' fixed rows at this width. The
    // real 390x844 layout is checked in headless Chrome.
    tester.takeException();
  });

  testWidgets(
      'zone 1 shows the starter-pack hero when the user has no starter game '
      'yet', (tester) async {
    await pumpHome(tester);

    // MockGameDataSource seeds ordinary games but no gameKind == 'starter'
    // one, so the hero should invite the (pre-round-7) user to start theirs.
    expect(
      find.textContaining('first ten tasks are waiting'),
      findsOneWidget,
    );
    expect(find.text('Start'), findsOneWidget);
  });

  testWidgets('the Arena button opens the Arena screen', (tester) async {
    await pumpHome(tester);

    await tester.tap(find.text('Arena — grade the crowd'));
    await tester.pumpAndSettle();

    expect(find.text('The Arena'), findsOneWidget);
  });

  testWidgets('the app bar no longer shows a Join button', (tester) async {
    await pumpHome(tester);
    // Code entry moved into the invites empty state + Play sheet.
    expect(find.widgetWithText(TextButton, 'Join'), findsNothing);
  });

  group('WP-6 hero: starter, today\'s task, done for today', () {
    // 18:48 UTC: the next task is 5 h 12 m away.
    final now = DateTime.utc(2026, 11, 9, 18, 48);
    final yesterday = now.subtract(const Duration(days: 1));
    final dailyTask = DailyTaskData.taskFor(now);

    late User user;

    /// Sign in, create the starter game with [starterPosted] tasks posted,
    /// optionally today's daily game (posted or not), and [posts] (task id ->
    /// time) as the player's own Arena posts.
    Future<void> seed(
      WidgetTester tester, {
      required int starterPosted,
      bool? dailyPosted,
      Map<String, DateTime> posts = const {},
    }) async {
      await tester.runAsync(() async {
        user = await sl<AuthRepository>().signInAnonymously();
        final games = sl<GameRepository>();
        final starterId = await games.createStarterGame(user);
        final starter = (await games.getGameStream(starterId).first)!;
        await games.updateGame(
          starterId,
          starter.copyWith(tasks: [
            for (var i = 0; i < starter.tasks.length; i++)
              starter.tasks[i].copyWith(playerStatuses: {
                user.id: PlayerTaskStatus(
                  playerId: user.id,
                  state: i < starterPosted
                      ? TaskPlayerState.submitted
                      : TaskPlayerState.not_started,
                ),
              }),
          ]),
        );
        if (dailyPosted != null) {
          final dailyId = await games.createOrGetDailyGame(
              user, DailyTaskData.dayKey(now));
          if (dailyPosted) {
            await games.updateTaskAtomically(
              dailyId,
              0,
              (t) => t.copyWith(playerStatuses: {
                user.id: PlayerTaskStatus(
                  playerId: user.id,
                  state: TaskPlayerState.submitted,
                ),
              }),
            );
          }
        }
        final feed = sl<FeedRepository>();
        for (final e in posts.entries) {
          await feed.createPost(FeedPost(
            id: '',
            gameId: 'g',
            taskId: e.key,
            taskTitle: 't',
            userId: user.id,
            displayName: user.displayName,
            mediaType: SubmissionMediaType.text,
            text: 'x',
            createdAt: e.value,
          ));
        }
      });
    }

    Future<void> pumpAt(WidgetTester tester, Size size, double dpr,
        {bool dark = false}) async {
      tester.view.physicalSize = size * dpr;
      tester.view.devicePixelRatio = dpr;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await tester.pumpWidget(
          BlocProvider<AuthBloc>(
            create: (_) => AuthBloc(authRepository: sl<AuthRepository>())
              ..add(AuthCheckRequested()),
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: dark ? ThemeMode.dark : ThemeMode.light,
              home: HomeScreen(clock: () => now),
            ),
          ),
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Finder inHero(Finder f) =>
        find.descendant(of: find.byType(NextTaskHeroCard), matching: f);

    testWidgets('starter in progress, nothing today: the starter task with '
        'its streak at risk', (tester) async {
      await seed(tester, starterPosted: 2, posts: {'starter-03': yesterday});
      await pumpAt(tester, const Size(800, 2200), 1);

      expect(find.text('YOUR NEXT TASK'), findsOneWidget);
      expect(find.text(StarterPackData.tasks()[2].title), findsOneWidget);
      expect(inHero(find.text('🔥 1')), findsOneWidget);
      expect(find.textContaining('or the 🔥 1 goes out'), findsOneWidget);
    });

    testWidgets("a starter task posted today brings today's task forward, "
        'with a way back to the starter', (tester) async {
      await seed(tester, starterPosted: 1, posts: {'starter-09-v2': now});
      await pumpAt(tester, const Size(800, 2200), 1);

      expect(find.text("TODAY'S TASK"), findsOneWidget);
      expect(find.text(dailyTask.title), findsOneWidget);
      expect(inHero(find.text('🔥 1')), findsOneWidget);
      expect(find.text('Or carry on with your first ten (2 of 10)'),
          findsOneWidget);
    });

    testWidgets("starter finished: today's task; Start opens it",
        (tester) async {
      await seed(tester, starterPosted: 10, posts: {'starter-08-v2': yesterday});
      await pumpAt(tester, const Size(800, 2200), 1);

      expect(find.byKey(const Key('home-hero-daily')), findsOneWidget);
      expect(find.text(dailyTask.title), findsOneWidget);
      expect(find.text('Challenge friends'), findsOneWidget);

      await tester.tap(inHero(find.text('Start')));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      // The task screen for today's game is on top.
      expect(find.byType(TaskExecutionScreen), findsOneWidget);
      final games = await tester.runAsync(
          () => sl<GameRepository>().getGamesStream().first);
      expect(
        games!.where((g) =>
            g.id == DailyTaskData.gameIdFor(user.id, DailyTaskData.dayKey(now))),
        hasLength(1),
      );
      // Unmount before the mock repos' timers outlive the test.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('posted today: done for today, streak, countdown; the daily '
        'game stays out of "Your games"', (tester) async {
      await seed(
        tester,
        starterPosted: 10,
        dailyPosted: true,
        posts: {'starter-08-v2': yesterday, dailyTask.id: now},
      );
      await pumpAt(tester, const Size(800, 2200), 1);

      expect(find.byKey(const Key('home-hero-daily-done')), findsOneWidget);
      expect(find.text('Done for today.'), findsOneWidget);
      expect(find.text('🔥 2 days running. New task in 5 h 12 m.'),
          findsOneWidget);
      expect(find.text("See today's entries"), findsOneWidget);
      expect(find.text(DailyTaskData.gameNameFor(DailyTaskData.dayKey(now))),
          findsNothing);
      // The finished starter joins "Your games" as before.
      expect(find.text(StarterPackData.gameName), findsOneWidget);
    });

    for (final dark in [false, true]) {
      testWidgets(
          'no overflow in the hero at 360x640 (${dark ? 'dark' : 'light'})',
          (tester) async {
        await seed(
          tester,
          starterPosted: 1,
          posts: {'starter-09-v2': now, 'starter-03': yesterday},
        );
        // Only the hero is checked: the seeded GameCards overflow under the
        // Ahem test font (see the 390x844 test above).
        final errors = <String>[];
        final previous = FlutterError.onError;
        FlutterError.onError = (details) => errors.add(details.toString());
        try {
          await pumpAt(tester, const Size(360, 640), 2, dark: dark);
        } finally {
          FlutterError.onError = previous;
        }
        expect(find.byKey(const Key('home-hero-daily')), findsOneWidget);
        expect(
          errors.where((s) => s.contains('next_task_hero_card.dart')),
          isEmpty,
        );
        final hero = tester.getRect(find.byType(NextTaskHeroCard));
        expect(hero.width, lessThanOrEqualTo(360));
      });
    }
  });
}
