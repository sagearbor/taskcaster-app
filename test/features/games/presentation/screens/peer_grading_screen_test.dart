import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:taskcaster_app/core/models/game.dart';
import 'package:taskcaster_app/core/models/game_settings.dart';
import 'package:taskcaster_app/core/models/player.dart';
import 'package:taskcaster_app/core/models/player_task_status.dart';
import 'package:taskcaster_app/core/models/submission.dart';
import 'package:taskcaster_app/core/models/task.dart';
import 'package:taskcaster_app/core/models/user.dart';
import 'package:taskcaster_app/core/theme/app_theme.dart';
import 'package:taskcaster_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:taskcaster_app/features/games/domain/repositories/game_repository.dart';
import 'package:taskcaster_app/features/games/presentation/bloc/peer_grading_cubit.dart';
import 'package:taskcaster_app/features/games/presentation/screens/create_game_screen.dart';
import 'package:taskcaster_app/features/games/presentation/screens/peer_grading_screen.dart';

class MockGameRepository extends Mock implements GameRepository {}

class MockAuthBloc extends Mock implements AuthBloc {}

/// WP-13: the in-game grade queue (cubit + screen) and the create-game
/// "Taskmaster mode" toggle.
void main() {
  final at = DateTime(2026, 11, 5, 10);

  Submission textEntry(String uid) => Submission(
        id: 'sub-$uid',
        userId: uid,
        text: '$uid wrote a poem',
        mediaType: SubmissionMediaType.text,
        score: 0,
        isJudged: false,
        submittedAt: at,
      );

  Game groupGame({Map<String, List<String>> peerGraders = const {}}) {
    const uids = ['me', 'sue', 'raj'];
    return Game(
      id: 'g1',
      gameName: 'Friday',
      creatorId: 'me',
      judgeId: '',
      status: GameStatus.inProgress,
      inviteCode: 'ABC234',
      createdAt: at,
      players: const [
        Player(userId: 'me', displayName: 'Me', totalScore: 0),
        Player(userId: 'sue', displayName: 'Sue', totalScore: 0),
        Player(userId: 'raj', displayName: 'Raj', totalScore: 0),
      ],
      tasks: [
        Task(
          id: 't1',
          title: 'Write an ode to a spoon',
          description: '',
          taskType: TaskType.video,
          submissions: [for (final u in uids) textEntry(u)],
          peerGraders: peerGraders,
          playerStatuses: {
            for (final u in uids)
              u: PlayerTaskStatus(
                  playerId: u,
                  state: TaskPlayerState.submitted,
                  submittedAt: at),
          },
        ),
      ],
      settings: const GameSettings(judgingMode: JudgingMode.group),
    );
  }

  late MockGameRepository repo;
  late StreamController<Game?> games;

  setUp(() {
    RecentPeerGrades.clear();
    repo = MockGameRepository();
    games = StreamController<Game?>.broadcast();
    when(() => repo.getGameStream('g1')).thenAnswer((_) async* {
      yield groupGame();
      yield* games.stream;
    });
  });

  tearDown(() => games.close());

  void stubGrade({Object? error}) {
    when(() => repo.submitPeerGrade(
          gameId: any(named: 'gameId'),
          taskIndex: any(named: 'taskIndex'),
          taskId: any(named: 'taskId'),
          targetUid: any(named: 'targetUid'),
          graderUid: any(named: 'graderUid'),
          score: any(named: 'score'),
        )).thenAnswer((_) async {
      if (error != null) throw error;
    });
  }

  group('PeerGradingCubit', () {
    blocTest<PeerGradingCubit, PeerGradingState>(
      'queues the other two entries, then empties as you grade',
      setUp: stubGrade,
      build: () => PeerGradingCubit(
        gameRepository: repo,
        gameId: 'g1',
        taskIndex: 0,
        currentUserId: 'me',
      ),
      act: (cubit) async {
        await Future<void>.delayed(Duration.zero);
        await cubit.grade('sue', 4);
        await cubit.grade('raj', 2);
      },
      verify: (cubit) {
        final s = cubit.state as PeerGradingReady;
        expect(s.isDone, isTrue);
        expect(s.gradedCount, 2);
        verify(() => repo.submitPeerGrade(
              gameId: 'g1',
              taskIndex: 0,
              taskId: 't1',
              targetUid: 'sue',
              graderUid: 'me',
              score: 4,
            )).called(1);
        expect(RecentPeerGrades.targets('g1', 't1'), {'sue', 'raj'});
      },
    );

    blocTest<PeerGradingCubit, PeerGradingState>(
      'a refused grade (already graded elsewhere) skips the entry',
      setUp: () => stubGrade(error: const PeerGradeRejected('permission-denied')),
      build: () => PeerGradingCubit(
        gameRepository: repo,
        gameId: 'g1',
        taskIndex: 0,
        currentUserId: 'me',
      ),
      act: (cubit) async {
        await Future<void>.delayed(Duration.zero);
        await cubit.grade('sue', 4);
      },
      verify: (cubit) {
        final s = cubit.state as PeerGradingReady;
        expect(s.queue.map((e) => e.userId), ['raj']);
        expect(s.error, isNull);
      },
    );

    blocTest<PeerGradingCubit, PeerGradingState>(
      'a network failure keeps the entry and says so',
      setUp: () => stubGrade(error: Exception('offline')),
      build: () => PeerGradingCubit(
        gameRepository: repo,
        gameId: 'g1',
        taskIndex: 0,
        currentUserId: 'me',
      ),
      act: (cubit) async {
        await Future<void>.delayed(Duration.zero);
        await cubit.grade('sue', 4);
      },
      verify: (cubit) {
        final s = cubit.state as PeerGradingReady;
        expect(s.queue.map((e) => e.userId), ['sue', 'raj']);
        expect(s.error, isNotNull);
      },
    );

    blocTest<PeerGradingCubit, PeerGradingState>(
      'the server echo (peerGraders) is honoured too',
      build: () => PeerGradingCubit(
        gameRepository: repo,
        gameId: 'g1',
        taskIndex: 0,
        currentUserId: 'me',
      ),
      act: (cubit) async {
        await Future<void>.delayed(Duration.zero);
        games.add(groupGame(peerGraders: const {
          'sue': ['me'],
        }));
        await Future<void>.delayed(Duration.zero);
      },
      verify: (cubit) {
        final s = cubit.state as PeerGradingReady;
        expect(s.queue.map((e) => e.userId), ['raj']);
        expect(s.gradedCount, 1);
      },
    );
  });

  group('PeerGradingScreen', () {
    Future<void> pumpScreen(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: PeerGradingScreen(
          gameId: 'g1',
          taskIndex: 0,
          currentUserId: 'me',
          gameRepository: repo,
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('grades each friend\'s entry in turn, then says all graded',
        (tester) async {
      stubGrade();
      await pumpScreen(tester);

      expect(find.text('ENTRY 1 OF 2'), findsOneWidget);
      expect(find.text('Sue'), findsOneWidget);
      expect(find.text('sue wrote a poem'), findsOneWidget);
      expect(find.text('me wrote a poem'), findsNothing,
          reason: 'never your own entry');

      await tester.ensureVisible(find.text('4'));
      await tester.tap(find.text('4'));
      await tester.pumpAndSettle();

      expect(find.text('ENTRY 2 OF 2'), findsOneWidget);
      expect(find.text('raj wrote a poem'), findsOneWidget);

      await tester.ensureVisible(find.text('5'));
      await tester.tap(find.text('5'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('peer-grade-done')), findsOneWidget);
      expect(find.text('All graded'), findsOneWidget);
      verify(() => repo.submitPeerGrade(
            gameId: 'g1',
            taskIndex: 0,
            taskId: 't1',
            targetUid: 'raj',
            graderUid: 'me',
            score: 5,
          )).called(1);
    });

    testWidgets('a failed grade shows a snackbar and keeps the entry',
        (tester) async {
      stubGrade(error: Exception('offline'));
      await pumpScreen(tester);
      await tester.ensureVisible(find.text('3'));
      await tester.tap(find.text('3'));
      await tester.pumpAndSettle();
      expect(find.textContaining("Couldn't save that grade"), findsOneWidget);
      expect(find.text('ENTRY 1 OF 2'), findsOneWidget);
    });
  });

  group('CreateGameScreen — Taskmaster mode', () {
    late MockAuthBloc auth;
    final getIt = GetIt.instance;

    setUpAll(() => registerFallbackValue(JudgingMode.judge));

    setUp(() async {
      await getIt.reset();
      getIt.registerSingleton<GameRepository>(repo);
      auth = MockAuthBloc();
      when(() => auth.state).thenReturn(AuthAuthenticated(
        user: User(
          id: 'me',
          displayName: 'Me',
          createdAt: DateTime(2026, 1, 1),
        ),
      ));
      when(() => auth.stream)
          .thenAnswer((_) => const Stream<AuthState>.empty());
      // Stop right after createGame so the screen does not navigate away.
      when(() => repo.createGame(any(), any(), any(),
              judgingMode: any(named: 'judgingMode')))
          .thenThrow(Exception('stop here'));
    });

    tearDown(() => getIt.reset());

    Future<void> pumpCreate(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: BlocProvider<AuthBloc>.value(
          value: auth,
          child: const CreateGameScreen(),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('off by default: a new friend game is graded by everyone',
        (tester) async {
      await pumpCreate(tester);
      expect(find.text('Taskmaster mode'), findsOneWidget);
      await tester.tap(find.byKey(const Key('create-and-invite')));
      await tester.pumpAndSettle();
      verify(() => repo.createGame(any(), 'me', 'me',
          judgingMode: JudgingMode.group)).called(1);
    });

    testWidgets('on: the creator judges', (tester) async {
      await pumpCreate(tester);
      await tester.tap(find.byKey(const Key('create-game-taskmaster')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('create-and-invite')));
      await tester.pumpAndSettle();
      verify(() => repo.createGame(any(), 'me', 'me',
          judgingMode: JudgingMode.judge)).called(1);
    });
  });
}
