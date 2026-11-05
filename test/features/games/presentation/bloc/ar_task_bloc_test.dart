import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/di/service_locator.dart';
import 'package:taskcaster_app/core/models/task.dart';
import 'package:taskcaster_app/core/services/ar/ar_capability_service.dart';
import 'package:taskcaster_app/features/games/domain/repositories/game_repository.dart';
import 'package:taskcaster_app/features/games/presentation/bloc/ar_task_bloc.dart';

/// A controllable capability service for driving the bloc through each branch
/// without any plugin/platform channel.
class _FakeCapability implements ArCapabilityService {
  ArSupport result;
  bool grantCamera;
  _FakeCapability(this.result, {this.grantCamera = true});

  @override
  Future<ArSupport> check() async => result;

  @override
  Future<bool> requestCamera() async => grantCamera;

  @override
  Future<void> openSettings() async {}
}

void main() {
  group('ArTaskBloc', () {
    late GameRepository repo;
    late String gameId;
    const creatorId = 'alice';
    const challengerId = 'bob';

    setUp(() async {
      await ServiceLocator.init(useMockServices: true);
      repo = sl<GameRepository>();

      gameId = await repo.createGame('AR Game', creatorId, creatorId);
      final created = await repo.getGameStream(gameId).first;
      await repo.joinGame(created!.inviteCode, challengerId, 'Bob');
      await repo.addTasksToGame(gameId, [
        const Task(
          id: 'ar-1',
          title: 'Balloon Pop',
          description: 'pop',
          taskType: TaskType.ar,
          arGameId: 'balloon_pop',
          submissions: [],
        ),
      ]);
      await repo.startGame(gameId);
    });

    tearDown(() async => sl.reset());

    ArTaskBloc build(ArCapabilityService cap, String userId) => ArTaskBloc(
          capabilityService: cap,
          gameRepository: repo,
          gameId: gameId,
          taskIndex: 0,
          userId: userId,
        );

    test('unsupported platform yields ArTaskUnsupported', () async {
      final bloc = build(_FakeCapability(ArSupport.unsupportedPlatform), creatorId);
      bloc.add(const ArCheckRequested());
      await expectLater(
        bloc.stream,
        emitsThrough(isA<ArTaskUnsupported>()),
      );
      await bloc.close();
    });

    test('supported device becomes ArTaskReady', () async {
      final bloc = build(_FakeCapability(ArSupport.supported), creatorId);
      bloc.add(const ArCheckRequested());
      await expectLater(bloc.stream, emitsThrough(isA<ArTaskReady>()));
      await bloc.close();
    });

    test('the judge submitting a score writes to the scoreboard',
        () async {
      final bloc = build(_FakeCapability(ArSupport.supported), creatorId);
      bloc.add(const ArScoreSubmitted(score: 9, rawResult: 9));
      await expectLater(bloc.stream, emitsThrough(isA<ArTaskSubmitted>()));
      await bloc.close();

      final game = await repo.getGameStream(gameId).first;
      expect(
        game!.players.firstWhere((p) => p.userId == creatorId).totalScore,
        9,
      );
    });

    test("a challenger's score is handed in for the judge, not banked",
        () async {
      final bloc = build(_FakeCapability(ArSupport.supported), challengerId);
      bloc.add(const ArScoreSubmitted(score: 9, rawResult: 9));
      await expectLater(bloc.stream, emitsThrough(isA<ArTaskSubmitted>()));
      await bloc.close();

      final game = await repo.getGameStream(gameId).first;
      final status = game!.tasks.single.getPlayerStatus(challengerId)!;
      expect(status.score, 9);
      expect(status.isJudged, isFalse);
      expect(
        game.players.firstWhere((p) => p.userId == challengerId).totalScore,
        0,
      );
    });

    test('skip marks the player skipped without scoring', () async {
      // Enable skips for this game.
      final g = await repo.getGameStream(gameId).first;
      await repo.updateGame(
        gameId,
        g!.copyWith(settings: g.settings.copyWith(allowSkips: true)),
      );

      final bloc = build(_FakeCapability(ArSupport.unsupportedPlatform), challengerId);
      bloc.add(const ArSkipRequested());
      await expectLater(bloc.stream, emitsThrough(isA<ArTaskSubmitted>()));
      await bloc.close();

      final game = await repo.getGameStream(gameId).first;
      final status = game!.tasks.single.getPlayerStatus(challengerId);
      expect(status, isNotNull);
      // Skipped, and no score awarded.
      expect(
        game.players.firstWhere((p) => p.userId == challengerId).totalScore,
        0,
      );
    });
  });
}
