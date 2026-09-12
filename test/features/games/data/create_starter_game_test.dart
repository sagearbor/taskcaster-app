import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/models/game.dart';
import 'package:taskcaster_app/core/models/player_task_status.dart';
import 'package:taskcaster_app/core/models/user.dart';
import 'package:taskcaster_app/features/games/data/datasources/mock_game_data_source.dart';
import 'package:taskcaster_app/features/games/data/repositories/game_repository_impl.dart';
import 'package:taskcaster_app/features/tasks/data/datasources/starter_pack_data.dart';

void main() {
  late GameRepositoryImpl repo;

  final user = User(
    id: 'user-1',
    displayName: 'Alice',
    createdAt: DateTime.parse('2026-09-01T10:00:00.000Z'),
  );

  setUp(() {
    repo = GameRepositoryImpl(MockGameDataSource());
  });

  Future<Game> create() async {
    final id = await repo.createStarterGame(user);
    final game = await repo.getGameStream(id).first;
    expect(game, isNotNull);
    return game!;
  }

  test('creates an in-progress starter game owned by the player', () async {
    final game = await create();
    expect(game.gameKind, Game.kindStarter);
    expect(game.isStarter, isTrue);
    expect(game.gameName, StarterPackData.gameName);
    expect(game.status, GameStatus.inProgress);
    expect(game.creatorId, user.id);
    expect(game.judgeId, user.id);
    expect(game.currentTaskIndex, 0);
  });

  test('has exactly one player: the creator, with their real name', () async {
    final game = await create();
    expect(game.players.length, 1);
    expect(game.players.single.userId, user.id);
    expect(game.players.single.displayName, 'Alice');
    expect(game.players.single.totalScore, 0);
  });

  test('carries the ten starter tasks with the creator seeded on each',
      () async {
    final game = await create();
    expect(game.tasks.length, 10);
    expect(
      game.tasks.map((t) => t.id),
      StarterPackData.tasks().map((t) => t.id),
    );
    for (final task in game.tasks) {
      expect(task.playerStatuses.keys, [user.id]);
      expect(task.playerStatuses[user.id]!.state, TaskPlayerState.not_started);
      expect(task.rubric, isNotNull);
      expect(task.twist, isNotNull);
      expect(task.durationSeconds, isNotNull);
    }
  });

  test('is crowd-judged, shared, skippable and has no per-task deadline',
      () async {
    final game = await create();
    expect(game.settings.crowdJudged, isTrue);
    expect(game.settings.shareToArena, isTrue);
    expect(game.settings.autoAdvanceTasks, isTrue);
    expect(game.settings.allowSkips, isTrue);
    expect(game.settings.taskDeadline, isNull);
    for (final task in game.tasks) {
      expect(task.deadline, isNull);
    }
  });

  test('survives the store round trip', () async {
    final game = await create();
    expect(Game.fromMap(game.toMap()), game);
  });
}
