import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:taskcaster_app/core/models/game.dart';
import 'package:taskcaster_app/core/models/game_settings.dart';
import 'package:taskcaster_app/core/models/player.dart';
import 'package:taskcaster_app/core/models/player_task_status.dart';
import 'package:taskcaster_app/core/models/user.dart';
import 'package:taskcaster_app/features/arena/data/datasources/mock_feed_data_source.dart';
import 'package:taskcaster_app/features/arena/data/repositories/feed_repository_impl.dart';
import 'package:taskcaster_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:taskcaster_app/features/games/domain/repositories/game_repository.dart';
import 'package:taskcaster_app/features/games/presentation/bloc/games_bloc.dart';
import 'package:taskcaster_app/features/tasks/data/datasources/starter_pack_data.dart';

class MockGameRepository extends Mock implements GameRepository {}

class MockAuthRepository extends Mock implements AuthRepository {}

class FakeUser extends Fake implements User {}

final testUser = User(
  id: 'user-1',
  displayName: 'Alice',
  createdAt: DateTime.parse('2026-09-01T10:00:00.000Z'),
);

Game starterGame({
  required List<TaskPlayerState> states,
  String creatorId = 'user-1',
  String? gameKind = Game.kindStarter,
}) {
  final packTasks = StarterPackData.tasks();
  return Game(
    id: 'starter-game',
    gameName: StarterPackData.gameName,
    creatorId: creatorId,
    judgeId: creatorId,
    status: GameStatus.inProgress,
    inviteCode: 'ABC123',
    createdAt: DateTime.parse('2026-09-10T10:00:00.000Z'),
    players: [
      Player(userId: creatorId, displayName: 'Alice', totalScore: 0),
    ],
    tasks: [
      for (var i = 0; i < states.length; i++)
        packTasks[i].copyWith(playerStatuses: {
          creatorId: PlayerTaskStatus(playerId: creatorId, state: states[i]),
        }),
    ],
    settings: const GameSettings(crowdJudged: true, shareToArena: true),
    gameKind: gameKind,
  );
}

Game ordinaryGame() => Game(
      id: 'other-game',
      gameName: 'Epic Journey',
      creatorId: 'user-1',
      judgeId: 'user-1',
      status: GameStatus.inProgress,
      inviteCode: 'ZZZ999',
      createdAt: DateTime.parse('2026-09-10T10:00:00.000Z'),
      players: const [
        Player(userId: 'user-1', displayName: 'Alice', totalScore: 0),
      ],
      tasks: const [],
      settings: const GameSettings(),
    );

