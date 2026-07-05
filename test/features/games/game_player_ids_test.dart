import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/models/game.dart';
import 'package:taskcaster_app/core/models/game_settings.dart';
import 'package:taskcaster_app/core/models/player.dart';

Game _game(List<Player> players) => Game(
      id: 'g1',
      gameName: 'Test',
      creatorId: players.first.userId,
      judgeId: players.first.userId,
      status: GameStatus.lobby,
      inviteCode: 'ABC234',
      createdAt: DateTime(2026, 1, 1),
      players: players,
      tasks: const [],
      settings: GameSettings.quickPlay(),
    );

void main() {
  group('Game.playerIds', () {
    test('derives from players', () {
      final game = _game(const [
        Player(userId: 'a', displayName: 'A', totalScore: 0),
        Player(userId: 'b', displayName: 'B', totalScore: 0),
      ]);
      expect(game.playerIds, ['a', 'b']);
    });

    test('toMap includes playerIds in step with players', () {
      final game = _game(const [
        Player(userId: 'a', displayName: 'A', totalScore: 0),
        Player(userId: 'b', displayName: 'B', totalScore: 0),
      ]);
      expect(game.toMap()['playerIds'], ['a', 'b']);
    });

    test('backfills from players[] when the stored field is missing', () {
      final map = _game(const [
        Player(userId: 'a', displayName: 'A', totalScore: 0),
        Player(userId: 'b', displayName: 'B', totalScore: 0),
      ]).toMap()
        ..remove('playerIds'); // legacy doc written before the field existed

      final restored = Game.fromMap(map);
      expect(restored.playerIds, ['a', 'b']);
    });

    test('stays in sync after copyWith adds a player', () {
      final game = _game(const [
        Player(userId: 'a', displayName: 'A', totalScore: 0),
      ]);
      final updated = game.copyWith(players: [
        ...game.players,
        const Player(userId: 'c', displayName: 'C', totalScore: 0),
      ]);
      expect(updated.playerIds, ['a', 'c']);
      expect(updated.toMap()['playerIds'], ['a', 'c']);
    });
  });
}
