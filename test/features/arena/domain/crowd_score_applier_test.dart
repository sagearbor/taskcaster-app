import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:taskcaster_app/core/models/game.dart';
import 'package:taskcaster_app/core/models/game_settings.dart';
import 'package:taskcaster_app/core/models/player.dart';
import 'package:taskcaster_app/core/models/player_task_status.dart';
import 'package:taskcaster_app/core/models/submission.dart';
import 'package:taskcaster_app/core/models/task.dart';
import 'package:taskcaster_app/features/arena/data/datasources/mock_feed_data_source.dart';
import 'package:taskcaster_app/features/arena/data/repositories/feed_repository_impl.dart';
import 'package:taskcaster_app/features/arena/domain/crowd_score_applier.dart';
import 'package:taskcaster_app/features/arena/domain/models/feed_post.dart';
import 'package:taskcaster_app/features/games/domain/repositories/game_repository.dart';

class MockGameRepository extends Mock implements GameRepository {}

const creatorId = 'creator-1';

Task buildTask({
  required String id,
  required TaskPlayerState state,
  String? feedPostId,
}) {
  return Task(
    id: id,
    title: 'Task $id',
    description: 'Do the thing',
    taskType: TaskType.video,
    durationSeconds: 90,
    submissions: [
      if (feedPostId != null)
        Submission(
          id: 'sub-$id',
          userId: creatorId,
          score: 0,
          isJudged: state == TaskPlayerState.judged,
          submittedAt: DateTime.parse('2026-09-12T11:00:00.000Z'),
          mediaType: SubmissionMediaType.text,
          feedPostId: feedPostId,
        ),
    ],
    playerStatuses: {
      creatorId: PlayerTaskStatus(playerId: creatorId, state: state),
    },
  );
}

Game buildGame(List<Task> tasks) {
  return Game(
    id: 'game-1',
    gameName: 'Your First Ten',
    creatorId: creatorId,
    judgeId: creatorId,
    status: GameStatus.inProgress,
    inviteCode: 'ABC123',
    createdAt: DateTime.parse('2026-09-12T10:00:00.000Z'),
    players: const [
      Player(userId: creatorId, displayName: 'Alice', totalScore: 0),
    ],
    tasks: tasks,
    settings: const GameSettings(crowdJudged: true, shareToArena: true),
    gameKind: Game.kindStarter,
  );
}

Future<String> seedPost(
  FeedRepositoryImpl repo, {
  required String taskId,
  required List<int> grades,
  Duration age = Duration.zero,
}) async {
  final id = await repo.createPost(FeedPost(
    id: 'post-$taskId',
    gameId: 'game-1',
    taskId: taskId,
    taskTitle: 'Task $taskId',
    userId: creatorId,
    displayName: 'Alice',
    mediaType: SubmissionMediaType.text,
    text: 'An attempt',
    createdAt: DateTime.now().subtract(age),
  ));
  for (var i = 0; i < grades.length; i++) {
    await repo.gradePost(postId: id, graderId: 'grader-$i', score: grades[i]);
  }
  return id;
}

