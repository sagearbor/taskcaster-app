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
import 'package:taskcaster_app/core/models/task.dart';
import 'package:taskcaster_app/core/services/photo/photo_capture.dart';
import 'package:taskcaster_app/core/services/sfx/game_sfx.dart';
import 'package:taskcaster_app/core/services/video/video_capture.dart';
import 'package:taskcaster_app/core/theme/app_theme.dart';
import 'package:taskcaster_app/features/games/domain/repositories/game_repository.dart';
import 'package:taskcaster_app/features/games/presentation/bloc/task_execution_bloc.dart';
import 'package:taskcaster_app/features/games/presentation/bloc/task_execution_event.dart';
import 'package:taskcaster_app/features/games/presentation/screens/task_execution_screen.dart';
import 'package:taskcaster_app/features/games/presentation/widgets/countdown_display.dart';
import 'package:taskcaster_app/features/games/presentation/widgets/gather_reveal.dart';
import 'package:taskcaster_app/features/games/presentation/widgets/up_next_card.dart';
import 'package:taskcaster_app/features/tasks/data/datasources/starter_pack_data.dart';

import '../../../../helpers/atomic_task_writes.dart';
import '../../../../helpers/recording_game_sfx.dart';

class MockGameRepository extends Mock implements GameRepository {}

class FakeGame extends Fake implements Game {}

