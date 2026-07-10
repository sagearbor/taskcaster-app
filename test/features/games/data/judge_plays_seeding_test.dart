import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/di/service_locator.dart';
import 'package:taskcaster_app/core/models/game_settings.dart';
import 'package:taskcaster_app/core/models/task.dart';
import 'package:taskcaster_app/features/games/domain/repositories/game_repository.dart';

/// REGRESSION: asymmetric games where the judge doesn't play (House Hunt —
/// the hider only judges) must not seed the judge a per-task status. A seeded
/// status the judge never fulfils keeps [Task.allPlayersJudged] false forever,
/// so the hunt could never complete.
void main() {
  group('judgePlays seeding', () {
    late GameRepository repo;

    setUp(() async {
      await ServiceLocator.init(useMockServices: true);
      repo = sl<GameRepository>();
    });

    tearDown(() async {
      await sl.reset();
    });

    const huntTask = Task(
      id: 'hunt-1',
      title: 'Find something red',
      description: 'Hunt! Find something red. Snap a photo as your proof.',
      taskType: TaskType.video,
      submissions: [],
    );

    test('judgePlays=false seeds statuses for everyone EXCEPT the judge',
        () async {
      const hider = 'hider';
      const seeker = 'seeker';

      final gameId = await repo.createGame("Hider's House Hunt", hider, hider);
      final created = await repo.getGameStream(gameId).first;
      await repo.updateGame(
        gameId,
        created!.copyWith(
          settings: created.settings.copyWith(judgePlays: false),
        ),
      );
      await repo.joinGame(created.inviteCode, seeker, 'Seeker');
      await repo.addTasksToGame(gameId, [huntTask]);
      await repo.startGame(gameId);

      final started = await repo.getGameStream(gameId).first;
      final task = started!.tasks.single;

      expect(task.playerStatuses.keys, [seeker],
          reason: 'only the seeker is expected to submit — never the judge');
      expect(task.allPlayersJudged, isFalse,
          reason: 'the seeker has not been judged yet');
    });

    test('judgePlays=false tasks added MID-game also skip the judge',
        () async {
      const hider = 'hider';
      const seeker = 'seeker';

      final gameId = await repo.createGame("Hider's House Hunt", hider, hider);
      final created = await repo.getGameStream(gameId).first;
      await repo.updateGame(
        gameId,
        created!.copyWith(
          settings: created.settings.copyWith(judgePlays: false),
        ),
      );
      await repo.joinGame(created.inviteCode, seeker, 'Seeker');
      await repo.addTasksToGame(gameId, [huntTask]);
      await repo.startGame(gameId);

      await repo.addTasksToGame(gameId, [
        huntTask.copyWith(id: 'hunt-2', title: 'The oldest thing you can find'),
      ]);

      final game = await repo.getGameStream(gameId).first;
      final added = game!.tasks.firstWhere((t) => t.id == 'hunt-2');
      expect(added.playerStatuses.keys, [seeker]);
    });

    test('default (judgePlays=true) seeds every player including the judge',
        () async {
      const judge = 'judge';
      const player = 'player';

      final gameId = await repo.createGame('Normal Game', judge, judge);
      final created = await repo.getGameStream(gameId).first;
      await repo.joinGame(created!.inviteCode, player, 'Player');
      await repo.addTasksToGame(gameId, [huntTask]);
      await repo.startGame(gameId);

      final started = await repo.getGameStream(gameId).first;
      expect(started!.tasks.single.playerStatuses.keys.toSet(),
          {judge, player});
    });

    test('GameSettings round-trips judgePlays and defaults to true', () {
      const settings = GameSettings(judgePlays: false);
      expect(GameSettings.fromMap(settings.toMap()).judgePlays, isFalse);

      // Older docs have no judgePlays key -> judge plays (legacy behavior).
      expect(GameSettings.fromMap(const {}).judgePlays, isTrue);
      expect(const GameSettings().judgePlays, isTrue);
    });
  });
}