void main() {
  late MockGameRepository gameRepository;
  late MockAuthRepository authRepository;
  late MockFeedDataSource source;
  late FeedRepositoryImpl feedRepository;

  setUpAll(() {
    registerFallbackValue(FakeUser());
  });

  setUp(() {
    gameRepository = MockGameRepository();
    authRepository = MockAuthRepository();
    source = MockFeedDataSource();
    feedRepository = FeedRepositoryImpl(source);

    when(() => authRepository.getCurrentUser())
        .thenAnswer((_) async => testUser);
    when(() => gameRepository.getGamesStream())
        .thenAnswer((_) => Stream.value(const <Game>[]));
    when(() => gameRepository.createStarterGame(any()))
        .thenAnswer((_) async => 'new-starter-game');
  });

  tearDown(() => source.dispose());

  GamesBloc buildBloc() => GamesBloc(
        gameRepository: gameRepository,
        authRepository: authRepository,
        feedRepository: feedRepository,
      );

  group('StartStarterPack', () {
    blocTest<GamesBloc, GamesState>(
      'creates the game the first time and opens task 0',
      build: buildBloc,
      act: (bloc) => bloc.add(const StartStarterPack()),
      expect: () => [
        isA<GamesLoading>(),
        const StarterPackReady(gameId: 'new-starter-game', taskIndex: 0),
      ],
      verify: (_) {
        verify(() => gameRepository.createStarterGame(testUser)).called(1);
      },
    );

    blocTest<GamesBloc, GamesState>(
      'is idempotent: an existing starter game is reused, never recreated',
      setUp: () {
        when(() => gameRepository.getGamesStream()).thenAnswer(
          (_) => Stream.value([
            ordinaryGame(),
            starterGame(states: const [
              TaskPlayerState.judged,
              TaskPlayerState.submitted,
              TaskPlayerState.not_started,
            ]),
          ]),
        );
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const StartStarterPack()),
      expect: () => [
        isA<GamesLoading>(),
        const StarterPackReady(gameId: 'starter-game', taskIndex: 2),
      ],
      verify: (_) {
        verifyNever(() => gameRepository.createStarterGame(any()));
      },
    );

    blocTest<GamesBloc, GamesState>(
      'ignores somebody else\'s starter game',
      setUp: () {
        when(() => gameRepository.getGamesStream()).thenAnswer(
          (_) => Stream.value([
            starterGame(
              states: const [TaskPlayerState.not_started],
              creatorId: 'someone-else',
            ),
          ]),
        );
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const StartStarterPack()),
      expect: () => [
        isA<GamesLoading>(),
        const StarterPackReady(gameId: 'new-starter-game', taskIndex: 0),
      ],
    );

    blocTest<GamesBloc, GamesState>(
      'ignores an ordinary game of the user\'s',
      setUp: () {
        when(() => gameRepository.getGamesStream())
            .thenAnswer((_) => Stream.value([ordinaryGame()]));
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const StartStarterPack()),
      expect: () => [
        isA<GamesLoading>(),
        const StarterPackReady(gameId: 'new-starter-game', taskIndex: 0),
      ],
    );

    blocTest<GamesBloc, GamesState>(
      'taskIndex is the first task with nothing handed in',
      setUp: () {
        when(() => gameRepository.getGamesStream()).thenAnswer(
          (_) => Stream.value([
            starterGame(states: const [
              TaskPlayerState.submitted,
              TaskPlayerState.judged,
              TaskPlayerState.submitted,
              TaskPlayerState.in_progress,
              TaskPlayerState.not_started,
            ]),
          ]),
        );
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const StartStarterPack()),
      expect: () => [
        isA<GamesLoading>(),
        const StarterPackReady(gameId: 'starter-game', taskIndex: 3),
      ],
    );

    blocTest<GamesBloc, GamesState>(
      'taskIndex is the LAST task once all ten are done',
      setUp: () {
        when(() => gameRepository.getGamesStream()).thenAnswer(
          (_) => Stream.value([
            starterGame(
              states: List.filled(10, TaskPlayerState.judged),
            ),
          ]),
        );
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const StartStarterPack()),
      expect: () => [
        isA<GamesLoading>(),
        const StarterPackReady(gameId: 'starter-game', taskIndex: 9),
      ],
    );

    blocTest<GamesBloc, GamesState>(
      'seeds the house entries so a brand-new player has something to grade',
      build: buildBloc,
      act: (bloc) => bloc.add(const StartStarterPack()),
      wait: const Duration(milliseconds: 20),
      verify: (_) {
        expect(source.posts.length, StarterPackData.houseEntries.length);
      },
    );

    blocTest<GamesBloc, GamesState>(
      'still starts the game when the Arena seeding fails',
      build: () => GamesBloc(
        gameRepository: gameRepository,
        authRepository: authRepository,
        // No feed repository wired, and none registered in the locator.
      ),
      act: (bloc) => bloc.add(const StartStarterPack()),
      expect: () => [
        isA<GamesLoading>(),
        const StarterPackReady(gameId: 'new-starter-game', taskIndex: 0),
      ],
    );

    blocTest<GamesBloc, GamesState>(
      'creates a game anyway when the existing-game lookup fails',
      setUp: () {
        when(() => gameRepository.getGamesStream())
            .thenAnswer((_) => Stream.error(Exception('offline')));
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const StartStarterPack()),
      expect: () => [
        isA<GamesLoading>(),
        const StarterPackReady(gameId: 'new-starter-game', taskIndex: 0),
      ],
    );

    blocTest<GamesBloc, GamesState>(
      'emits a friendly error when nobody is signed in',
      setUp: () {
        when(() => authRepository.getCurrentUser()).thenAnswer((_) async => null);
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const StartStarterPack()),
      expect: () => [isA<GamesLoading>(), isA<GamesError>()],
    );

    blocTest<GamesBloc, GamesState>(
      'emits a friendly error when the game cannot be created',
      setUp: () {
        when(() => gameRepository.createStarterGame(any()))
            .thenThrow(Exception('firestore is having a day'));
      },
      build: buildBloc,
      act: (bloc) => bloc.add(const StartStarterPack()),
      expect: () => [isA<GamesLoading>(), isA<GamesError>()],
      verify: (bloc) {
        final state = bloc.state as GamesError;
        expect(state.message, isNot(contains('Exception')));
      },
    );
  });
}