void main() {
  late MockGameRepository gameRepository;
  late MockFeedDataSource source;
  late FeedRepositoryImpl feedRepository;
  late CrowdScoreApplier applier;

  setUp(() {
    gameRepository = MockGameRepository();
    source = MockFeedDataSource();
    feedRepository = FeedRepositoryImpl(source);
    applier = CrowdScoreApplier(
      gameRepository: gameRepository,
      feedRepository: feedRepository,
    );
    when(() => gameRepository.judgeSubmission(any(), any(), any(), any()))
        .thenAnswer((_) async {});
  });

  tearDown(() => source.dispose());

  test('judges a task whose post has three grades', () async {
    await seedPost(feedRepository, taskId: 't1', grades: [5, 4, 5]);
    final game = buildGame([
      buildTask(
          id: 't1', state: TaskPlayerState.submitted, feedPostId: 'post-t1'),
    ]);

    expect(await applier.applyPending(game), 1);
    // mean 14/3 = 4.667 -> round(9.33) = 9
    verify(() => gameRepository.judgeSubmission('game-1', 0, creatorId, 9))
        .called(1);
  });

  test('judges a single-grade post once it is past the solo lock', () async {
    await seedPost(
      feedRepository,
      taskId: 't1',
      grades: [3],
      age: const Duration(minutes: 45),
    );
    final game = buildGame([
      buildTask(
          id: 't1', state: TaskPlayerState.submitted, feedPostId: 'post-t1'),
    ]);

    expect(await applier.applyPending(game), 1);
    verify(() => gameRepository.judgeSubmission('game-1', 0, creatorId, 6))
        .called(1);
  });

  test('leaves a fresh single-grade post alone', () async {
    await seedPost(feedRepository, taskId: 't1', grades: [3]);
    final game = buildGame([
      buildTask(
          id: 't1', state: TaskPlayerState.submitted, feedPostId: 'post-t1'),
    ]);

    expect(await applier.applyPending(game), 0);
    verifyNever(
        () => gameRepository.judgeSubmission(any(), any(), any(), any()));
  });

  test('leaves an ungraded post alone', () async {
    await seedPost(feedRepository, taskId: 't1', grades: const []);
    final game = buildGame([
      buildTask(
          id: 't1', state: TaskPlayerState.submitted, feedPostId: 'post-t1'),
    ]);

    expect(await applier.applyPending(game), 0);
    verifyNever(
        () => gameRepository.judgeSubmission(any(), any(), any(), any()));
  });

  test('never re-judges a task that is already judged', () async {
    await seedPost(feedRepository, taskId: 't1', grades: [5, 5, 5]);
    final game = buildGame([
      buildTask(id: 't1', state: TaskPlayerState.judged, feedPostId: 'post-t1'),
    ]);

    expect(await applier.applyPending(game), 0);
    verifyNever(
        () => gameRepository.judgeSubmission(any(), any(), any(), any()));
  });

  test('is one-shot: a second pass over the now-judged game does nothing',
      () async {
    await seedPost(feedRepository, taskId: 't1', grades: [4, 4, 4]);
    final pending = buildGame([
      buildTask(
          id: 't1', state: TaskPlayerState.submitted, feedPostId: 'post-t1'),
    ]);
    expect(await applier.applyPending(pending), 1);

    final judged = buildGame([
      buildTask(id: 't1', state: TaskPlayerState.judged, feedPostId: 'post-t1'),
    ]);
    expect(await applier.applyPending(judged), 0);
    verify(() => gameRepository.judgeSubmission(any(), any(), any(), any()))
        .called(1);
  });

  test('skips a task the player has not started', () async {
    final game = buildGame([
      buildTask(id: 't1', state: TaskPlayerState.not_started),
    ]);
    expect(await applier.applyPending(game), 0);
  });

  test('skips a submission with no Arena post behind it', () async {
    final game = buildGame([
      buildTask(id: 't1', state: TaskPlayerState.submitted),
    ]);
    expect(await applier.applyPending(game), 0);
  });

  test('skips a submission whose post has vanished', () async {
    final game = buildGame([
      buildTask(
          id: 't1', state: TaskPlayerState.submitted, feedPostId: 'gone'),
    ]);
    expect(await applier.applyPending(game), 0);
  });

  test('applies every ready task in one pass, by task index', () async {
    await seedPost(feedRepository, taskId: 't1', grades: [5, 5, 5]);
    await seedPost(feedRepository, taskId: 't2', grades: [1, 1, 1]);
    await seedPost(feedRepository, taskId: 't3', grades: const []);

    final game = buildGame([
      buildTask(
          id: 't1', state: TaskPlayerState.submitted, feedPostId: 'post-t1'),
      buildTask(
          id: 't2', state: TaskPlayerState.submitted, feedPostId: 'post-t2'),
      buildTask(
          id: 't3', state: TaskPlayerState.submitted, feedPostId: 'post-t3'),
    ]);

    expect(await applier.applyPending(game), 2);
    verify(() => gameRepository.judgeSubmission('game-1', 0, creatorId, 10))
        .called(1);
    verify(() => gameRepository.judgeSubmission('game-1', 1, creatorId, 2))
        .called(1);
  });
}
