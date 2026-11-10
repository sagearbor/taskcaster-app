// WP-11 placement rules: the paywall NEVER appears on cold open, invite /
// join, the first task or grading. It appears only when a limit is hit (and
// then with a free fallback in the same sheet) or from Settings.
//
// Each flow runs with a RecordingPaywallLauncher in the service locator, the
// one door every screen must go through to present the paywall or the
// upgrade prompt, and asserts it recorded nothing. A source scan backs it up:
// no screen outside the allowed ones may reference the paywall at all.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taskcaster_app/core/di/service_locator.dart';
import 'package:taskcaster_app/core/models/game.dart';
import 'package:taskcaster_app/core/models/game_settings.dart';
import 'package:taskcaster_app/core/models/player.dart';
import 'package:taskcaster_app/core/models/player_task_status.dart';
import 'package:taskcaster_app/core/models/submission.dart';
import 'package:taskcaster_app/core/models/task.dart';
import 'package:taskcaster_app/core/models/user.dart';
import 'package:taskcaster_app/core/services/photo/photo_capture.dart';
import 'package:taskcaster_app/core/services/plans/plan_repository.dart';
import 'package:taskcaster_app/core/services/plans/plans.dart';
import 'package:taskcaster_app/core/services/video/video_capture.dart';
import 'package:taskcaster_app/core/services/video/video_uploader.dart';
import 'package:taskcaster_app/features/arena/data/datasources/mock_feed_data_source.dart';
import 'package:taskcaster_app/features/arena/data/repositories/feed_repository_impl.dart';
import 'package:taskcaster_app/features/arena/data/repositories/mock_montage_repository.dart';
import 'package:taskcaster_app/features/arena/domain/models/feed_post.dart';
import 'package:taskcaster_app/features/arena/domain/repositories/feed_repository.dart';
import 'package:taskcaster_app/features/arena/domain/repositories/montage_repository.dart';
import 'package:taskcaster_app/features/arena/presentation/screens/arena_screen.dart';
import 'package:taskcaster_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:taskcaster_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:taskcaster_app/features/games/domain/repositories/game_repository.dart';
import 'package:taskcaster_app/features/games/presentation/bloc/task_execution_bloc.dart';
import 'package:taskcaster_app/features/games/presentation/bloc/task_execution_event.dart';
import 'package:taskcaster_app/features/games/presentation/screens/join_game_screen.dart';
import 'package:taskcaster_app/features/games/presentation/screens/task_execution_screen.dart';
import 'package:taskcaster_app/features/onboarding/presentation/screens/cold_open_screen.dart';
import 'package:taskcaster_app/features/paywall/presentation/paywall_launcher.dart';
import 'package:taskcaster_app/features/settings/presentation/screens/settings_screen.dart';

import '../../helpers/fake_video_player_platform.dart';

class MockGameRepository extends Mock implements GameRepository {}

class MockAuthRepository extends Mock implements AuthRepository {}

class FakeGame extends Fake implements Game {}

/// A valid 1x1 PNG, so the photo preview (Image.memory) can decode it.
final Uint8List _onePixelPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=');

Task _starterTask() => Task(
      id: 'starter-01',
      title: 'Egg on a spoon, to the far wall and back',
      description: 'Put an egg on a spoon and walk to the far wall.',
      taskType: TaskType.video,
      submissionType: SubmissionType.video,
      durationSeconds: 30,
      submissions: const [],
      playerStatuses: {
        'guest1': PlayerTaskStatus(
          playerId: 'guest1',
          state: TaskPlayerState.in_progress,
          startedAt: DateTime.now().subtract(const Duration(seconds: 6)),
        ),
      },
    );

Game _game(Task task) => Game(
      id: 'game1',
      gameName: 'Your First Ten',
      creatorId: 'guest1',
      judgeId: 'guest1',
      status: GameStatus.inProgress,
      inviteCode: 'ABC123',
      createdAt: DateTime.now(),
      gameKind: Game.kindStarter,
      players: const [
        Player(userId: 'guest1', displayName: 'Guest', totalScore: 0),
      ],
      tasks: [task],
      settings: const GameSettings(crowdJudged: true, shareToArena: true),
    );

