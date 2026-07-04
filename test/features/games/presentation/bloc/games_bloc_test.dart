import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:taskcaster_app/core/models/game.dart';
import 'package:taskcaster_app/core/models/game_settings.dart';
import 'package:taskcaster_app/core/models/player.dart';
import 'package:taskcaster_app/core/models/user.dart';
import 'package:taskcaster_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:taskcaster_app/features/games/domain/repositories/game_repository.dart';
import 'package:taskcaster_app/features/games/presentation/bloc/games_bloc.dart';

class MockGameRepository extends Mock implements GameRepository {}
class MockAuthRepository extends Mock implements AuthRepository {}

class FakeGame extends Fake implements Game {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeGame());
  });

  group('GamesBloc Tests', () {
    late GamesBloc gamesBloc;
    late MockGameRepository mockGameRepository;
    late MockAuthRepository mockAuthRepository;
    late List<Game> testGames;

    setUp(() {
      mockGameRepository = MockGameRepository();
      mockAuthRepository = MockAuthRepository();
      gamesBloc = GamesBloc(
        gameRepository: mockGameRepository,
        authRepository: mockAuthRepository,
      );
      
      testGames = [
        Game(
          id: 'game1',
          gameName: 'Test Game 1',
          creatorId: 'user1',
          judgeId: 'user1',
          status: GameStatus.lobby,
          inviteCode: 'TEST01',
          createdAt: DateTime.now(),
          players: [
            const Player(userId: 'user1', displayName: 'Alice', totalScore: 0),
          ],
          tasks: [],
          settings: const GameSettings(),
        ),
        Game(
          id: 'game2',
          gameName: 'Test Game 2',
          creatorId: 'user2',
          judgeId: 'user2',
          status: GameStatus.inProgress,
          inviteCode: 'TEST02',
          createdAt: DateTime.now(),
          players: [
            const Player(userId: 'user2', displayName: 'Bob', totalScore: 15),
          ],
          tasks: [],
          settings: const GameSettings(),
        ),
      ];
    });

    tearDown(() {
      gamesBloc.close();
    });

    test('initial state should be GamesInitial', () {
      expect(gamesBloc.state, equals(GamesInitial()));
    });

    group('LoadGames', () {
      blocTest<GamesBloc, GamesState>(
        'emits [GamesLoading, GamesLoaded] when games are loaded successfully',
        build: () {
          when(() => mockGameRepository.getGamesStream())
              .thenAnswer((_) => Stream.value(testGames));
          return gamesBloc;
        },
        act: (bloc) => bloc.add(LoadGames()),
        expect: () => [
          GamesLoading(),
          GamesLoaded(games: testGames),
        ],
      );

      blocTest<GamesBloc, GamesState>(
        'emits [GamesLoading, GamesError] when loading games fails',
        build: () {
          when(() => mockGameRepository.getGamesStream())
              .thenAnswer((_) => Stream.error(Exception('Failed to load games')));
          return gamesBloc;
        },
        act: (bloc) => bloc.add(LoadGames()),
        expect: () => [
          GamesLoading(),
          const GamesError(
              message: 'Could not load your games. Please try again.'),
        ],
      );

      blocTest<GamesBloc, GamesState>(
        'emits [GamesLoading, GamesLoaded] with empty list when no games exist',
        build: () {
          when(() => mockGameRepository.getGamesStream())
              .thenAnswer((_) => Stream.value([]));
          return gamesBloc;
        },
        act: (bloc) => bloc.add(LoadGames()),
        expect: () => [
          GamesLoading(),
          const GamesLoaded(games: []),
        ],
      );
    });

    group('CreateGame', () {
      blocTest<GamesBloc, GamesState>(
        'emits [GamesLoading] and calls LoadGames when game is created successfully',
        build: () {
          when(() => mockGameRepository.createGame(any(), any(), any()))
              .thenAnswer((_) async => 'new_game_id');
          when(() => mockGameRepository.getGamesStream())
              .thenAnswer((_) => Stream.value(testGames));
          return gamesBloc;
        },
        act: (bloc) => bloc.add(const CreateGame(
          gameName: 'New Game',
          creatorId: 'user1',
          judgeId: 'user1',
        )),
        expect: () => [
          GamesLoading(),
          GamesLoaded(games: testGames),
        ],
      );

      blocTest<GamesBloc, GamesState>(
        'emits [GamesLoading, GamesError] when game creation fails',
        build: () {
          when(() => mockGameRepository.createGame(any(), any(), any()))
              .thenThrow(Exception('Failed to create game'));
          return gamesBloc;
        },
        act: (bloc) => bloc.add(const CreateGame(
          gameName: 'New Game',
          creatorId: 'user1',
          judgeId: 'user1',
        )),
        expect: () => [
          GamesLoading(),
          const GamesError(
              message: 'Could not create the game. Please try again.'),
        ],
      );
    });

    group('JoinGame', () {
      blocTest<GamesBloc, GamesState>(
        'calls LoadGames when game is joined successfully',
        build: () {
          when(() => mockGameRepository.joinGame(any(), any(), any()))
              .thenAnswer((_) async => 'game_id');
          when(() => mockGameRepository.getGamesStream())
              .thenAnswer((_) => Stream.value(testGames));
          return gamesBloc;
        },
        act: (bloc) => bloc.add(const JoinGame(
          inviteCode: 'TEST01',
          userId: 'user2',
          displayName: 'Charlie',
        )),
        expect: () => [
          GamesLoading(),
          GamesLoaded(games: testGames),
        ],
      );

      blocTest<GamesBloc, GamesState>(
        'emits GamesError when joining game fails',
        build: () {
          when(() => mockGameRepository.joinGame(any(), any(), any()))
              .thenThrow(Exception('Game not found'));
          return gamesBloc;
        },
        act: (bloc) => bloc.add(const JoinGame(
          inviteCode: 'INVALID',
          userId: 'user2',
          displayName: 'Charlie',
        )),
        expect: () => [
          const GamesError(
              message:
                  'Could not join the game. Double-check the code. Please try again.'),
        ],
      );
    });

    group('DeleteGame', () {
      blocTest<GamesBloc, GamesState>(
        'calls LoadGames when game is deleted successfully',
        build: () {
          when(() => mockGameRepository.deleteGame(any()))
              .thenAnswer((_) async {});
          when(() => mockGameRepository.getGamesStream())
              .thenAnswer((_) => Stream.value([]));
          return gamesBloc;
        },
        act: (bloc) => bloc.add(const DeleteGame(gameId: 'game1')),
        expect: () => [
          GamesLoading(),
          const GamesLoaded(games: []),
        ],
      );

      blocTest<GamesBloc, GamesState>(
        'emits GamesError when deleting game fails',
        build: () {
          when(() => mockGameRepository.deleteGame(any()))
              .thenThrow(Exception('Failed to delete game'));
          return gamesBloc;
        },
        act: (bloc) => bloc.add(const DeleteGame(gameId: 'game1')),
        expect: () => [
          const GamesError(
              message: 'Could not delete the game. Please try again.'),
        ],
      );
    });

    group('Multiple Events', () {
      blocTest<GamesBloc, GamesState>(
        'handles multiple events correctly',
        build: () {
          when(() => mockGameRepository.createGame(any(), any(), any()))
              .thenAnswer((_) async => 'new_game_id');
          when(() => mockGameRepository.getGamesStream())
              .thenAnswer((_) => Stream.value(testGames));
          return gamesBloc;
        },
        act: (bloc) {
          bloc.add(LoadGames());
          bloc.add(const CreateGame(
            gameName: 'New Game',
            creatorId: 'user1',
            judgeId: 'user1',
          ));
        },
        expect: () => [
          GamesLoading(),
          GamesLoaded(games: testGames),
          GamesLoading(),
          GamesLoaded(games: testGames),
        ],
      );
    });

    group('QuickPlayGame', () {
      final testUser = User(
        id: 'quick_user_1',
        displayName: 'Quick Player',
        email: 'quick@test.com',
        createdAt: DateTime(2025, 1, 1),
      );

      blocTest<GamesBloc, GamesState>(
        'emits [GamesLoading, QuickPlaySuccess] when quick play succeeds',
        build: () {
          when(() => mockAuthRepository.getCurrentUser())
              .thenAnswer((_) async => testUser);
          when(() => mockGameRepository.createGame(any(), any(), any()))
              .thenAnswer((_) async => 'quick_game_123');
          when(() => mockGameRepository.updateGame(any(), any()))
              .thenAnswer((_) async {});
          return gamesBloc;
        },
        act: (bloc) => bloc.add(const QuickPlayGame()),
        expect: () => [
          GamesLoading(),
          const QuickPlaySuccess(gameId: 'quick_game_123'),
        ],
      );

      blocTest<GamesBloc, GamesState>(
        'creates game with correct properties',
        build: () {
          when(() => mockAuthRepository.getCurrentUser())
              .thenAnswer((_) async => testUser);
          when(() => mockGameRepository.createGame(any(), any(), any()))
              .thenAnswer((_) async => 'quick_game_123');
          when(() => mockGameRepository.updateGame(any(), any()))
              .thenAnswer((_) async {});
          return gamesBloc;
        },
        act: (bloc) => bloc.add(const QuickPlayGame()),
        verify: (_) {
          // Verify createGame was called with user as both creator and judge
          verify(() => mockGameRepository.createGame(
            any(), // Game name (randomly generated)
            testUser.id,
            testUser.id, // Same user is judge
          )).called(1);

          // Verify updateGame was called to add tasks
          verify(() => mockGameRepository.updateGame(
            'quick_game_123',
            any(),
          )).called(1);
        },
      );

      blocTest<GamesBloc, GamesState>(
        'emits [GamesLoading, GamesError] when user is not authenticated',
        build: () {
          when(() => mockAuthRepository.getCurrentUser())
              .thenAnswer((_) async => null);
          return gamesBloc;
        },
        act: (bloc) => bloc.add(const QuickPlayGame()),
        expect: () => [
          GamesLoading(),
          const GamesError(
              message: 'Could not start a quick game. Please try again.'),
        ],
      );

      blocTest<GamesBloc, GamesState>(
        'emits [GamesLoading, GamesError] when game creation fails',
        build: () {
          when(() => mockAuthRepository.getCurrentUser())
              .thenAnswer((_) async => testUser);
          when(() => mockGameRepository.createGame(any(), any(), any()))
              .thenThrow(Exception('Firebase error'));
          return gamesBloc;
        },
        act: (bloc) => bloc.add(const QuickPlayGame()),
        expect: () => [
          GamesLoading(),
          const GamesError(
              message: 'Could not start a quick game. Please try again.'),
        ],
      );

      blocTest<GamesBloc, GamesState>(
        'emits [GamesLoading, GamesError] when game update fails',
        build: () {
          when(() => mockAuthRepository.getCurrentUser())
              .thenAnswer((_) async => testUser);
          when(() => mockGameRepository.createGame(any(), any(), any()))
              .thenAnswer((_) async => 'quick_game_123');
          when(() => mockGameRepository.updateGame(any(), any()))
              .thenThrow(Exception('Update failed'));
          return gamesBloc;
        },
        act: (bloc) => bloc.add(const QuickPlayGame()),
        expect: () => [
          GamesLoading(),
          const GamesError(
              message: 'Could not start a quick game. Please try again.'),
        ],
      );
    });
  });
}