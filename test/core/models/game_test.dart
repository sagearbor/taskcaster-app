import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/models/game.dart';
import 'package:taskcaster_app/core/models/game_settings.dart';
import 'package:taskcaster_app/core/models/player.dart';
import 'package:taskcaster_app/core/models/task.dart';

void main() {
  group('Game Model Tests', () {
    late Game testGame;
    late List<Player> testPlayers;
    late List<Task> testTasks;

    setUp(() {
      testPlayers = [
        const Player(
          userId: 'user1',
          displayName: 'Alice',
          totalScore: 15,
        ),
        const Player(
          userId: 'user2',
          displayName: 'Bob',
          totalScore: 12,
        ),
      ];

      testTasks = [
        Task(
          id: 'task1',
          title: 'Test Task',
          description: 'A test task',
          taskType: TaskType.video,
          submissions: [],
        ),
      ];

      testGame = Game(
        id: 'game1',
        gameName: 'Test Game',
        creatorId: 'user1',
        judgeId: 'user1',
        status: GameStatus.lobby,
        inviteCode: 'TEST01',
        createdAt: DateTime.now(),
        players: testPlayers,
        tasks: testTasks,
        settings: const GameSettings(),
      );
    });

    test('should create game with all required fields', () {
      expect(testGame.id, 'game1');
      expect(testGame.gameName, 'Test Game');
      expect(testGame.creatorId, 'user1');
      expect(testGame.judgeId, 'user1');
      expect(testGame.status, GameStatus.lobby);
      expect(testGame.inviteCode, 'TEST01');
      expect(testGame.players, testPlayers);
      expect(testGame.tasks, testTasks);
    });

    test('should correctly identify game status', () {
      expect(testGame.isInLobby, true);
      expect(testGame.isInProgress, false);
      expect(testGame.isCompleted, false);

      final inProgressGame = testGame.copyWith(status: GameStatus.inProgress);
      expect(inProgressGame.isInLobby, false);
      expect(inProgressGame.isInProgress, true);
      expect(inProgressGame.isCompleted, false);

      final completedGame = testGame.copyWith(status: GameStatus.completed);
      expect(completedGame.isInLobby, false);
      expect(completedGame.isInProgress, false);
      expect(completedGame.isCompleted, true);
    });

    test('should find player by ID', () {
      final player = testGame.getPlayerById('user1');
      expect(player, isNotNull);
      expect(player!.displayName, 'Alice');

      final nonExistentPlayer = testGame.getPlayerById('user999');
      expect(nonExistentPlayer, isNull);
    });

    test('should check if user is in game', () {
      expect(testGame.isUserInGame('user1'), true);
      expect(testGame.isUserInGame('user2'), true);
      expect(testGame.isUserInGame('user999'), false);
    });

    test('should check if user is creator', () {
      expect(testGame.isUserCreator('user1'), true);
      expect(testGame.isUserCreator('user2'), false);
    });

    test('should check if user is judge', () {
      expect(testGame.isUserJudge('user1'), true);
      expect(testGame.isUserJudge('user2'), false);
    });

    test('should convert to/from map correctly', () {
      final map = testGame.toMap();
      final reconstructedGame = Game.fromMap(map);

      expect(reconstructedGame.id, testGame.id);
      expect(reconstructedGame.gameName, testGame.gameName);
      expect(reconstructedGame.status, testGame.status);
      expect(reconstructedGame.players.length, testGame.players.length);
      expect(reconstructedGame.tasks.length, testGame.tasks.length);
    });

    test('gameKind defaults to null and round-trips through toMap/fromMap',
        () {
      expect(testGame.gameKind, isNull);

      final map = testGame.toMap();
      expect(map['gameKind'], isNull);
      final reconstructed = Game.fromMap(map);
      expect(reconstructed.gameKind, isNull);

      final kindedGame = testGame.copyWith(gameKind: 'house_hunt');
      expect(kindedGame.gameKind, 'house_hunt');
      final kindedMap = kindedGame.toMap();
      expect(kindedMap['gameKind'], 'house_hunt');
      expect(Game.fromMap(kindedMap).gameKind, 'house_hunt');
    });

    test('gameKind parses as null when the key is absent from the map '
        '(pre-existing docs written before the field existed)', () {
      final map = testGame.toMap()..remove('gameKind');
      expect(Game.fromMap(map).gameKind, isNull);
    });

    test('should create copy with modified fields', () {
      final modifiedGame = testGame.copyWith(
        gameName: 'Modified Game',
        status: GameStatus.inProgress,
      );

      expect(modifiedGame.gameName, 'Modified Game');
      expect(modifiedGame.status, GameStatus.inProgress);
      expect(modifiedGame.id, testGame.id); // Unchanged
      expect(modifiedGame.creatorId, testGame.creatorId); // Unchanged
    });

    test('should handle equality correctly', () {
      final identicalGame = Game(
        id: testGame.id,
        gameName: testGame.gameName,
        creatorId: testGame.creatorId,
        judgeId: testGame.judgeId,
        status: testGame.status,
        inviteCode: testGame.inviteCode,
        createdAt: testGame.createdAt,
        players: testGame.players,
        tasks: testGame.tasks,
        settings: testGame.settings,
      );

      expect(testGame, equals(identicalGame));

      final differentGame = testGame.copyWith(gameName: 'Different Name');
      expect(testGame, isNot(equals(differentGame)));
    });
  });
}