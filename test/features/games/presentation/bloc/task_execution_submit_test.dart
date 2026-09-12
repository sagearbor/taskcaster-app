import 'dart:convert';
import 'dart:typed_data';

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
import 'package:taskcaster_app/features/arena/domain/models/feed_post.dart';
import 'package:taskcaster_app/features/games/domain/repositories/game_repository.dart';
import 'package:taskcaster_app/features/games/presentation/bloc/task_execution_bloc.dart';
import 'package:taskcaster_app/features/games/presentation/bloc/task_execution_event.dart';
import 'package:taskcaster_app/features/games/presentation/bloc/task_execution_state.dart';

class MockGameRepository extends Mock implements GameRepository {}

class FakeGame extends Fake implements Game {}

const userId = 'user-1';

Game buildGame({
  required PlayerTaskStatus status,
  int? durationSeconds = 90,
  bool shareToArena = true,
}) {
  return Game(
    id: 'game-1',
    gameName: 'Your First Ten',
    creatorId: userId,
    judgeId: userId,
    status: GameStatus.inProgress,
    inviteCode: 'ABC123',
    createdAt: DateTime.parse('2026-09-12T09:00:00.000Z'),
    players: const [
      Player(userId: userId, displayName: 'Alice', totalScore: 0),
    ],
    tasks: [
      Task(
        id: 'starter-01',
        title: 'A vegetable that has just received terrible news',
        description: 'Find a vegetable.',
        taskType: TaskType.video,
        submissionType: SubmissionType.photo,
        rubric: 'Emotional truth of the vegetable.',
        twist: 'No text on the vegetable.',
        durationSeconds: durationSeconds,
        submissions: const [],
        playerStatuses: {userId: status},
      ),
    ],
    settings: GameSettings(crowdJudged: true, shareToArena: shareToArena),
    gameKind: Game.kindStarter,
  );
}

PlayerTaskStatus startedSecondsAgo(int seconds) => PlayerTaskStatus(
      playerId: userId,
      state: TaskPlayerState.in_progress,
      startedAt: DateTime.now().subtract(Duration(seconds: seconds)),
    );

