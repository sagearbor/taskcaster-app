import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:taskcaster_app/core/config/e2e_mode.dart';
import 'package:taskcaster_app/core/models/game.dart';
import 'package:taskcaster_app/core/models/game_settings.dart';
import 'package:taskcaster_app/core/models/player.dart';
import 'package:taskcaster_app/core/models/player_task_status.dart';
import 'package:taskcaster_app/core/models/task.dart';
import 'package:taskcaster_app/features/arena/data/datasources/mock_feed_data_source.dart';
import 'package:taskcaster_app/features/arena/data/repositories/feed_repository_impl.dart';
import 'package:taskcaster_app/features/games/domain/repositories/game_repository.dart';
import 'package:taskcaster_app/features/games/presentation/bloc/task_execution_bloc.dart';
import 'package:taskcaster_app/features/games/presentation/bloc/task_execution_event.dart';
import 'package:taskcaster_app/features/games/presentation/bloc/task_execution_state.dart';
import '../../../../helpers/atomic_task_writes.dart';

/// Fun audit WP-1: an automated walk (E2eMode on) must never put its test
/// patterns in front of real players.

class MockGameRepository extends Mock implements GameRepository {}

class FakeGame extends Fake implements Game {}

const userId = 'walker-1';

Game buildGame(String taskId, {String? kind = Game.kindStarter}) => Game(
      id: 'game-1',
      gameName: 'Your First Ten',
      creatorId: userId,
      judgeId: userId,
      status: GameStatus.inProgress,
      inviteCode: 'ABC123',
      createdAt: DateTime.parse('2026-11-09T09:00:00.000Z'),
      players: const [
        Player(userId: userId, displayName: 'Guest', totalScore: 0),
      ],
      tasks: [
        Task(
          id: taskId,
          title: 'Make an egg look surprised',
          description: 'Find an egg.',
          taskType: TaskType.video,
          submissionType: SubmissionType.photo,
          durationSeconds: 60,
          submissions: const [],
          playerStatuses: {
            userId: PlayerTaskStatus(
              playerId: userId,
              state: TaskPlayerState.in_progress,
              startedAt: DateTime.now().subtract(const Duration(seconds: 5)),
            ),
          },
        ),
      ],
      settings: const GameSettings(crowdJudged: true, shareToArena: true),
      gameKind: kind,
    );

void main() {
  late MockGameRepository gameRepository;
  late MockFeedDataSource source;
  late FeedRepositoryImpl feedRepository;
  TaskExecutionBloc? bloc;

  setUpAll(() => registerFallbackValue(FakeGame()));

  setUp(() {
    gameRepository = MockGameRepository();
    source = MockFeedDataSource();
    feedRepository = FeedRepositoryImpl(source);
    stubAtomicTaskWrites(gameRepository, onWrite: (_) {});
  });

  tearDown(() async {
    E2eMode.debugReset();
    await bloc?.close();
    bloc = null;
    source.dispose();
  });

  Future<String> postPhoto(String taskId,
      {String? kind = Game.kindStarter}) async {
    when(() => gameRepository.getGameStream('game-1'))
        .thenAnswer((_) => Stream.value(buildGame(taskId, kind: kind)));
    final b = bloc = TaskExecutionBloc(
      gameRepository: gameRepository,
      feedRepository: feedRepository,
    );
    b.add(const LoadTask(gameId: 'game-1', taskIndex: 0, userId: userId));
    await b.stream.firstWhere((s) => s is TaskExecutionLoaded);
    b.add(SubmitTask(
      gameId: 'game-1',
      taskIndex: 0,
      userId: userId,
      photoBytes: Uint8List.fromList(List.filled(32, 3)),
      displayName: 'Guest',
    ));
    final state = await b.stream.firstWhere(
      (s) => s is TaskExecutionSubmitted || s is TaskExecutionError,
    );
    expect(state, isA<TaskExecutionSubmitted>());
    return (state as TaskExecutionSubmitted).feedPostId!;
  }

  Future<List<String>> strangersQueue(String taskId) async {
    final queue = await feedRepository
        .watchQueue(viewerId: 'someone-else', unlockedTaskIds: {taskId}).first;
    return queue.map((p) => p.id).toList();
  }

  test('e2e on: the post is created with shareable false', () async {
    E2eMode.debugOverride(true);
    final id = await postPhoto('starter-06');
    final post = await feedRepository.watchPost(id).first;
    expect(post!.shareable, isFalse);
  });

  test("e2e on: the post never reaches another viewer's Arena queue",
      () async {
    E2eMode.debugOverride(true);
    final id = await postPhoto('starter-06');
    expect(await strangersQueue('starter-06'), isNot(contains(id)));
  });

  test('e2e off: a Starter Pack post stays public', () async {
    E2eMode.debugOverride(false);
    final id = await postPhoto('starter-06');
    final post = await feedRepository.watchPost(id).first;
    expect(post!.shareable, isTrue);
    expect(await strangersQueue('starter-06'), contains(id));
  });

  test('e2e on: a friend-game post is private too', () async {
    E2eMode.debugOverride(true);
    final id = await postPhoto('friend-task-1', kind: null);
    final post = await feedRepository.watchPost(id).first;
    expect(post!.shareable, isFalse);
  });

  test('e2e off: a Daily Task post is public, like the Starter Pack',
      () async {
    E2eMode.debugOverride(false);
    final id = await postPhoto('daily-04', kind: Game.kindDaily);
    final post = await feedRepository.watchPost(id).first;
    expect(post!.shareable, isTrue);
    expect(await strangersQueue('daily-04'), contains(id));
  });

  test('e2e on: a Daily Task post is private', () async {
    E2eMode.debugOverride(true);
    final id = await postPhoto('daily-04', kind: Game.kindDaily);
    final post = await feedRepository.watchPost(id).first;
    expect(post!.shareable, isFalse);
    expect(await strangersQueue('daily-04'), isNot(contains(id)));
  });

  test('e2e off: a friend-game post stays unset until the owner shares',
      () async {
    E2eMode.debugOverride(false);
    final id = await postPhoto('friend-task-1', kind: null);
    final post = await feedRepository.watchPost(id).first;
    expect(post!.shareable, isNull);
  });
}