void main() {
  late RecordingPaywallLauncher launcher;
  late AuthBloc authBloc;

  setUpAll(() => registerFallbackValue(FakeGame()));

  AuthBloc makeAuth(String uid) {
    final repo = MockAuthRepository();
    when(() => repo.getCurrentUser()).thenAnswer((_) async => User(
          id: uid,
          displayName: 'Guest',
          createdAt: DateTime(2026, 1, 1),
        ));
    return AuthBloc(authRepository: repo);
  }

  Future<void> signIn(WidgetTester tester) async {
    await tester.runAsync(() async {
      authBloc.add(AuthCheckRequested());
      await authBloc.stream.firstWhere((s) => s is AuthAuthenticated);
    });
  }

  void tallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(600, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await sl.reset();
    launcher = RecordingPaywallLauncher();
    authBloc = makeAuth('guest1');
  });

  tearDown(() => authBloc.close());

  testWidgets('cold open: Start never shows the paywall', (tester) async {
    sl.registerSingleton<PaywallLauncher>(launcher);
    var started = false;
    await tester.pumpWidget(BlocProvider<AuthBloc>.value(
      value: authBloc,
      child: MaterialApp(
        home: ColdOpenScreen(
          taskTitle: 'A vegetable that has just received terrible news',
          taskDescription: 'Photograph it.',
          timerSeconds: 90,
          onStart: () => started = true,
        ),
      ),
    ));
    await tester.tap(find.text('Start — 90 s'));
    await tester.pump();
    expect(started, isTrue);
    expect(launcher.presentations, isEmpty);
  });

  testWidgets('invite / join: joining by code never shows the paywall',
      (tester) async {
    tallSurface(tester);
    await ServiceLocator.init(useMockServices: true);
    sl.unregister<PaywallLauncher>();
    sl.registerSingleton<PaywallLauncher>(launcher);
    await signIn(tester);
    await tester.pumpWidget(BlocProvider<AuthBloc>.value(
      value: authBloc,
      child: const MaterialApp(home: JoinGameScreen()),
    ));
    await tester.enterText(find.byType(TextField).first, 'PARTY1');
    await tester.tap(find.text('Join Game'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(launcher.presentations, isEmpty);
  });

  testWidgets('grading in the Arena never shows the paywall', (tester) async {
    tallSurface(tester);
    final feedSource = MockFeedDataSource();
    addTearDown(feedSource.dispose);
    final feed = FeedRepositoryImpl(feedSource);
    sl.registerSingleton<PaywallLauncher>(launcher);
    sl.registerSingleton<FeedRepository>(feed);
    sl.registerSingleton<MontageRepository>(MockMontageRepository());
    sl.registerSingleton<PlanRepository>(
        MockPlanRepository(initial: UserPlan.guest));
    await tester.runAsync(() async {
      // Post first (unlocks the task), then someone else's attempt to grade.
      await feed.createPost(FeedPost(
        id: '',
        gameId: 'game1',
        taskId: 'starter-01',
        taskTitle: 'Egg',
        rubric: 'Distance',
        userId: 'guest1',
        displayName: 'Guest',
        mediaType: SubmissionMediaType.text,
        text: 'mine',
        createdAt: DateTime(2026, 1, 1),
      ));
      await feed.createPost(FeedPost(
        id: '',
        gameId: 'game2',
        taskId: 'starter-01',
        taskTitle: 'Egg',
        rubric: 'Distance',
        userId: 'other',
        displayName: 'Greg',
        mediaType: SubmissionMediaType.text,
        text: 'theirs',
        createdAt: DateTime(2026, 1, 1),
      ));
    });
    await signIn(tester);
    await tester.pumpWidget(BlocProvider<AuthBloc>.value(
      value: authBloc,
      child: const MaterialApp(home: ArenaScreen()),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('theirs'), findsOneWidget, reason: 'a post to grade');
    await tester.tap(find.text('4').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('✓ 1 graded'), findsOneWidget);
    expect(launcher.presentations, isEmpty);
  });

  group('the first task (a guest, filming)', () {
    late MockGameRepository games;
    late MockFeedDataSource feedSource;

    Future<TaskExecutionBloc> pumpTask(
      WidgetTester tester, {
      required VideoUploader uploader,
      Uint8List? photo,
    }) async {
      tallSurface(tester);
      FakeVideoPlayerPlatform.install();
      games = MockGameRepository();
      feedSource = MockFeedDataSource();
      addTearDown(feedSource.dispose);
      when(() => games.getGameStream('game1'))
          .thenAnswer((_) => Stream.value(_game(_starterTask())));
      when(() => games.updateGame(any(), any())).thenAnswer((_) async {});
      sl.registerSingleton<GameRepository>(games);
      sl.registerSingleton<FeedRepository>(FeedRepositoryImpl(feedSource));
      sl.registerSingleton<VideoCapture>(FakeVideoCapture(PickedVideo(
        bytes: Uint8List.fromList(List.filled(512, 4)),
        contentType: 'video/mp4',
        sourcePath: '/tmp/a.mp4',
      )));
      sl.registerSingleton<VideoUploader>(uploader);
      sl.registerSingleton<PhotoCapture>(
          FakePhotoCapture(photo ?? _onePixelPng));
      sl.registerSingleton<PlanRepository>(
          MockPlanRepository(initial: UserPlan.guest));
      if (!sl.isRegistered<PaywallLauncher>()) {
        sl.registerSingleton<PaywallLauncher>(launcher);
      }

      final bloc = TaskExecutionBloc(
        gameRepository: games,
        feedRepository: FeedRepositoryImpl(feedSource),
        videoUploader: uploader,
        planRepository: sl<PlanRepository>(),
      )..add(const LoadTask(gameId: 'game1', taskIndex: 0, userId: 'guest1'));
      addTearDown(bloc.close);

      await signIn(tester);
      await tester.pumpWidget(MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>.value(value: authBloc),
          BlocProvider<TaskExecutionBloc>.value(value: bloc),
        ],
        child: const MaterialApp(
          home: TaskExecutionView(
              gameId: 'game1', taskIndex: 0, userId: 'guest1'),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      return bloc;
    }

    Future<void> filmAndPost(WidgetTester tester) async {
      await tester.tap(find.textContaining('Film it'));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Post it'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('filming and posting the first clip never shows the paywall',
        (tester) async {
      final uploader = FakeVideoUploader();
      await pumpTask(tester, uploader: uploader);
      expect(find.text('20 s clip'), findsOneWidget,
          reason: 'a guest records 20 s clips');
      await filmAndPost(tester);
      expect(uploader.calls.single.limits, PlanLimits.guest);
      expect(launcher.presentations, isEmpty);
    });

    testWidgets('the 6th guest clip shows the limit prompt (and only that)',
        (tester) async {
      await pumpTask(tester,
          uploader: FakeVideoUploader(
              error: const DailyVideoLimitReached(tier: PlanTier.guest)));
      await filmAndPost(tester);
      expect(launcher.presentations, ['limit:guest']);
    });

    testWidgets(
        'guest at the limit sees Post as photo + Sign in free + Go Pro, '
        'and can still post a photo', (tester) async {
      sl.registerSingleton<PaywallLauncher>(const DefaultPaywallLauncher());
      await pumpTask(tester,
          uploader: FakeVideoUploader(
              error: const DailyVideoLimitReached(tier: PlanTier.guest)));
      await filmAndPost(tester);
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Post it as a photo instead'), findsOneWidget);
      expect(find.text('Sign in free (3 clips a day)'), findsOneWidget);
      expect(find.text('Go Pro'), findsOneWidget);

      await tester.tap(find.text('Post it as a photo instead'));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(sl<PhotoCapture>() is FakePhotoCapture, isTrue);
      expect((sl<PhotoCapture>() as FakePhotoCapture).calls, [true]);

      await tester.tap(find.text('Post it'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final posts = await tester.runAsync(() => FeedRepositoryImpl(feedSource)
          .watchQueue(viewerId: 'nobody', unlockedTaskIds: {'starter-01'})
          .first);
      expect(posts!.where((p) => p.mediaType == SubmissionMediaType.photo),
          isNotEmpty);
    });
  });

  testWidgets('Settings > TaskCaster Pro opens the paywall', (tester) async {
    tallSurface(tester);
    await ServiceLocator.init(useMockServices: true);
    sl.unregister<PaywallLauncher>();
    sl.registerSingleton<PaywallLauncher>(launcher);
    await tester.pumpWidget(BlocProvider<AuthBloc>.value(
      value: authBloc,
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await tester.pump();
    expect(find.text('TaskCaster Pro'), findsOneWidget);
    expect(launcher.presentations, isEmpty, reason: 'not on open');
    await tester.tap(find.byKey(const Key('settings.taskcasterPro')));
    await tester.pump();
    expect(launcher.presentations, ['paywall:settings']);
  });

  test('source scan: only Settings and the task screen reach the paywall', () {
    const allowed = {
      'lib/features/settings/presentation/screens/settings_screen.dart',
      'lib/features/games/presentation/screens/task_execution_screen.dart',
      'lib/core/di/service_locator.dart',
    };
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (path.startsWith('lib/features/paywall/')) continue;
      if (allowed.contains(path)) continue;
      final src = entity.readAsStringSync();
      if (src.contains('PaywallLauncher') ||
          src.contains('PaywallScreen') ||
          src.contains('UpgradePrompt') ||
          src.contains('showLimitPrompt')) {
        offenders.add(path);
      }
    }
    expect(offenders, isEmpty,
        reason: 'the paywall may only appear from Settings or a hit limit');
  });
}
