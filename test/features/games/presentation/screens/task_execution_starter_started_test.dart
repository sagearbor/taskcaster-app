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
import 'package:taskcaster_app/features/games/presentation/bloc/task_execution_bloc.dart';
import 'package:taskcaster_app/features/games/presentation/bloc/task_execution_event.dart';
import 'package:taskcaster_app/features/games/presentation/screens/task_execution_screen.dart';

class MockGameRepository extends Mock implements GameRepository {}

class FakeGame extends Fake implements Game {}

/// Regression: once a starter (photo/text) task has been started, the task
/// title and description must stay on screen next to the countdown. The first
/// deployed build showed only the timer, the twist and "Snap it" — a player
/// mid-attempt could no longer read what they were supposed to do.
void main() {
  late MockGameRepository mockRepo;

  setUpAll(() => registerFallbackValue(FakeGame()));
  setUp(() => mockRepo = MockGameRepository());

  Game startedStarterGame() => Game(
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
        tasks: [
          Task(
            id: 'starter-01',
            title: 'A vegetable that has just received terrible news',
            description: 'Find a vegetable. Photograph it at the exact moment '
                'it receives devastating news.',
            taskType: TaskType.video,
            submissionType: SubmissionType.photo,
            twist: 'The news must be implied by the photo alone.',
            rubric: 'Emotional truth of the vegetable.',
            durationSeconds: 90,
            submissions: const [],
            playerStatuses: {
              'user1': PlayerTaskStatus(
                playerId: 'user1',
                state: TaskPlayerState.in_progress,
                startedAt: DateTime.now(),
              ),
            },
          ),
        ],
        settings: const GameSettings(crowdJudged: true, shareToArena: true),
      );

  testWidgets('started starter task keeps title + description beside the clock',
      (tester) async {
    when(() => mockRepo.getGameStream('game1'))
        .thenAnswer((_) => Stream.value(startedStarterGame()));

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider(
          create: (_) => TaskExecutionBloc(gameRepository: mockRepo)
            ..add(const LoadTask(
                gameId: 'game1', taskIndex: 0, userId: 'user1')),
          child: const TaskExecutionView(
              gameId: 'game1', taskIndex: 0, userId: 'user1'),
        ),
      ),
    );
    // The countdown ticks every second, so pump a fixed span rather than
    // pumpAndSettle (which would never settle).
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byKey(const Key('starter-task-title')), findsOneWidget);
    expect(find.text('A vegetable that has just received terrible news'),
        findsOneWidget);
    expect(find.textContaining('Find a vegetable.'), findsOneWidget);
    expect(find.textContaining('Snap it'), findsOneWidget);
    expect(find.text('The news must be implied by the photo alone.'),
        findsOneWidget);
  });
}