/// Round 9: the gather -> reveal misdirect. Start shows ONLY the gather
/// stage and its countdown; "I'm back" (or zero) reveals the real task with
/// its own, still-frozen clock. Nothing of the real task may be on screen
/// before the reveal.
void main() {
  late MockGameRepository repo;
  late RecordingGameSfx sfx;

  // The real starter task 4, so the test also pins the shipped copy.
  final tower = StarterPackData.tasks()
      .firstWhere((t) => t.id == 'starter-02-v3');

  Task gatherTask({PlayerTaskStatus? status}) => tower.copyWith(
        playerStatuses: {
          'user1': status ??
              const PlayerTaskStatus(
                playerId: 'user1',
                state: TaskPlayerState.not_started,
              ),
        },
      );

  Game gameWith(Task task) => Game(
        id: 'game1',
        gameName: 'Your First Ten',
        creatorId: 'user1',
        judgeId: 'user1',
        status: GameStatus.inProgress,
        inviteCode: 'ABC123',
        createdAt: DateTime.now(),
        gameKind: Game.kindStarter,
        players: const [
          Player(userId: 'user1', displayName: 'Alice', totalScore: 0),
        ],
        tasks: [task],
        settings: const GameSettings(crowdJudged: true, shareToArena: true),
      );

  setUpAll(() => registerFallbackValue(FakeGame()));

  setUp(() async {
    await sl.reset();
    repo = MockGameRepository();
    sfx = RecordingGameSfx();
    sl.registerLazySingleton<GameSfx>(() => sfx);
    sl.registerLazySingleton<VideoCapture>(() => FakeVideoCapture());
    sl.registerLazySingleton<PhotoCapture>(() => FakePhotoCapture());
    SharedPreferences.setMockInitialValues({});
    GameSfx.resetMuteForTest();
    stubAtomicTaskWrites(repo, onWrite: (_) {});
  });
  tearDown(GameSfx.resetMuteForTest);

  Future<void> pump(
    WidgetTester tester, {
    bool autoStart = false,
    Size size = const Size(500, 1600),
    ThemeData? theme,
    Task? task,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    when(() => repo.getGameStream('game1'))
        .thenAnswer((_) => Stream.value(gameWith(task ?? gatherTask())));
    final bloc = TaskExecutionBloc(gameRepository: repo)
      ..add(const LoadTask(gameId: 'game1', taskIndex: 0, userId: 'user1'));
    addTearDown(bloc.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: BlocProvider<TaskExecutionBloc>.value(
          value: bloc,
          child: TaskExecutionView(
            gameId: 'game1',
            taskIndex: 0,
            userId: 'user1',
            autoStart: autoStart,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Nothing that would give the real task away.
  void expectNoSpoiler() {
    expect(find.textContaining(tower.title), findsNothing);
    expect(find.textContaining('tower'), findsNothing);
    expect(find.textContaining(tower.description), findsNothing);
    expect(find.textContaining(tower.twist!), findsNothing);
    expect(find.textContaining(tower.rubric!), findsNothing);
    expect(find.textContaining('Film it'), findsNothing);
  }

  testWidgets('the card before Start shows only the gather stage',
      (tester) async {
    await pump(tester);

    expect(find.text('Gather different shapes'), findsOneWidget);
    expect(find.textContaining('different shapes or numbers of sides'),
        findsOneWidget);
    expect(find.text('Start — 60 s'), findsOneWidget);
    expectNoSpoiler();
  });

  testWidgets('Start -> gather countdown -> "I\'m back" -> SURPRISE + real task',
      (tester) async {
    await pump(tester);

    await tester.tap(find.text('Start — 60 s'));
    await tester.pump(const Duration(milliseconds: 100));

    // Stage 1: the gather prompt and its own big clock.
    expect(find.byType(GatherStageView), findsOneWidget);
    expect(find.byKey(const Key('gather-countdown')), findsOneWidget);
    expect(find.text('1:00'), findsOneWidget);
    expect(find.text("I'm back"), findsOneWidget);
    expect(sfx.played, ['prime', 'go']);
    expectNoSpoiler();

    await tester.pump(const Duration(seconds: 2));
    expectNoSpoiler();

    // Stage 2: the reveal.
    await tester.tap(find.byKey(const Key('gather-im-back')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(GatherStageView), findsNothing);
    expect(find.byKey(const Key('gather-reveal-banner')), findsOneWidget);
    expect(find.text('SURPRISE.'), findsOneWidget);
    expect(find.text(tower.title), findsOneWidget);
    expect(find.text(tower.description), findsOneWidget);
    expect(find.text(tower.twist!), findsOneWidget);
    expect(find.textContaining('Film it'), findsOneWidget);
    // The real task has its own clock, frozen until the camera opens.
    final waiting = tester.widget<CountdownDisplay>(
        find.byKey(const Key('starter-clock-waiting')));
    expect(waiting.remainingSeconds, 90);
    expect(sfx.played.last, 'fanfare');
    // Gathering never stamps the task clock.
    verifyNever(() => repo.updateTaskAtomically(any(), any(), any()));
  });

  testWidgets('autoStart (from the cold open / Home) starts gathering at once',
      (tester) async {
    await pump(tester, autoStart: true);

    expect(find.byType(GatherStageView), findsOneWidget);
    expect(find.text('Start — 60 s'), findsNothing);
    expectNoSpoiler();
  });

  testWidgets('a task whose clock already runs skips the gather stage',
      (tester) async {
    await pump(
      tester,
      task: gatherTask(
        status: PlayerTaskStatus(
          playerId: 'user1',
          state: TaskPlayerState.in_progress,
          startedAt: DateTime.now().subtract(const Duration(seconds: 5)),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(GatherStageView), findsNothing);
    expect(find.text(tower.title), findsOneWidget);
  });

  group('360x640, no overflow', () {
    for (final (name, theme) in [
      ('light', AppTheme.lightTheme),
      ('dark', AppTheme.darkTheme),
    ]) {
      testWidgets('card, gather stage and reveal ($name)', (tester) async {
        await pump(tester, size: const Size(360, 640), theme: theme);
        expect(tester.takeException(), isNull);

        await tester.ensureVisible(find.text('Start — 60 s'));
        await tester.tap(find.text('Start — 60 s'));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(GatherStageView), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.ensureVisible(find.byKey(const Key('gather-im-back')));
        await tester.tap(find.byKey(const Key('gather-im-back')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.byKey(const Key('gather-reveal-banner')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('GatherStageView', () {
    testWidgets('reveals by itself when the gather clock hits zero',
        (tester) async {
      var now = DateTime(2026, 11, 10, 12);
      final started = now;
      var done = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: GatherStageView(
            task: tower,
            startedAt: started,
            now: () => now,
            sfx: sfx,
            onDone: () => done++,
          ),
        ),
      ));
      expect(find.text('1:00'), findsOneWidget);

      now = started.add(const Duration(seconds: 59));
      await tester.pump(const Duration(seconds: 1));
      expect(done, 0);
      expect(sfx.played.last, 'tick');

      now = started.add(const Duration(seconds: 60));
      await tester.pump(const Duration(seconds: 1));
      expect(done, 1);
      expect(sfx.played.last, 'fanfare');

      // Only once.
      now = started.add(const Duration(seconds: 62));
      await tester.pump(const Duration(seconds: 1));
      expect(done, 1);
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('no spoiler before you play it', () {
    test('Up next shows the gather stage until you have posted', () {
      final game = gameWith(gatherTask());
      final upNext =
          UpNext.resolve(game, currentUserId: 'user1', isJudge: false);
      expect(upNext.title, 'Gather different shapes');
      expect(upNext.detail, tower.gatherPrompt);

      final played = gameWith(gatherTask(
        status: const PlayerTaskStatus(
          playerId: 'user1',
          state: TaskPlayerState.submitted,
        ),
      ));
      expect(
        UpNext.resolve(played, currentUserId: 'user1', isJudge: false).title,
        tower.title,
      );
    });

    test('a gather task survives a serialization round trip', () {
      final back = Task.fromMap(tower.toMap());
      expect(back, tower);
      expect(back.gatherSeconds, 60);
      expect(back.hasGatherPhase, isTrue);
      // An ordinary task's map carries no gather keys at all.
      final rename = StarterPackData.tasks()[1].toMap();
      expect(rename.containsKey('gatherPrompt'), isFalse);
    });
  });
}
