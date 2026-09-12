import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:taskcaster_app/core/models/game.dart';
import 'package:taskcaster_app/core/models/game_settings.dart';
import 'package:taskcaster_app/core/models/player.dart';
import 'package:taskcaster_app/core/models/player_task_status.dart';
import 'package:taskcaster_app/core/models/submission.dart';
import 'package:taskcaster_app/core/models/task.dart';
import 'package:taskcaster_app/features/arena/domain/crowd_score_applier.dart';
import 'package:taskcaster_app/features/games/domain/repositories/game_repository.dart';
import 'package:taskcaster_app/features/games/presentation/bloc/game_detail_bloc.dart';

class MockGameRepository extends Mock implements GameRepository {}

class MockCrowdScoreApplier extends Mock implements CrowdScoreApplier {}

class FakeGame extends Fake implements Game {}

const owner = 'owner-1';

Game buildGame({
  bool crowdJudged = true,
  String creatorId = owner,
  TaskPlayerState state = TaskPlayerState.submitted,
  String? feedPostId = 'post-1',
}) {
  return Game(
    id: 'game-1',
    gameName: 'Your First Ten',
    creatorId: creatorId,
    judgeId: creatorId,
    status: GameStatus.inProgress,
    inviteCode: 'ABC123',
    createdAt: DateTime.parse('2026-09-12T10:00:00.000Z'),
    players: [Player(userId: creatorId, displayName: 'Alice', totalScore: 0)],
    tasks: [
      Task(
        id: 'starter-01',
        title: 'A vegetable that has just received terrible news',
        description: 'Find a vegetable.',
        taskType: TaskType.video,
        submissions: [
          Submission(
            id: 'sub-1',
            userId: creatorId,
            score: 0,
            isJudged: false,
            submittedAt: DateTime.parse('2026-09-12T11:00:00.000Z'),
            mediaType: SubmissionMediaType.photo,
            feedPostId: feedPostId,
          ),
        ],
        playerStatuses: {
          creatorId: PlayerTaskStatus(playerId: creatorId, state: state),
        },
      ),
    ],
    settings: GameSettings(crowdJudged: crowdJudged, shareToArena: true),
    gameKind: Game.kindStarter,
  );
}

void main() {
  late MockGameRepository gameRepository;
  late MockCrowdScoreApplier applier;

  setUpAll(() {
    registerFallbackValue(FakeGame());
  });

  setUp(() {
    gameRepository = MockGameRepository();
    applier = MockCrowdScoreApplier();
    when(() => applier.applyPending(any())).thenAnswer((_) async => 1);
  });

  void streaming(Game game) {
    when(() => gameRepository.getGameStream('game-1'))
        .thenAnswer((_) => Stream.value(game));
  }

  GameDetailBloc buildBloc({String? viewer = owner}) => GameDetailBloc(
        gameRepository: gameRepository,
        crowdScoreApplier: applier,
        currentUserId: viewer,
      );

  blocTest<GameDetailBloc, GameDetailState>(
    'applies pending crowd scores when the owner opens a crowd-judged game',
    setUp: () => streaming(buildGame()),
    build: buildBloc,
    act: (bloc) => bloc.add(const LoadGameDetail(gameId: 'game-1')),
    wait: const Duration(milliseconds: 20),
    verify: (_) {
      verify(() => applier.applyPending(any())).called(1);
    },
  );

  blocTest<GameDetailBloc, GameDetailState>(
    'does nothing for a viewer who does not own the game',
    setUp: () => streaming(buildGame()),
    build: () => buildBloc(viewer: 'someone-else'),
    act: (bloc) => bloc.add(const LoadGameDetail(gameId: 'game-1')),
    wait: const Duration(milliseconds: 20),
    verify: (_) => verifyNever(() => applier.applyPending(any())),
  );

  blocTest<GameDetailBloc, GameDetailState>(
    'does nothing for a human-judged game',
    setUp: () => streaming(buildGame(crowdJudged: false)),
    build: buildBloc,
    act: (bloc) => bloc.add(const LoadGameDetail(gameId: 'game-1')),
    wait: const Duration(milliseconds: 20),
    verify: (_) => verifyNever(() => applier.applyPending(any())),
  );

  blocTest<GameDetailBloc, GameDetailState>(
    'does nothing when no task is waiting on a crowd score',
    setUp: () => streaming(buildGame(state: TaskPlayerState.judged)),
    build: buildBloc,
    act: (bloc) => bloc.add(const LoadGameDetail(gameId: 'game-1')),
    wait: const Duration(milliseconds: 20),
    verify: (_) => verifyNever(() => applier.applyPending(any())),
  );

  blocTest<GameDetailBloc, GameDetailState>(
    'does nothing when the submission has no Arena post behind it',
    setUp: () => streaming(buildGame(feedPostId: null)),
    build: buildBloc,
    act: (bloc) => bloc.add(const LoadGameDetail(gameId: 'game-1')),
    wait: const Duration(milliseconds: 20),
    verify: (_) => verifyNever(() => applier.applyPending(any())),
  );

  blocTest<GameDetailBloc, GameDetailState>(
    'runs once, not once per stream re-emit — the write it makes cannot loop',
    setUp: () {
      final game = buildGame();
      when(() => gameRepository.getGameStream('game-1')).thenAnswer(
        (_) => Stream.fromIterable([game, game, game]),
      );
    },
    build: buildBloc,
    act: (bloc) => bloc.add(const LoadGameDetail(gameId: 'game-1')),
    wait: const Duration(milliseconds: 40),
    verify: (_) => verify(() => applier.applyPending(any())).called(1),
  );

  blocTest<GameDetailBloc, GameDetailState>(
    'still renders the game when applying crowd scores throws',
    setUp: () {
      streaming(buildGame());
      when(() => applier.applyPending(any()))
          .thenThrow(Exception('firestore is having a day'));
    },
    build: buildBloc,
    act: (bloc) => bloc.add(const LoadGameDetail(gameId: 'game-1')),
    wait: const Duration(milliseconds: 20),
    expect: () => [isA<GameDetailLoading>(), isA<GameDetailLoaded>()],
  );

  blocTest<GameDetailBloc, GameDetailState>(
    'is inert when no applier is wired up (the default)',
    setUp: () => streaming(buildGame()),
    build: () => GameDetailBloc(gameRepository: gameRepository),
    act: (bloc) => bloc.add(const LoadGameDetail(gameId: 'game-1')),
    wait: const Duration(milliseconds: 20),
    expect: () => [isA<GameDetailLoading>(), isA<GameDetailLoaded>()],
  );
}
