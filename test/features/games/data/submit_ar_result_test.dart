import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/di/service_locator.dart';
import 'package:taskcaster_app/core/models/game.dart';
import 'package:taskcaster_app/core/models/task.dart';
import 'package:taskcaster_app/features/games/domain/repositories/game_repository.dart';

/// Verifies STEP 2: an AR task result, submitted via [GameRepository.submitArResult],
/// performs the same scoreboard mutation as the human-judge path — landing a
/// score on the player's total, stamping a judged submission, and completing
/// the task/game — all without any data-source or AR-plugin changes.
void main() {
  group('submitArResult (mock services)', () {
    late GameRepository repo;

    setUp(() async {
      await ServiceLocator.init(useMockServices: true);
      repo = sl<GameRepository>();
    });

    tearDown(() async {
      await sl.reset();
    });

    test('AR self-judge lands on scoreboard and completes the AR task',
        () async {
      const creatorId = 'alice';
      const challengerId = 'bob';

      final gameId = await repo.createGame('AR Party', creatorId, creatorId);
      final created = await repo.getGameStream(gameId).first;
      await repo.joinGame(created!.inviteCode, challengerId, 'Bob');

      // Single AR task: Balloon Pop.
      await repo.addTasksToGame(gameId, [
        const Task(
          id: 'ar-task-1',
          title: 'Balloon Pop',
          description: 'Pop as many balloons as you can',
          taskType: TaskType.ar,
          arGameId: 'balloon_pop',
          submissions: [],
        ),
      ]);
      await repo.startGame(gameId);

      // Both players self-judge their AR result instantly (no judge UI, no
      // video submission). rawResult carries the gameplay metric.
      await repo.submitArResult(gameId, 0, challengerId, 8, rawResult: 8);
      await repo.submitArResult(gameId, 0, creatorId, 5, rawResult: 5);

      final done = await repo.getGameStream(gameId).first;
      final task = done!.tasks.single;

      // Scores landed on player totals.
      expect(done.players.firstWhere((p) => p.userId == challengerId).totalScore,
          8);
      expect(
          done.players.firstWhere((p) => p.userId == creatorId).totalScore, 5);

      // Submissions stamped judged with the awarded scores.
      final bobSub = task.submissions.firstWhere((s) => s.userId == challengerId);
      expect(bobSub.score, 8);
      expect(bobSub.isJudged, isTrue);

      // Raw AR result recorded on the task.
      expect(task.arResult, isNotNull);

      // Task + game complete once everyone is judged.
      expect(task.allPlayersJudged, isTrue);
      expect(task.status, TaskStatus.completed);
      expect(done.status, GameStatus.completed);
    });

    test('a single AR self-judge advances only that player', () async {
      const creatorId = 'alice';
      const challengerId = 'bob';

      final gameId = await repo.createGame('AR Mix', creatorId, creatorId);
      final created = await repo.getGameStream(gameId).first;
      await repo.joinGame(created!.inviteCode, challengerId, 'Bob');
      await repo.addTasksToGame(gameId, [
        const Task(
          id: 'ar-task-1',
          title: 'Balloon Pop',
          description: 'Pop balloons',
          taskType: TaskType.ar,
          arGameId: 'balloon_pop',
          submissions: [],
        ),
      ]);
      await repo.startGame(gameId);

      await repo.submitArResult(gameId, 0, challengerId, 7);

      final mid = await repo.getGameStream(gameId).first;
      final task = mid!.tasks.single;
      // Bob is judged; Alice is not — task not yet complete, game in progress.
      expect(task.getPlayerStatus(challengerId)!.isJudged, isTrue);
      expect(task.getPlayerStatus(creatorId)!.isJudged, isFalse);
      expect(task.status, isNot(TaskStatus.completed));
      expect(mid.status, GameStatus.inProgress);
      expect(mid.players.firstWhere((p) => p.userId == challengerId).totalScore,
          7);
    });
  });
}
