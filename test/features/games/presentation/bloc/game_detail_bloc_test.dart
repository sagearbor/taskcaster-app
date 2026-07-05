import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:taskcaster_app/core/models/game.dart';
import 'package:taskcaster_app/core/models/game_settings.dart';
import 'package:taskcaster_app/core/models/player.dart';
import 'package:taskcaster_app/core/models/task.dart';
import 'package:taskcaster_app/features/games/domain/repositories/game_repository.dart';
import 'package:taskcaster_app/features/games/presentation/bloc/game_detail_bloc.dart';

class MockGameRepository extends Mock implements GameRepository {}

void main() {
  late GameRepository mockGameRepository;
  late GameDetailBloc gameDetailBloc;

  setUp(() {
    mockGameRepository = MockGameRepository();
    gameDetailBloc = GameDetailBloc(gameRepository: mockGameRepository);
  });

  tearDown(() {
    gameDetailBloc.close();
  });

  group('GameDetailBloc - StartGame', () {
    final testGame = Game(
      id: 'game123',
      gameName: 'Test Game',
      creatorId: 'creator123',
      judgeId: 'judge123',
      inviteCode: 'ABC123',
      status: GameStatus.lobby,
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
        const Task(
          id: 'task1',
          title: 'Test Task 1',
          description: 'Do something funny',
          taskType: TaskType.video,
          submissions: [],
        ),
        const Task(
          id: 'task2',
          title: 'Test Task 2',
          description: 'Do something silly',
          taskType: TaskType.video,
          submissions: [],
        ),
      ],
      settings: const GameSettings(),
      createdAt: DateTime.now(),
    );

    blocTest<GameDetailBloc, GameDetailState>(
      'starts game successfully with valid conditions',
      build: () {
        when(() => mockGameRepository.startGame(any()))
            .thenAnswer((_) async => {});
        return GameDetailBloc(gameRepository: mockGameRepository);
      },
      act: (bloc) => bloc.add(const StartGame(gameId: 'game123')),
      verify: (_) {
        verify(() => mockGameRepository.startGame('game123')).called(1);
      },
    );

    blocTest<GameDetailBloc, GameDetailState>(
      'emits error when startGame fails',
      build: () {
        when(() => mockGameRepository.startGame(any()))
            .thenThrow(Exception('Failed to start game'));
        return GameDetailBloc(gameRepository: mockGameRepository);
      },
      act: (bloc) => bloc.add(const StartGame(gameId: 'game123')),
      expect: () => [
        const GameDetailError(
            message: "Couldn't start the game. Please try again."),
      ],
    );
  });

  group('GameDetailBloc - LoadGameDetail', () {
    final testGame = Game(
      id: 'game123',
      gameName: 'Test Game',
      creatorId: 'creator123',
      judgeId: 'judge123',
      inviteCode: 'ABC123',
      status: GameStatus.lobby,
      players: [
        const Player(
          userId: 'player1',
          displayName: 'Player 1',
          totalScore: 0,
        ),
      ],
      tasks: [],
      settings: const GameSettings(),
      createdAt: DateTime.now(),
    );

    blocTest<GameDetailBloc, GameDetailState>(
      'emits [Loading, Loaded] when game is found',
      build: () {
        when(() => mockGameRepository.getGameStream('game123'))
            .thenAnswer((_) => Stream.value(testGame));
        return GameDetailBloc(gameRepository: mockGameRepository);
      },
      act: (bloc) => bloc.add(const LoadGameDetail(gameId: 'game123')),
      expect: () => [
        GameDetailLoading(),
        GameDetailLoaded(game: testGame),
      ],
    );

    blocTest<GameDetailBloc, GameDetailState>(
      'emits [Loading, Error] when game is not found',
      build: () {
        when(() => mockGameRepository.getGameStream('game123'))
            .thenAnswer((_) => Stream.value(null));
        return GameDetailBloc(gameRepository: mockGameRepository);
      },
      act: (bloc) => bloc.add(const LoadGameDetail(gameId: 'game123')),
      expect: () => [
        GameDetailLoading(),
        const GameDetailError(message: 'Game not found'),
      ],
    );

    blocTest<GameDetailBloc, GameDetailState>(
      'emits [Loading, Error] when stream errors',
      build: () {
        when(() => mockGameRepository.getGameStream('game123'))
            .thenAnswer((_) => Stream.error('Network error'));
        return GameDetailBloc(gameRepository: mockGameRepository);
      },
      act: (bloc) => bloc.add(const LoadGameDetail(gameId: 'game123')),
      expect: () => [
        GameDetailLoading(),
        // Stream errors are mapped to friendly copy; "Network error" is
        // detected as a connectivity problem.
        const GameDetailError(
            message: 'No connection — check your internet and try again.'),
      ],
    );
  });
}