void main() {
  late MockGameRepository gameRepository;
  late MockFeedDataSource source;
  late FeedRepositoryImpl feedRepository;
  late TaskExecutionBloc bloc;
  late List<Game> written;

  setUpAll(() {
    registerFallbackValue(FakeGame());
  });

  setUp(() {
    gameRepository = MockGameRepository();
    source = MockFeedDataSource();
    feedRepository = FeedRepositoryImpl(source);
    written = [];
    when(() => gameRepository.updateGame(any(), any()))
        .thenAnswer((invocation) async {
      written.add(invocation.positionalArguments[1] as Game);
    });
  });

  tearDown(() async {
    await bloc.close();
    source.dispose();
  });

  /// Load the task (so the bloc is in TaskExecutionLoaded) and then submit.
  Future<TaskExecutionState> submit(
    Game game,
    SubmitTask event, {
    bool withFeed = true,
  }) async {
    when(() => gameRepository.getGameStream('game-1'))
        .thenAnswer((_) => Stream.value(game));
    bloc = TaskExecutionBloc(
      gameRepository: gameRepository,
      feedRepository: withFeed ? feedRepository : null,
    );
    bloc.add(const LoadTask(gameId: 'game-1', taskIndex: 0, userId: userId));
    await bloc.stream.firstWhere((s) => s is TaskExecutionLoaded);
    bloc.add(event);
    return bloc.stream.firstWhere(
      (s) => s is TaskExecutionSubmitted || s is TaskExecutionError,
    );
  }

  Task writtenTask() => written.last.tasks.first;
  Submission writtenSubmission() => writtenTask().submissions.single;
  PlayerTaskStatus writtenStatus() => writtenTask().playerStatuses[userId]!;

  group('photo submissions', () {
    test('post the photo to the Arena and stamp the submission', () async {
      final bytes = Uint8List.fromList(List.filled(64, 7));
      final state = await submit(
        buildGame(status: startedSecondsAgo(20)),
        SubmitTask(
          gameId: 'game-1',
          taskIndex: 0,
          userId: userId,
          photoBytes: bytes,
          displayName: 'Alice',
        ),
      ) as TaskExecutionSubmitted;

      expect(state.feedPostId, isNotNull);
      expect(state.isLate, isFalse);

      final post = await feedRepository.watchPost(state.feedPostId!).first;
      expect(post, isNotNull);
      expect(post!.mediaType, SubmissionMediaType.photo);
      expect(post.photoData, base64Encode(bytes));
      expect(post.taskId, 'starter-01');
      expect(post.taskTitle,
          'A vegetable that has just received terrible news');
      expect(post.rubric, 'Emotional truth of the vegetable.');
      expect(post.displayName, 'Alice');
      expect(post.userId, userId);
      // Well inside the first third of 90 s.
      expect(post.stamp, Stamps.nailedIt);
      expect(post.caption, contains('No text on the vegetable.'));
      expect(post.caption, contains('Done in'));
      expect(post.isLate, isFalse);
      expect(post.gradeCount, 0);
    });

    test('write a submission row carrying the post id', () async {
      final state = await submit(
        buildGame(status: startedSecondsAgo(20)),
        SubmitTask(
          gameId: 'game-1',
          taskIndex: 0,
          userId: userId,
          photoBytes: Uint8List.fromList(const [1, 2, 3]),
          displayName: 'Alice',
        ),
      ) as TaskExecutionSubmitted;

      final submission = writtenSubmission();
      expect(submission.userId, userId);
      expect(submission.mediaType, SubmissionMediaType.photo);
      expect(submission.feedPostId, state.feedPostId);
      expect(submission.stamp, Stamps.nailedIt);
      expect(submission.isJudged, isFalse);
      expect(submission.isLate, isFalse);
      expect(submission.elapsedSeconds, isNotNull);
    });

    test('stamp the player status submitted with an arena: marker', () async {
      final state = await submit(
        buildGame(status: startedSecondsAgo(20)),
        SubmitTask(
          gameId: 'game-1',
          taskIndex: 0,
          userId: userId,
          photoBytes: Uint8List.fromList(const [1, 2, 3]),
          displayName: 'Alice',
        ),
      ) as TaskExecutionSubmitted;

      final status = writtenStatus();
      expect(status.state, TaskPlayerState.submitted);
      expect(status.submissionUrl, 'arena:${state.feedPostId}');
      expect(status.submittedAt, isNotNull);
    });

    test('reject a photo that is too big to store inline', () async {
      // Well over the 400 KB base64 ceiling.
      final huge = Uint8List(500 * 1024);
      final state = await submit(
        buildGame(status: startedSecondsAgo(20)),
        SubmitTask(
          gameId: 'game-1',
          taskIndex: 0,
          userId: userId,
          photoBytes: huge,
          displayName: 'Alice',
        ),
      );

      expect(state, isA<TaskExecutionError>());
      expect((state as TaskExecutionError).message, contains('too big'));
      expect(written, isEmpty);
      expect(source.posts, isEmpty);
    });
  });

  group('text submissions', () {
    test('post the text with the ART stamp', () async {
      final state = await submit(
        buildGame(status: startedSecondsAgo(40)),
        const SubmitTask(
          gameId: 'game-1',
          taskIndex: 0,
          userId: userId,
          text: 'The lamp is now The Understudy.',
          displayName: 'Alice',
        ),
      ) as TaskExecutionSubmitted;

      final post = await feedRepository.watchPost(state.feedPostId!).first;
      expect(post!.mediaType, SubmissionMediaType.text);
      expect(post.text, 'The lamp is now The Understudy.');
      expect(post.photoData, isNull);
      expect(post.stamp, Stamps.art);
      expect(writtenSubmission().text, 'The lamp is now The Understudy.');
    });
  });

  group('late submissions', () {
    test('are flagged, stamped SEND HELP and captioned LATE', () async {
      // 90 s timer + 30 s grace = late from 120 s.
      final state = await submit(
        buildGame(status: startedSecondsAgo(140)),
        const SubmitTask(
          gameId: 'game-1',
          taskIndex: 0,
          userId: userId,
          text: 'Sorry.',
          displayName: 'Alice',
        ),
      ) as TaskExecutionSubmitted;

      expect(state.isLate, isTrue);
      final post = await feedRepository.watchPost(state.feedPostId!).first;
      expect(post!.isLate, isTrue);
      expect(post.stamp, Stamps.sendHelp);
      expect(post.caption, contains('LATE by'));
      expect(writtenSubmission().isLate, isTrue);
    });

    test('inside the 30 s grace are not late', () async {
      final state = await submit(
        buildGame(status: startedSecondsAgo(100)),
        const SubmitTask(
          gameId: 'game-1',
          taskIndex: 0,
          userId: userId,
          text: 'Just about.',
          displayName: 'Alice',
        ),
      ) as TaskExecutionSubmitted;

      expect(state.isLate, isFalse);
    });

    test('a task with no timer can never be late', () async {
      final state = await submit(
        buildGame(status: startedSecondsAgo(5000), durationSeconds: null),
        const SubmitTask(
          gameId: 'game-1',
          taskIndex: 0,
          userId: userId,
          text: 'Took my time.',
          displayName: 'Alice',
        ),
      ) as TaskExecutionSubmitted;

      expect(state.isLate, isFalse);
    });

    test('a player who never tapped Start has no elapsed time', () async {
      final state = await submit(
        buildGame(
          status: const PlayerTaskStatus(
            playerId: userId,
            state: TaskPlayerState.not_started,
          ),
        ),
        const SubmitTask(
          gameId: 'game-1',
          taskIndex: 0,
          userId: userId,
          text: 'Straight in.',
          displayName: 'Alice',
        ),
      ) as TaskExecutionSubmitted;

      expect(state.isLate, isFalse);
      expect(writtenSubmission().elapsedSeconds, isNull);
      final post = await feedRepository.watchPost(state.feedPostId!).first;
      expect(post!.elapsedSeconds, isNull);
      expect(post.caption, 'No text on the vegetable.');
    });
  });

  group('sharing', () {
    test('no post is created when the player opts out', () async {
      final state = await submit(
        buildGame(status: startedSecondsAgo(20)),
        const SubmitTask(
          gameId: 'game-1',
          taskIndex: 0,
          userId: userId,
          text: 'Private, this one.',
          shareToArena: false,
          displayName: 'Alice',
        ),
      ) as TaskExecutionSubmitted;

      expect(state.feedPostId, isNull);
      expect(source.posts, isEmpty);
      expect(writtenSubmission().feedPostId, isNull);
    });

    test('no post is created when the game does not share', () async {
      final state = await submit(
        buildGame(status: startedSecondsAgo(20), shareToArena: false),
        const SubmitTask(
          gameId: 'game-1',
          taskIndex: 0,
          userId: userId,
          text: 'Nope.',
          displayName: 'Alice',
        ),
      ) as TaskExecutionSubmitted;

      expect(state.feedPostId, isNull);
      expect(source.posts, isEmpty);
    });

    test('no post is created when no Arena is wired up at all', () async {
      final state = await submit(
        buildGame(status: startedSecondsAgo(20)),
        const SubmitTask(
          gameId: 'game-1',
          taskIndex: 0,
          userId: userId,
          videoUrl: 'https://youtu.be/abc',
          displayName: 'Alice',
        ),
        withFeed: false,
      ) as TaskExecutionSubmitted;

      expect(state.feedPostId, isNull);
      expect(source.posts, isEmpty);
    });

    test('posting is what unlocks the task for the viewer', () async {
      await submit(
        buildGame(status: startedSecondsAgo(20)),
        const SubmitTask(
          gameId: 'game-1',
          taskIndex: 0,
          userId: userId,
          text: 'Mine.',
          displayName: 'Alice',
        ),
      );

      expect(
        await feedRepository.watchUnlockedTaskIds(userId).first,
        {'starter-01'},
      );
    });
  });

  group('the legacy video-link path', () {
    test('still submits with the url as the submission url', () async {
      final state = await submit(
        buildGame(status: startedSecondsAgo(20)),
        const SubmitTask(
          gameId: 'game-1',
          taskIndex: 0,
          userId: userId,
          videoUrl: 'https://youtu.be/abc',
          displayName: 'Alice',
        ),
      ) as TaskExecutionSubmitted;

      expect(writtenStatus().state, TaskPlayerState.submitted);
      expect(writtenStatus().submissionUrl, 'https://youtu.be/abc');
      expect(writtenSubmission().mediaType, SubmissionMediaType.link);
      expect(writtenSubmission().videoUrl, 'https://youtu.be/abc');
      expect(state.feedPostId, isNotNull);
    });

    test('moves the task to ready_to_judge once everybody has handed in',
        () async {
      await submit(
        buildGame(status: startedSecondsAgo(20)),
        const SubmitTask(
          gameId: 'game-1',
          taskIndex: 0,
          userId: userId,
          videoUrl: 'https://youtu.be/abc',
          displayName: 'Alice',
        ),
      );
      expect(writtenTask().status, TaskStatus.ready_to_judge);
    });
  });
}
