import 'package:bloc_test/bloc_test.dart';
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
import 'package:taskcaster_app/features/games/presentation/bloc/task_execution_state.dart';

class MockGameRepository extends Mock implements GameRepository {}

void main() {
  late GameRepository mockGameRepository;
  late TaskExecutionBloc taskExecutionBloc;

  setUp(() {
    mockGameRepository = MockGameRepository();
    taskExecutionBloc = TaskExecutionBloc(gameRepository: mockGameRepository);
  });

  tearDown(() {
    taskExecutionBloc.close();
  });

  setUpAll(() {
    registerFallbackValue(Game(
      id: 'test-game',
      gameName: 'Test Game',
      creatorId: 'creator123',
      judgeId: 'judge123',
      inviteCode: 'ABC123',
      status: GameStatus.inProgress,
      players: [],
      tasks: [],
      settings: const GameSettings(),
      createdAt: DateTime.now(),
    ));
  });

  group('TaskExecutionBloc', () {
    final testGame = Game(
      id: 'game123',
      gameName: 'Test Game',
      creatorId: 'creator123',
      judgeId: 'judge123',
      inviteCode: 'ABC123',
      status: GameStatus.inProgress,
      players: [
        const Player(
          userId: 'player1',
          displayName: 'Player 1',
          totalScore: 0,
        ),
        const Player(
          userId: 'player2',
          displayName: 'Player 2',
          totalScore: 0,
        ),
      ],
      tasks: [
        Task(
          id: 'task1',
          title: 'Test Task',
          description: 'Do something funny',
          taskType: TaskType.video,
          submissions: [],
          status: TaskStatus.waiting_for_submissions,
          playerStatuses: {
            'player1': const PlayerTaskStatus(
              playerId: 'player1',
              state: TaskPlayerState.not_started,
            ),
            'player2': const PlayerTaskStatus(
              playerId: 'player2',
              state: TaskPlayerState.not_started,
            ),
          },
        ),
      ],
      settings: const GameSettings(),
      createdAt: DateTime.now(),
    );

    test('initial state is TaskExecutionInitial', () {
      expect(taskExecutionBloc.state, equals(TaskExecutionInitial()));
    });

    group('LoadTask', () {
      blocTest<TaskExecutionBloc, TaskExecutionState>(
        'emits [Loading, Loaded] when LoadTask succeeds',
        build: () {
          when(() => mockGameRepository.getGameStream('game123'))
              .thenAnswer((_) => Stream.value(testGame));
          return TaskExecutionBloc(gameRepository: mockGameRepository);
        },
        act: (bloc) => bloc.add(const LoadTask(
          gameId: 'game123',
          taskIndex: 0,
          userId: 'player1',
        )),
        expect: () => [
          TaskExecutionLoading(),
          isA<TaskExecutionLoaded>()
              .having((s) => s.task.id, 'task.id', 'task1')
              .having((s) => s.taskNumber, 'taskNumber', 1)
              .having((s) => s.totalTasks, 'totalTasks', 1)
              .having((s) => s.userStatus?.playerId, 'userStatus.playerId', 'player1'),
        ],
      );

      blocTest<TaskExecutionBloc, TaskExecutionState>(
        'emits [Loading, Error] when game not found',
        build: () {
          when(() => mockGameRepository.getGameStream('game123'))
              .thenAnswer((_) => Stream.value(null));
          return TaskExecutionBloc(gameRepository: mockGameRepository);
        },
        act: (bloc) => bloc.add(const LoadTask(
          gameId: 'game123',
          taskIndex: 0,
          userId: 'player1',
        )),
        expect: () => [
          TaskExecutionLoading(),
          const TaskExecutionError(message: 'Game not found'),
        ],
      );

      blocTest<TaskExecutionBloc, TaskExecutionState>(
        'emits [Loading, Error] when task index out of bounds',
        build: () {
          when(() => mockGameRepository.getGameStream('game123'))
              .thenAnswer((_) => Stream.value(testGame));
          return TaskExecutionBloc(gameRepository: mockGameRepository);
        },
        act: (bloc) => bloc.add(const LoadTask(
          gameId: 'game123',
          taskIndex: 999,
          userId: 'player1',
        )),
        expect: () => [
          TaskExecutionLoading(),
          const TaskExecutionError(message: 'Task not found'),
        ],
      );
    });

    group('StartTask', () {
      blocTest<TaskExecutionBloc, TaskExecutionState>(
        'updates player status to in_progress',
        build: () {
          when(() => mockGameRepository.getGameStream('game123'))
              .thenAnswer((_) => Stream.value(testGame));
          when(() => mockGameRepository.updateGame(any(), any()))
              .thenAnswer((_) async => {});
          return TaskExecutionBloc(gameRepository: mockGameRepository);
        },
        seed: () => TaskExecutionLoaded(
          task: testGame.tasks[0],
          userStatus: testGame.tasks[0].getPlayerStatus('player1'),
          allPlayerStatuses: testGame.tasks[0].playerStatuses,
          taskNumber: 1,
          totalTasks: 1,
        ),
        act: (bloc) => bloc.add(const StartTask(
          gameId: 'game123',
          taskIndex: 0,
          userId: 'player1',
        )),
        verify: (_) {
          verify(() => mockGameRepository.updateGame(
                'game123',
                any(that: isA<Game>()),
              )).called(1);
        },
      );
    });

    group('SubmitTask', () {
      blocTest<TaskExecutionBloc, TaskExecutionState>(
        'updates player status to submitted and emits TaskExecutionSubmitted',
        build: () {
          when(() => mockGameRepository.getGameStream('game123'))
              .thenAnswer((_) => Stream.value(testGame));
          when(() => mockGameRepository.updateGame(any(), any()))
              .thenAnswer((_) async => {});
          return TaskExecutionBloc(gameRepository: mockGameRepository);
        },
        seed: () => TaskExecutionLoaded(
          task: testGame.tasks[0],
          userStatus: testGame.tasks[0].getPlayerStatus('player1'),
          allPlayerStatuses: testGame.tasks[0].playerStatuses,
          taskNumber: 1,
          totalTasks: 1,
        ),
        act: (bloc) => bloc.add(const SubmitTask(
          gameId: 'game123',
          taskIndex: 0,
          userId: 'player1',
          videoUrl: 'https://youtube.com/watch?v=test',
        )),
        expect: () => [
          const TaskExecutionSubmitted(
            gameId: 'game123',
            taskIndex: 0,
          ),
        ],
        verify: (_) {
          verify(() => mockGameRepository.updateGame(
                'game123',
                any(that: isA<Game>()),
              )).called(1);
        },
      );

      blocTest<TaskExecutionBloc, TaskExecutionState>(
        'updates task status to ready_to_judge when all players submitted',
        build: () {
          final gameWithOneSubmitted = testGame.copyWith(
            tasks: [
              testGame.tasks[0].copyWith(
                playerStatuses: {
                  'player1': const PlayerTaskStatus(
                    playerId: 'player1',
                    state: TaskPlayerState.submitted,
                    submittedAt: null,
                    submissionUrl: 'https://youtube.com/test1',
                  ),
                  'player2': const PlayerTaskStatus(
                    playerId: 'player2',
                    state: TaskPlayerState.not_started,
                  ),
                },
              ),
            ],
          );

          when(() => mockGameRepository.getGameStream('game123'))
              .thenAnswer((_) => Stream.value(gameWithOneSubmitted));
          when(() => mockGameRepository.updateGame(any(), any()))
              .thenAnswer((_) async => {});
          return TaskExecutionBloc(gameRepository: mockGameRepository);
        },
        seed: () => TaskExecutionLoaded(
          task: testGame.tasks[0],
          userStatus: testGame.tasks[0].getPlayerStatus('player2'),
          allPlayerStatuses: testGame.tasks[0].playerStatuses,
          taskNumber: 1,
          totalTasks: 1,
        ),
        act: (bloc) => bloc.add(const SubmitTask(
          gameId: 'game123',
          taskIndex: 0,
          userId: 'player2',
          videoUrl: 'https://youtube.com/watch?v=test2',
        )),
        expect: () => [
          const TaskExecutionSubmitted(
            gameId: 'game123',
            taskIndex: 0,
          ),
        ],
      );
    });

    group('SkipTask', () {
      blocTest<TaskExecutionBloc, TaskExecutionState>(
        'updates player status to skipped when game allows skips',
        build: () {
          final gameWithSkipsAllowed = testGame.copyWith(
            settings: const GameSettings(allowSkips: true),
          );

          when(() => mockGameRepository.getGameStream('game123'))
              .thenAnswer((_) => Stream.value(gameWithSkipsAllowed));
          when(() => mockGameRepository.updateGame(any(), any()))
              .thenAnswer((_) async => {});
          return TaskExecutionBloc(gameRepository: mockGameRepository);
        },
        seed: () => TaskExecutionLoaded(
          task: testGame.tasks[0],
          userStatus: testGame.tasks[0].getPlayerStatus('player1'),
          allPlayerStatuses: testGame.tasks[0].playerStatuses,
          taskNumber: 1,
          totalTasks: 1,
        ),
        act: (bloc) => bloc.add(const SkipTask(
          gameId: 'game123',
          taskIndex: 0,
          userId: 'player1',
        )),
        expect: () => [
          const TaskExecutionSubmitted(
            gameId: 'game123',
            taskIndex: 0,
          ),
        ],
        verify: (_) {
          verify(() => mockGameRepository.updateGame(
                'game123',
                any(that: isA<Game>()),
              )).called(1);
        },
      );

      blocTest<TaskExecutionBloc, TaskExecutionState>(
        'emits error when game does not allow skips',
        build: () {
          final gameWithSkipsDisabled = testGame.copyWith(
            settings: const GameSettings(allowSkips: false),
          );

          when(() => mockGameRepository.getGameStream('game123'))
              .thenAnswer((_) => Stream.value(gameWithSkipsDisabled));
          return TaskExecutionBloc(gameRepository: mockGameRepository);
        },
        seed: () => TaskExecutionLoaded(
          task: testGame.tasks[0],
          userStatus: testGame.tasks[0].getPlayerStatus('player1'),
          allPlayerStatuses: testGame.tasks[0].playerStatuses,
          taskNumber: 1,
          totalTasks: 1,
        ),
        act: (bloc) => bloc.add(const SkipTask(
          gameId: 'game123',
          taskIndex: 0,
          userId: 'player1',
        )),
        expect: () => [
          const TaskExecutionError(
              message: 'Skipping tasks is not allowed in this game'),
        ],
      );
    });
  });
}