import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/models/game.dart';
import 'package:taskcaster_app/core/models/game_settings.dart';
import 'package:taskcaster_app/core/models/player.dart';
import 'package:taskcaster_app/core/models/submission.dart';
import 'package:taskcaster_app/core/models/task.dart';
import 'package:taskcaster_app/features/games/data/datasources/mock_game_data_source.dart';
import 'package:taskcaster_app/features/games/data/repositories/game_repository_impl.dart';

Game _finishedGame({String name = 'Family Game Night'}) {
  Task playedTask(String id, String title) => Task(
        id: id,
        title: title,
        description: 'desc for $title',
        taskType: TaskType.video,
        status: TaskStatus.completed,
        submissions: [
          Submission(
            id: 'sub_$id',
            userId: 'user_a',
            videoUrl: 'https://example.com/$id',
            score: 3,
            isJudged: true,
            submittedAt: DateTime(2026, 7, 1),
          ),
        ],
      );

  return Game(
    id: 'source_game',
    gameName: name,
    creatorId: 'user_a',
    judgeId: 'user_b',
    status: GameStatus.completed,
    inviteCode: 'ABC234',
    createdAt: DateTime(2026, 7, 1),
    players: const [
      Player(userId: 'user_a', displayName: 'Alice', totalScore: 12),
      Player(userId: 'user_b', displayName: 'Bob', totalScore: 7),
      Player(userId: 'user_c', displayName: 'Cara', totalScore: 9),
    ],
    tasks: [
      playedTask('t1', 'Make the most magnificent sandwich'),
      playedTask('t2', 'Build the tallest tower'),
      playedTask('t3', 'Invent a secret handshake'),
    ],
    currentTaskIndex: 2,
    settings: GameSettings.quickPlay(),
  );
}

void main() {
  group('GameRepositoryImpl.rematchGame', () {
    late MockGameDataSource dataSource;
    late GameRepositoryImpl repository;

    setUp(() {
      dataSource = MockGameDataSource();
      repository = GameRepositoryImpl(dataSource);
    });

    tearDown(() => dataSource.dispose());

    test('creates a fresh lobby game with the same crew and judge', () async {
      final source = _finishedGame();

      final newId = await repository.rematchGame(source);
      expect(newId, isNot(source.id));

      final rematch = await repository.getGameStream(newId).first;
      expect(rematch, isNotNull);

      // Fresh lobby, same creator + judge.
      expect(rematch!.status, GameStatus.lobby);
      expect(rematch.creatorId, source.creatorId);
      expect(rematch.judgeId, source.judgeId);

      // Same crew, scores wiped, names intact.
      expect(
        rematch.players.map((p) => p.userId).toSet(),
        source.players.map((p) => p.userId).toSet(),
      );
      expect(rematch.players.every((p) => p.totalScore == 0), isTrue);
      expect(
        rematch.players.firstWhere((p) => p.userId == 'user_a').displayName,
        'Alice',
      );
    });

    test('draws the same NUMBER of tasks, but fresh unplayed ones', () async {
      final source = _finishedGame();

      final newId = await repository.rematchGame(source);
      final rematch = await repository.getGameStream(newId).first;

      expect(rematch!.tasks.length, source.tasks.length);

      final sourceIds = source.tasks.map((t) => t.id).toSet();
      final sourceTitles = source.tasks.map((t) => t.title).toSet();
      for (final task in rematch.tasks) {
        expect(sourceIds.contains(task.id), isFalse,
            reason: 'rematch tasks must be new task docs');
        expect(sourceTitles.contains(task.title), isFalse,
            reason: 'the crew should not replay the tasks they just played');
        expect(task.submissions, isEmpty);
        expect(task.playerStatuses, isEmpty);
      }
    });

    test('names the rematch after the source game and counts rounds',
        () async {
      final first = await repository.rematchGame(_finishedGame());
      final firstGame = await repository.getGameStream(first).first;
      expect(firstGame!.gameName, 'Family Game Night — Rematch');

      final second = await repository
          .rematchGame(_finishedGame(name: 'Family Game Night — Rematch'));
      final secondGame = await repository.getGameStream(second).first;
      expect(secondGame!.gameName, 'Family Game Night — Rematch 2');
    });
  });
}
