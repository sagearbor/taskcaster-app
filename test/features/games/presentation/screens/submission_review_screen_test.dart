import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:taskcaster_app/core/models/game.dart';
import 'package:taskcaster_app/core/models/game_settings.dart';
import 'package:taskcaster_app/core/models/player.dart';
import 'package:taskcaster_app/core/models/player_task_status.dart';
import 'package:taskcaster_app/core/models/task.dart';
import 'package:taskcaster_app/features/games/domain/repositories/game_repository.dart';
import 'package:taskcaster_app/features/games/presentation/bloc/game_detail_bloc.dart';
import 'package:taskcaster_app/features/games/presentation/bloc/judging_bloc.dart';
import 'package:taskcaster_app/features/games/presentation/bloc/judging_event.dart';
import 'package:taskcaster_app/features/games/presentation/screens/submission_review_screen.dart';
import 'package:taskcaster_app/features/games/presentation/screens/task_scoreboard_screen.dart';

class MockGameRepository extends Mock implements GameRepository {}

class MockGameDetailBloc extends MockBloc<GameDetailEvent, GameDetailState>
    implements GameDetailBloc {}

void main() {
  late MockGameRepository mockRepo;

  setUp(() {
    mockRepo = MockGameRepository();
  });

  /// The game under test. [judged] returns the snapshot as it looks AFTER
  /// judging landed (per-task scores recorded, player totals bumped) — what
  /// the repository hands back when JudgingBloc re-reads the game.
  Game buildGame({bool judged = false}) {
    PlayerTaskStatus statusFor(String id, String url, int score) {
      return PlayerTaskStatus(
        playerId: id,
        state: judged ? TaskPlayerState.judged : TaskPlayerState.submitted,
        submissionUrl: url,
        submittedAt: DateTime.now(),
        score: judged ? score : null,
        scoredAt: judged ? DateTime.now() : null,
      );
    }

    return Game(
      id: 'game1',
      gameName: 'Judge Night',
      creatorId: 'judge1',
      judgeId: 'judge1',
      status: GameStatus.inProgress,
      inviteCode: 'JUDGE1',
      createdAt: DateTime.now(),
      players: [
        Player(
            userId: 'p1', displayName: 'Alice', totalScore: judged ? 7 : 0),
        Player(userId: 'p2', displayName: 'Bob', totalScore: judged ? 10 : 0),
      ],
      tasks: [
        Task(
          id: 'task-1',
          title: 'Deliver a passionate sales pitch for air',
          description: 'Sixty seconds to sell AIR to the camera.',
          taskType: TaskType.video,
          category: 'Word & Wit',
          submissions: const [],
          playerStatuses: {
            'p1': statusFor('p1', 'https://youtu.be/alice', 7),
            'p2': statusFor('p2', 'https://youtu.be/bob', 10),
          },
        ),
      ],
      // Keep the scoreboard's 10-second auto-advance countdown out of these
      // tests — it would pop the reveal back off the stack mid-assertion.
      settings: const GameSettings(autoAdvanceTasks: false),
    );
  }

  Future<void> pumpReviewScreen(WidgetTester tester) async {
    when(() => mockRepo.getGameStream('game1'))
        .thenAnswer((_) => Stream.value(buildGame()));

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider(
          create: (_) => JudgingBloc(gameRepository: mockRepo)
            ..add(const LoadSubmissions(gameId: 'game1', taskIndex: 0)),
          child: const SubmissionReviewView(gameId: 'game1', taskIndex: 0),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('SubmissionReviewView', () {
    testWidgets('shows one submission at a time with a 0-10 score selector',
        (tester) async {
      await pumpReviewScreen(tester);

      // One submission at a time, with the player front and center.
      expect(find.text('Submission 1 of 2'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsNothing);
      expect(find.text('Open Video'), findsOneWidget);

      // Judged progress starts at zero.
      expect(find.text('0 of 2 judged'), findsOneWidget);

      // The full 0-10 selector is present.
      for (var score = JudgingBloc.minScore;
          score <= JudgingBloc.maxScore;
          score++) {
        expect(find.text('$score'), findsWidgets,
            reason: 'Missing score chip for $score');
      }
    });

    testWidgets('scoring a submission advances the judged progress',
        (tester) async {
      await pumpReviewScreen(tester);

      expect(find.text('0 of 2 judged'), findsOneWidget);

      // Award Alice a solid 7. The score chips sit below the fold on the
      // default 800×600 test viewport, so scroll them into view first.
      await tester.ensureVisible(find.text('7').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('7').first);
      await tester.pump();

      expect(find.text('1 of 2 judged'), findsOneWidget);
      expect(find.text('Scored: 7 pts'), findsOneWidget);

      // Let the auto-advance timer fire and carry us to Bob.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text('Bob'), findsOneWidget);
    });

    testWidgets('scoring everyone triggers the All judged moment',
        (tester) async {
      await pumpReviewScreen(tester);

      // Score Alice (chips are below the fold — scroll into view first).
      await tester.ensureVisible(find.text('7').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('7').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      // Score Bob (we are now on Bob's page; scroll his chips into view).
      await tester.ensureVisible(find.text('10').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('10').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(find.text('All judged! 🎉'), findsOneWidget);
      expect(find.text('Reveal the scores'), findsOneWidget);
    });
  });

  // Regression cover for the "Finish silently drops the judge back on the
  // judging list" bug: the reveal used to be pushed only when GameDetailBloc
  // happened to be in GameDetailLoaded at the exact instant JudgingCompleted
  // landed, and to pop TWICE otherwise. GameDetailBloc mirrors a Firestore
  // stream that re-emits on its own schedule, so that instant is a race.
  group('SubmissionReviewView finishing judging', () {
    late MockGameDetailBloc gameDetailBloc;
    late JudgingBloc judgingBloc;
    final navigatorKey = GlobalKey<NavigatorState>();

    /// Stands the screen up three routes deep (root -> judging list ->
    /// review) so "popped once" and "popped twice" are distinguishable.
    Future<void> pumpJudgingStack(
      WidgetTester tester, {
      required GameDetailState gameDetailState,
    }) async {
      gameDetailBloc = MockGameDetailBloc();
      whenListen(
        gameDetailBloc,
        const Stream<GameDetailState>.empty(),
        initialState: gameDetailState,
      );
      judgingBloc = JudgingBloc(gameRepository: mockRepo)
        ..add(const LoadSubmissions(gameId: 'game1', taskIndex: 0));
      addTearDown(judgingBloc.close);

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: Center(child: Text('ROOT'))),
        ),
      );
      unawaited(navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              const Scaffold(body: Center(child: Text('JUDGE SUBMISSIONS'))),
        ),
      ));
      await tester.pumpAndSettle();
      unawaited(navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => MultiBlocProvider(
            providers: [
              BlocProvider<GameDetailBloc>.value(value: gameDetailBloc),
              BlocProvider<JudgingBloc>.value(value: judgingBloc),
            ],
            child: const SubmissionReviewView(gameId: 'game1', taskIndex: 0),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    /// Scores both players and finishes, then pumps in bounded steps (never
    /// pumpAndSettle — the reveal screen animates indefinitely).
    Future<void> scoreAndFinish(WidgetTester tester,
        {int pumps = 30}) async {
      judgingBloc
        ..add(const ScoreSubmission(playerId: 'p1', score: 7))
        ..add(const ScoreSubmission(playerId: 'p2', score: 10));
      await tester.pump();
      judgingBloc.add(const FinishJudging());
      // Long enough for the reveal's staggered timers to all fire, so no
      // pending timer outlives the test.
      for (var i = 0; i < pumps; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    /// Repository stubs for a judging round that succeeds: the game reads
    /// back un-judged until the scores are written, judged afterwards.
    void stubSuccessfulJudging({bool reReadFails = false}) {
      var judged = false;
      when(() => mockRepo.getGameStream('game1')).thenAnswer((_) {
        if (judged && reReadFails) {
          return Stream<Game?>.error(Exception('snapshot unavailable'));
        }
        return Stream<Game?>.value(buildGame(judged: judged));
      });
      when(() => mockRepo.judgeSubmission(any(), any(), any(), any()))
          .thenAnswer((_) async => judged = true);
    }

    testWidgets(
        'reveals the scoreboard even when GameDetailBloc is not loaded yet',
        (tester) async {
      stubSuccessfulJudging();
      // The exact race: the shared bloc is mid-reload when judging finishes.
      await pumpJudgingStack(tester, gameDetailState: GameDetailLoading());

      await scoreAndFinish(tester);

      expect(find.byType(TaskScoreboardScreen), findsOneWidget);
      expect(find.text('JUDGE SUBMISSIONS'), findsNothing);
    });

    testWidgets('reveals the scoreboard when GameDetailBloc errored out',
        (tester) async {
      stubSuccessfulJudging();
      await pumpJudgingStack(
        tester,
        gameDetailState: const GameDetailError(message: 'stream hiccup'),
      );

      await scoreAndFinish(tester);

      expect(find.byType(TaskScoreboardScreen), findsOneWidget);
      expect(find.text('JUDGE SUBMISSIONS'), findsNothing);
    });

    testWidgets(
        'reveals real deltas from the post-judging snapshot, not a stale one',
        (tester) async {
      stubSuccessfulJudging();
      // GameDetailBloc is Loaded but still holding the PRE-judging game —
      // reading the scoreboard off it would reveal +0 for everyone.
      await pumpJudgingStack(
        tester,
        gameDetailState: GameDetailLoaded(game: buildGame()),
      );

      await scoreAndFinish(tester);

      final scoreboard =
          tester.widget<TaskScoreboardScreen>(find.byType(TaskScoreboardScreen));
      expect(scoreboard.taskScores, {'p1': 7, 'p2': 10});
      expect(scoreboard.previousTotals, {'p1': 0, 'p2': 0});
      expect(scoreboard.game.players.first.totalScore, 7);
    });

    testWidgets(
        'falls back to the last loaded game when the post-write re-read fails',
        (tester) async {
      stubSuccessfulJudging(reReadFails: true);
      await pumpJudgingStack(
        tester,
        gameDetailState: GameDetailLoaded(game: buildGame()),
      );

      await scoreAndFinish(tester);

      final scoreboard =
          tester.widget<TaskScoreboardScreen>(find.byType(TaskScoreboardScreen));
      // The snapshot predates the write, so the scores just awarded carry the
      // reveal and the totals on it are still the pre-task ones.
      expect(scoreboard.taskScores, {'p1': 7, 'p2': 10});
      expect(scoreboard.previousTotals, {'p1': 0, 'p2': 0});
    });

    testWidgets(
        'with no game data anywhere, explains itself and pops exactly once',
        (tester) async {
      stubSuccessfulJudging(reReadFails: true);
      await pumpJudgingStack(tester, gameDetailState: GameDetailLoading());

      // Short drain: the SnackBar is only on screen for its own duration.
      await scoreAndFinish(tester, pumps: 5);

      expect(find.byType(TaskScoreboardScreen), findsNothing);
      expect(
        find.text(
            "Scores saved — but the scoreboard couldn't be loaded right now."),
        findsOneWidget,
      );
      // One pop, not two: back on the judging list, not past it.
      expect(find.text('JUDGE SUBMISSIONS'), findsOneWidget);
      expect(find.text('ROOT'), findsNothing);
    });

    testWidgets(
        'the full tap path (score -> reveal -> Finish) reaches the scoreboard',
        (tester) async {
      stubSuccessfulJudging();
      await pumpJudgingStack(tester, gameDetailState: GameDetailLoading());

      await tester.ensureVisible(find.text('7').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('7').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('10').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('10').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Reveal the scores'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Finish'));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.byType(TaskScoreboardScreen), findsOneWidget);
      expect(find.text('JUDGE SUBMISSIONS'), findsNothing);
    });
  });
}
