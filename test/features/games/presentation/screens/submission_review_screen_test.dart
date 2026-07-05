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
import 'package:taskcaster_app/features/games/presentation/bloc/judging_bloc.dart';
import 'package:taskcaster_app/features/games/presentation/bloc/judging_event.dart';
import 'package:taskcaster_app/features/games/presentation/screens/submission_review_screen.dart';

class MockGameRepository extends Mock implements GameRepository {}

void main() {
  late MockGameRepository mockRepo;

  setUp(() {
    mockRepo = MockGameRepository();
  });

  Game buildGame() {
    return Game(
      id: 'game1',
      gameName: 'Judge Night',
      creatorId: 'judge1',
      judgeId: 'judge1',
      status: GameStatus.inProgress,
      inviteCode: 'JUDGE1',
      createdAt: DateTime.now(),
      players: [
        const Player(userId: 'p1', displayName: 'Alice', totalScore: 0),
        const Player(userId: 'p2', displayName: 'Bob', totalScore: 0),
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
            'p1': PlayerTaskStatus(
              playerId: 'p1',
              state: TaskPlayerState.submitted,
              submissionUrl: 'https://youtu.be/alice',
              submittedAt: DateTime.now(),
            ),
            'p2': PlayerTaskStatus(
              playerId: 'p2',
              state: TaskPlayerState.submitted,
              submissionUrl: 'https://youtu.be/bob',
              submittedAt: DateTime.now(),
            ),
          },
        ),
      ],
      settings: const GameSettings(),
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
}
