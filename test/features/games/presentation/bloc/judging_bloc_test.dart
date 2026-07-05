import 'package:bloc_test/bloc_test.dart';
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
import 'package:taskcaster_app/features/games/presentation/bloc/judging_state.dart';

class MockGameRepository extends Mock implements GameRepository {}

void main() {
  group('JudgingBloc Tests', () {
    late JudgingBloc judgingBloc;
    late MockGameRepository mockGameRepository;
    late Game testGame;

    setUp(() {
      mockGameRepository = MockGameRepository();
      judgingBloc = JudgingBloc(gameRepository: mockGameRepository);

      testGame = Game(
        id: 'game1',
        gameName: 'Test Game',
        creatorId: 'user1',
        judgeId: 'user1',
        status: GameStatus.inProgress,
        inviteCode: 'TEST01',
        createdAt: DateTime.now(),
        players: [
          const Player(userId: 'user1', displayName: 'Alice', totalScore: 0),
          const Player(userId: 'user2', displayName: 'Bob', totalScore: 0),
          const Player(userId: 'user3', displayName: 'Charlie', totalScore: 0),
        ],
        tasks: [
          Task(
            id: 'task1',
            title: 'Test Task',
            description: 'Do something funny',
            taskType: TaskType.video,
            submissions: [],
            playerStatuses: {
              'user1': PlayerTaskStatus(
                playerId: 'user1',
                state: TaskPlayerState.submitted,
                submissionUrl: 'https://youtube.com/watch?v=123',
              ),
              'user2': PlayerTaskStatus(
                playerId: 'user2',
                state: TaskPlayerState.submitted,
                submissionUrl: 'https://youtube.com/watch?v=456',
              ),
              'user3': PlayerTaskStatus(
                playerId: 'user3',
                state: TaskPlayerState.in_progress,
              ),
            },
          ),
        ],
        settings: const GameSettings(),
      );
    });

    tearDown(() {
      judgingBloc.close();
    });

    test('initial state should be JudgingInitial', () {
      expect(judgingBloc.state, equals(JudgingInitial()));
    });

    group('LoadSubmissions', () {
      blocTest<JudgingBloc, JudgingState>(
        'emits [JudgingLoading, JudgingLoaded] when submissions are loaded successfully',
        build: () {
          when(() => mockGameRepository.getGameStream('game1'))
              .thenAnswer((_) => Stream.value(testGame));
          return judgingBloc;
        },
        act: (bloc) => bloc.add(const LoadSubmissions(
          gameId: 'game1',
          taskIndex: 0,
        )),
        expect: () => [
          JudgingLoading(),
          isA<JudgingLoaded>()
              .having((s) => s.gameId, 'gameId', 'game1')
              .having((s) => s.taskIndex, 'taskIndex', 0)
              .having((s) => s.taskTitle, 'taskTitle', 'Test Task')
              .having((s) => s.submissions.length, 'submissions length', 3)
              .having((s) => s.submittedCount, 'submittedCount', 2)
              .having((s) => s.allSubmitted, 'allSubmitted', false),
        ],
      );

      blocTest<JudgingBloc, JudgingState>(
        'emits [JudgingLoading, JudgingError] when game is not found',
        build: () {
          when(() => mockGameRepository.getGameStream('game1'))
              .thenAnswer((_) => Stream.value(null));
          return judgingBloc;
        },
        act: (bloc) => bloc.add(const LoadSubmissions(
          gameId: 'game1',
          taskIndex: 0,
        )),
        expect: () => [
          JudgingLoading(),
          const JudgingError(message: 'Game not found'),
        ],
      );

      blocTest<JudgingBloc, JudgingState>(
        'emits [JudgingLoading, JudgingError] when task index is invalid',
        build: () {
          when(() => mockGameRepository.getGameStream('game1'))
              .thenAnswer((_) => Stream.value(testGame));
          return judgingBloc;
        },
        act: (bloc) => bloc.add(const LoadSubmissions(
          gameId: 'game1',
          taskIndex: 5,
        )),
        expect: () => [
          JudgingLoading(),
          const JudgingError(message: 'Task not found'),
        ],
      );
    });

    group('ScoreSubmission', () {
      blocTest<JudgingBloc, JudgingState>(
        'updates score and moves to next submission',
        build: () {
          when(() => mockGameRepository.getGameStream('game1'))
              .thenAnswer((_) => Stream.value(testGame));
          return judgingBloc;
        },
        act: (bloc) {
          bloc.add(const LoadSubmissions(gameId: 'game1', taskIndex: 0));
          return Future.delayed(const Duration(milliseconds: 100), () {
            bloc.add(const ScoreSubmission(playerId: 'user1', score: 5));
          });
        },
        skip: 2, // Skip loading states
        expect: () => [
          isA<JudgingLoaded>()
              .having((s) => s.scores['user1'], 'user1 score', 5)
              .having((s) => s.scoredCount, 'scoredCount', 1),
        ],
      );

      blocTest<JudgingBloc, JudgingState>(
        'emits error when score is out of range',
        build: () {
          when(() => mockGameRepository.getGameStream('game1'))
              .thenAnswer((_) => Stream.value(testGame));
          return judgingBloc;
        },
        seed: () => JudgingLoaded(
          gameId: 'game1',
          taskIndex: 0,
          taskTitle: 'Test Task',
          taskDescription: 'Description',
          submissions: [
            SubmissionData(
              playerId: 'user1',
              playerName: 'Alice',
              submissionUrl: 'https://youtube.com',
              status: PlayerTaskStatus(
                playerId: 'user1',
                state: TaskPlayerState.submitted,
              ),
            ),
          ],
          currentIndex: 0,
          scores: {},
        ),
        act: (bloc) => bloc.add(const ScoreSubmission(playerId: 'user1', score: 11)),
        expect: () => [
          const JudgingError(message: 'Score must be between 0 and 10'),
        ],
      );

      blocTest<JudgingBloc, JudgingState>(
        'accepts the full 0-10 range, including a brutal 0',
        build: () => judgingBloc,
        seed: () => JudgingLoaded(
          gameId: 'game1',
          taskIndex: 0,
          taskTitle: 'Test Task',
          taskDescription: 'Description',
          submissions: [
            SubmissionData(
              playerId: 'user1',
              playerName: 'Alice',
              submissionUrl: 'https://youtube.com',
              status: PlayerTaskStatus(
                playerId: 'user1',
                state: TaskPlayerState.submitted,
              ),
            ),
          ],
          currentIndex: 0,
          scores: {},
        ),
        act: (bloc) => bloc.add(const ScoreSubmission(playerId: 'user1', score: 0)),
        expect: () => [
          isA<JudgingLoaded>()
              .having((s) => s.scores['user1'], 'user1 score', 0)
              .having((s) => s.scoredCount, 'scoredCount', 1),
        ],
      );
    });

    group('SkipSubmission', () {
      blocTest<JudgingBloc, JudgingState>(
        'marks submission as skipped and moves to next',
        build: () {
          when(() => mockGameRepository.getGameStream('game1'))
              .thenAnswer((_) => Stream.value(testGame));
          return judgingBloc;
        },
        act: (bloc) {
          bloc.add(const LoadSubmissions(gameId: 'game1', taskIndex: 0));
          return Future.delayed(const Duration(milliseconds: 100), () {
            bloc.add(const SkipSubmission(playerId: 'user1'));
          });
        },
        skip: 2,
        expect: () => [
          isA<JudgingLoaded>()
              .having(
                (s) => s.submissions.firstWhere((sub) => sub.playerId == 'user1').skipped,
                'user1 skipped',
                true,
              ),
        ],
      );
    });

    group('FinishJudging', () {
      blocTest<JudgingBloc, JudgingState>(
        'submits all scores and emits JudgingCompleted',
        build: () {
          when(() => mockGameRepository.getGameStream('game1'))
              .thenAnswer((_) => Stream.value(testGame));
          when(() => mockGameRepository.judgeSubmission(any(), any(), any(), any()))
              .thenAnswer((_) async {});
          return judgingBloc;
        },
        act: (bloc) async {
          bloc.add(const LoadSubmissions(gameId: 'game1', taskIndex: 0));
          await Future.delayed(const Duration(milliseconds: 100));
          bloc.add(const ScoreSubmission(playerId: 'user1', score: 5));
          await Future.delayed(const Duration(milliseconds: 100));
          bloc.add(const ScoreSubmission(playerId: 'user2', score: 3));
          await Future.delayed(const Duration(milliseconds: 100));
          bloc.add(const FinishJudging());
        },
        expect: () => [
          JudgingLoading(),
          isA<JudgingLoaded>(),
          isA<JudgingLoaded>().having((s) => s.scoredCount, 'scoredCount', 1),
          isA<JudgingLoaded>().having((s) => s.scoredCount, 'scoredCount', 2),
          JudgingLoading(),
          const JudgingCompleted(gameId: 'game1', taskIndex: 0),
        ],
        verify: (_) {
          verify(() => mockGameRepository.judgeSubmission('game1', 0, 'user1', 5)).called(1);
          verify(() => mockGameRepository.judgeSubmission('game1', 0, 'user2', 3)).called(1);
        },
      );

      blocTest<JudgingBloc, JudgingState>(
        'allows finishing when all submissions are scored (even if zero)',
        build: () {
          when(() => mockGameRepository.judgeSubmission(any(), any(), any(), any()))
              .thenAnswer((_) async {});
          return judgingBloc;
        },
        seed: () => const JudgingLoaded(
          gameId: 'game1',
          taskIndex: 0,
          taskTitle: 'Test Task',
          taskDescription: 'Description',
          submissions: [],
          currentIndex: 0,
          scores: {},
        ),
        act: (bloc) => bloc.add(const FinishJudging()),
        expect: () => [
          JudgingLoading(),
          const JudgingCompleted(gameId: 'game1', taskIndex: 0),
        ],
      );

      blocTest<JudgingBloc, JudgingState>(
        'emits error when judgeSubmission fails',
        build: () {
          when(() => mockGameRepository.getGameStream('game1'))
              .thenAnswer((_) => Stream.value(testGame));
          when(() => mockGameRepository.judgeSubmission(any(), any(), any(), any()))
              .thenThrow(Exception('Failed to submit score'));
          return judgingBloc;
        },
        act: (bloc) async {
          bloc.add(const LoadSubmissions(gameId: 'game1', taskIndex: 0));
          await Future.delayed(const Duration(milliseconds: 100));
          bloc.add(const ScoreSubmission(playerId: 'user1', score: 5));
          await Future.delayed(const Duration(milliseconds: 100));
          bloc.add(const FinishJudging());
        },
        expect: () => [
          JudgingLoading(),
          isA<JudgingLoaded>(),
          isA<JudgingLoaded>(),
          JudgingLoading(),
          const JudgingError(
              message: "Couldn't save the scores. Please try again."),
        ],
      );
    });
  });
}