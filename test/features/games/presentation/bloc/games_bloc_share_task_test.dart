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

Game existingStarter() {
  final tasks = StarterPackData.tasks();
  return Game(
    id: 'starter-game',
    gameName: StarterPackData.gameName,
    creatorId: 'user-1',
    judgeId: 'user-1',
    status: GameStatus.inProgress,
    inviteCode: 'ABC123',
    createdAt: DateTime.parse('2026-09-10T10:00:00.000Z'),
    players: const [Player(userId: 'user-1', displayName: 'Alice', totalScore: 0)],
    tasks: [
      for (var i = 0; i < tasks.length; i++)
        tasks[i].copyWith(playerStatuses: {
          'user-1': PlayerTaskStatus(
            playerId: 'user-1',
            state: i == 0 ? TaskPlayerState.submitted : TaskPlayerState.not_started,
          ),
        }),
    ],
    settings: const GameSettings(crowdJudged: true, shareToArena: true),
    gameKind: Game.kindStarter,
  );
}

/// WP-09: a share link's "Your turn" opens THAT starter task.
void main() {
  late MockGameRepository gameRepository;
  late MockAuthRepository authRepository;
  late MockFeedDataSource source;

  setUpAll(() => registerFallbackValue(FakeUser()));

  setUp(() {
    gameRepository = MockGameRepository();
    authRepository = MockAuthRepository();
    source = MockFeedDataSource();
    when(() => authRepository.getCurrentUser()).thenAnswer((_) async => testUser);
    when(() => gameRepository.getGamesStream())
        .thenAnswer((_) => Stream.value(const <Game>[]));
    when(() => gameRepository.createStarterGame(any()))
        .thenAnswer((_) async => 'new-starter-game');
  });

  tearDown(() => source.dispose());

  GamesBloc build() => GamesBloc(
        gameRepository: gameRepository,
        authRepository: authRepository,
        feedRepository: FeedRepositoryImpl(source),
      );

  final doorIndex =
      StarterPackData.tasks().indexWhere((t) => t.id == 'starter-12');

  blocTest<GamesBloc, GamesState>(
    'a brand-new player lands on the shared task, not task 1',
    build: build,
    act: (bloc) => bloc.add(const StartStarterPack(taskId: 'starter-12')),
    expect: () => [
      isA<GamesLoading>(),
      StarterPackReady(gameId: 'new-starter-game', taskIndex: doorIndex),
    ],
  );

  blocTest<GamesBloc, GamesState>(
    'a returning player jumps to the shared task in their existing game',
    setUp: () => when(() => gameRepository.getGamesStream())
        .thenAnswer((_) => Stream.value([existingStarter()])),
    build: build,
    act: (bloc) => bloc.add(const StartStarterPack(taskId: 'starter-12')),
    expect: () => [
      isA<GamesLoading>(),
      StarterPackReady(gameId: 'starter-game', taskIndex: doorIndex),
    ],
  );

  blocTest<GamesBloc, GamesState>(
    'an unknown task id falls back to the next unsubmitted task',
    setUp: () => when(() => gameRepository.getGamesStream())
        .thenAnswer((_) => Stream.value([existingStarter()])),
    build: build,
    act: (bloc) => bloc.add(const StartStarterPack(taskId: 'starter-99')),
    expect: () => [
      isA<GamesLoading>(),
      const StarterPackReady(gameId: 'starter-game', taskIndex: 1),
    ],
  );
}
