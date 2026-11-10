import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:taskcaster_app/core/models/game.dart';
import 'package:taskcaster_app/core/models/player_task_status.dart';
import 'package:taskcaster_app/core/models/user.dart';
import 'package:taskcaster_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:taskcaster_app/features/games/data/datasources/mock_game_data_source.dart';
import 'package:taskcaster_app/features/games/data/repositories/game_repository_impl.dart';
import 'package:taskcaster_app/features/games/presentation/bloc/games_bloc.dart';
import 'package:taskcaster_app/features/tasks/data/datasources/daily_task_data.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

User user(String id) => User(
      id: id,
      displayName: id,
      createdAt: DateTime.utc(2026, 11, 1),
    );

void main() {
  late MockGameDataSource source;
  late GameRepositoryImpl repo;
  late MockAuthRepository auth;
  var now = DateTime.utc(2026, 11, 9, 10);

  setUp(() {
    source = MockGameDataSource();
    repo = GameRepositoryImpl(source);
    auth = MockAuthRepository();
    now = DateTime.utc(2026, 11, 9, 10);
    when(() => auth.getCurrentUser()).thenAnswer((_) async => user('alice'));
  });

  GamesBloc bloc() => GamesBloc(
        gameRepository: repo,
        authRepository: auth,
        clock: () => now,
      );

  Future<String> start(GamesBloc b) async {
    final ready = b.stream.firstWhere((s) => s is DailyTaskReady || s is GamesError);
    b.add(const StartDailyTask());
    final s = await ready;
    expect(s, isA<DailyTaskReady>(), reason: '$s');
    return (s as DailyTaskReady).gameId;
  }

  Future<List<Game>> dailyGames() async => (await repo.getGamesStream().first)
      .where((g) => g.isDaily)
      .toList();

  test('creates a one-task, crowd-judged, Arena-shared daily game', () async {
    final b = bloc();
    final id = await start(b);
    expect(id, 'daily_alice_20261109');

    final game = (await repo.getGameStream(id).first)!;
    expect(game.gameKind, Game.kindDaily);
    expect(game.isDaily, isTrue);
    expect(game.isStarter, isFalse);
    expect(game.status, GameStatus.inProgress);
    expect(game.creatorId, 'alice');
    expect(game.players.single.userId, 'alice');
    expect(game.settings.crowdJudged, isTrue);
    expect(game.settings.shareToArena, isTrue);
    expect(game.tasks.length, 1);
    expect(game.tasks.single.id,
        DailyTaskData.taskFor(DateTime.utc(2026, 11, 9)).id);
    expect(game.tasks.single.getPlayerStatus('alice')?.state,
        TaskPlayerState.not_started);
    expect(game.inviteCode, isNotEmpty);
    expect(game.gameName, 'Daily task, 9 Nov');
    await b.close();
  });

  test('starting twice on the same day reuses the same game', () async {
    final b = bloc();
    final first = await start(b);
    now = now.add(const Duration(hours: 8));
    final second = await start(b);
    expect(second, first);
    expect((await dailyGames()).length, 1);
    await b.close();
  });

  test('a second start never overwrites progress already made', () async {
    final b = bloc();
    final id = await start(b);
    await repo.updateTaskAtomically(
      id,
      0,
      (t) => t.copyWith(playerStatuses: {
        'alice': const PlayerTaskStatus(
          playerId: 'alice',
          state: TaskPlayerState.submitted,
        ),
      }),
    );
    await start(b);
    final game = (await repo.getGameStream(id).first)!;
    expect(game.tasks.single.getPlayerStatus('alice')?.state,
        TaskPlayerState.submitted);
    await b.close();
  });

  test('the next UTC day makes a new game with a different task', () async {
    final b = bloc();
    final today = await start(b);
    now = DateTime.utc(2026, 11, 10, 0, 1);
    final tomorrow = await start(b);
    expect(tomorrow, 'daily_alice_20261110');
    expect(tomorrow, isNot(today));
    final games = await dailyGames();
    expect(games.length, 2);
    expect(games[0].tasks.single.id, isNot(games[1].tasks.single.id));
    await b.close();
  });

  test('two players on the same day get the same task id', () async {
    final b = bloc();
    final aliceGame = await start(b);
    when(() => auth.getCurrentUser()).thenAnswer((_) async => user('bob'));
    final bobGame = await start(b);
    expect(bobGame, isNot(aliceGame));
    final a = (await repo.getGameStream(aliceGame).first)!;
    final bo = (await repo.getGameStream(bobGame).first)!;
    expect(a.tasks.single.id, bo.tasks.single.id);
    await b.close();
  });

  test('signed out: a friendly error, no game', () async {
    when(() => auth.getCurrentUser()).thenAnswer((_) async => null);
    final b = bloc();
    final s = b.stream.firstWhere((s) => s is GamesError);
    b.add(const StartDailyTask());
    final err = await s as GamesError;
    expect(err.message, isNot(contains('Exception')));
    expect(await dailyGames(), isEmpty);
    await b.close();
  });
}
