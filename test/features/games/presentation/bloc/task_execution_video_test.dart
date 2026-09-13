import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:taskcaster_app/core/models/game.dart';
import 'package:taskcaster_app/core/models/game_settings.dart';
import 'package:taskcaster_app/core/models/player.dart';
import 'package:taskcaster_app/core/models/player_task_status.dart';
import 'package:taskcaster_app/core/models/submission.dart';
import 'package:taskcaster_app/core/models/task.dart';
import 'package:taskcaster_app/core/services/video/video_capture.dart';
import 'package:taskcaster_app/core/services/video/video_policy.dart';
import 'package:taskcaster_app/core/services/video/video_uploader.dart';
import 'package:taskcaster_app/features/arena/data/datasources/mock_feed_data_source.dart';
import 'package:taskcaster_app/features/arena/data/repositories/feed_repository_impl.dart';
import 'package:taskcaster_app/features/games/domain/repositories/game_repository.dart';
import 'package:taskcaster_app/features/games/presentation/bloc/task_execution_bloc.dart';
import 'package:taskcaster_app/features/games/presentation/bloc/task_execution_event.dart';
import 'package:taskcaster_app/features/games/presentation/bloc/task_execution_state.dart';

class MockGameRepository extends Mock implements GameRepository {}

class FakeGame extends Fake implements Game {}

const userId = 'user-1';

Game buildGame({
  required PlayerTaskStatus status,
  int? durationSeconds = 30,
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
        title: 'Egg on a spoon, to the far wall and back',
        description: 'Put an egg on a spoon.',
        taskType: TaskType.video,
        submissionType: SubmissionType.video,
        rubric: 'Distance covered before disaster, then narration.',
        twist: 'You must narrate it like a nature documentary.',
        durationSeconds: durationSeconds,
        submissions: const [],
        playerStatuses: {userId: status},
      ),
    ],
    settings: const GameSettings(crowdJudged: true, shareToArena: true),
    gameKind: Game.kindStarter,
  );
}

PlayerTaskStatus startedSecondsAgo(int seconds) => PlayerTaskStatus(
      playerId: userId,
      state: TaskPlayerState.in_progress,
      startedAt: DateTime.now().subtract(Duration(seconds: seconds)),
    );

PickedVideo clipOf(int bytes) => PickedVideo(
      bytes: Uint8List.fromList(List.filled(bytes, 9)),
      contentType: 'video/quicktime',
      fileName: 'IMG_0001.MOV',
      sourcePath: '/tmp/IMG_0001.MOV',
    );

void main() {
  late MockGameRepository gameRepository;
  late MockFeedDataSource source;
  late FeedRepositoryImpl feedRepository;
  late TaskExecutionBloc bloc;
  late List<Game> written;

  setUpAll(() => registerFallbackValue(FakeGame()));

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

  /// Loads the task, submits [event] and returns every state the submit
  /// produced (so progress emissions can be asserted).
  Future<List<TaskExecutionState>> submit(
    Game game,
    SubmitTask event, {
    VideoUploader? uploader,
  }) async {
    when(() => gameRepository.getGameStream('game-1'))
        .thenAnswer((_) => Stream.value(game));
    bloc = TaskExecutionBloc(
      gameRepository: gameRepository,
      feedRepository: feedRepository,
      videoUploader: uploader,
    );
    bloc.add(const LoadTask(gameId: 'game-1', taskIndex: 0, userId: userId));
    await bloc.stream.firstWhere((s) => s is TaskExecutionLoaded);

    final seen = <TaskExecutionState>[];
    final sub = bloc.stream.listen(seen.add);
    bloc.add(event);
    await bloc.stream.firstWhere(
      (s) => s is TaskExecutionSubmitted || s is TaskExecutionError,
    );
    await sub.cancel();
    return seen;
  }

  group('video submissions', () {
    test('upload, then a video post and a mirrored submission', () async {
      final uploader = FakeVideoUploader(
        result: const VideoUploadResult(
          downloadUrl: 'https://cdn.test/submissions/user-1/20260912/2',
          storagePath: 'submissions/user-1/20260912/2',
          bytes: 3 * 1024 * 1024,
        ),
      );

      final states = await submit(
        buildGame(status: startedSecondsAgo(6)),
        SubmitTask(
          gameId: 'game-1',
          taskIndex: 0,
          userId: userId,
          video: clipOf(1024),
          clockOffsetSeconds: 4,
          displayName: 'Alice',
        ),
        uploader: uploader,
      );

      final done = states.last as TaskExecutionSubmitted;
      expect(done.feedPostId, isNotNull);

      final post = (await feedRepository.watchPost(done.feedPostId!).first)!;
      expect(post.mediaType, SubmissionMediaType.video);
      expect(post.videoUrl, 'https://cdn.test/submissions/user-1/20260912/2');
      expect(post.videoStoragePath, 'submissions/user-1/20260912/2');
      expect(post.videoBytes, 3 * 1024 * 1024);
      expect(post.videoContentType, 'video/quicktime');
      // Never known at upload time; playback trims at the cap regardless.
      expect(post.videoDurationSeconds, isNull);
      expect(post.clockOffsetSeconds, 4);
      expect(post.timerSeconds, 30);
      // Auto-edit runs exactly as it does for a photo.
      expect(post.caption, contains('nature documentary'));
      expect(post.caption, contains('Done in'));
      expect(post.stamp, isNotNull);
      expect(post.isLate, isFalse);
      expect(post.photoData, isNull);

      final submission = written.last.tasks.first.submissions.single;
      expect(submission.mediaType, SubmissionMediaType.video);
      expect(submission.videoUrl, post.videoUrl);
      expect(submission.videoStoragePath, post.videoStoragePath);
      expect(submission.videoBytes, post.videoBytes);
      expect(submission.videoContentType, 'video/quicktime');
      expect(submission.clockOffsetSeconds, 4);
      expect(submission.timerSeconds, 30);
      expect(submission.feedPostId, done.feedPostId);
    });

    test('carries the splice metadata to Storage', () async {
      final uploader = FakeVideoUploader();
      await submit(
        buildGame(status: startedSecondsAgo(11), durationSeconds: 60),
        SubmitTask(
          gameId: 'game-1',
          taskIndex: 0,
          userId: userId,
          video: clipOf(2048),
          clockOffsetSeconds: 9,
          displayName: 'Alice',
        ),
        uploader: uploader,
      );

      final call = uploader.calls.single;
      expect(call.userId, userId);
      expect(call.bytes, 2048);
      expect(call.contentType, 'video/quicktime');
      expect(call.metadata, containsPair('gameId', 'game-1'));
      expect(call.metadata, containsPair('taskId', 'starter-01'));
      expect(call.metadata, containsPair('userId', userId));
      expect(call.metadata, containsPair('timerSeconds', '60'));
      expect(call.metadata, containsPair('clockOffsetSeconds', '9'));
      expect(call.metadata, containsPair('isLate', 'false'));
      expect(call.metadata, containsPair('clipCapSeconds', '30'));
      expect(call.metadata!['elapsedSeconds'], isNotNull);
    });

    test('emits upload progress before the submitted state', () async {
      final states = await submit(
        buildGame(status: startedSecondsAgo(3)),
        SubmitTask(
          gameId: 'game-1',
          taskIndex: 0,
          userId: userId,
          video: clipOf(512),
          displayName: 'Alice',
        ),
        uploader: FakeVideoUploader(
          progressTicks: const [0.01, 0.02, 0.4, 0.9],
        ),
      );

      final uploading = states.whereType<TaskExecutionUploading>().toList();
      // Starts at 0, throttled to ~5 % steps (0.01 and 0.02 are swallowed),
      // and always ends on 1.0.
      expect(uploading.first.progress, 0);
      expect(
        uploading.map((s) => s.progress).toList(),
        [0.0, 0.4, 0.9, 1.0],
      );
      expect(uploading.last.percent, 100);
      expect(uploading.first.task.id, 'starter-01');
      expect(states.last, isA<TaskExecutionSubmitted>());
    });

    test('refuses an over-size clip before uploading anything', () async {
      final uploader = FakeVideoUploader();
      final states = await submit(
        buildGame(status: startedSecondsAgo(3)),
        SubmitTask(
          gameId: 'game-1',
          taskIndex: 0,
          userId: userId,
          video: clipOf(VideoPolicy.maxUploadBytes + 1),
          displayName: 'Alice',
        ),
        uploader: uploader,
      );

      final error = states.last as TaskExecutionError;
      expect(error.message, contains('too big'));
      expect(uploader.calls, isEmpty);
      expect(written, isEmpty);
      expect(states.whereType<TaskExecutionUploading>(), isEmpty);
    });

    test('an empty clip is refused too', () async {
      final states = await submit(
        buildGame(status: startedSecondsAgo(3)),
        SubmitTask(
          gameId: 'game-1',
          taskIndex: 0,
          userId: userId,
          video: clipOf(0),
          displayName: 'Alice',
        ),
        uploader: FakeVideoUploader(),
      );
      expect((states.last as TaskExecutionError).message, contains('empty'));
    });

    test('the daily cap surfaces its own player-facing message', () async {
      final states = await submit(
        buildGame(status: startedSecondsAgo(3)),
        SubmitTask(
          gameId: 'game-1',
          taskIndex: 0,
          userId: userId,
          video: clipOf(1024),
          displayName: 'Alice',
        ),
        uploader: FakeVideoUploader(error: const DailyVideoLimitReached()),
      );

      final error = states.last as TaskExecutionError;
      expect(error.message, contains('clips today'));
      expect(error.message, contains('snap a photo'));
      expect(written, isEmpty);
    });

    test('any other upload failure gets the friendly fallback', () async {
      final states = await submit(
        buildGame(status: startedSecondsAgo(3)),
        SubmitTask(
          gameId: 'game-1',
          taskIndex: 0,
          userId: userId,
          video: clipOf(1024),
          displayName: 'Alice',
        ),
        uploader: FakeVideoUploader(error: Exception('the bucket is asleep')),
      );

      final error = states.last as TaskExecutionError;
      expect(error.message, isNot(contains('asleep')));
      expect(error.message, isNotEmpty);
      expect(written, isEmpty);
    });

    test('a clip with no uploader wired up fails politely', () async {
      final states = await submit(
        buildGame(status: startedSecondsAgo(3)),
        SubmitTask(
          gameId: 'game-1',
          taskIndex: 0,
          userId: userId,
          video: clipOf(1024),
          displayName: 'Alice',
        ),
      );
      expect(
        (states.last as TaskExecutionError).message,
        contains('snap a photo'),
      );
    });

    test('a late clip is flagged LATE and keeps its clock metadata', () async {
      final states = await submit(
        // 30 s timer + 30 s grace, so 75 s in is late.
        buildGame(status: startedSecondsAgo(75)),
        SubmitTask(
          gameId: 'game-1',
          taskIndex: 0,
          userId: userId,
          video: clipOf(1024),
          clockOffsetSeconds: 70,
          displayName: 'Alice',
        ),
        uploader: FakeVideoUploader(),
      );

      final done = states.last as TaskExecutionSubmitted;
      expect(done.isLate, isTrue);
      final post = (await feedRepository.watchPost(done.feedPostId!).first)!;
      expect(post.isLate, isTrue);
      expect(post.clockOffsetSeconds, 70);
      expect(post.timerSeconds, 30);
    });
  });

  group('the photo and text paths are untouched by the video branch', () {
    test('a photo submission emits no upload state and no clip fields',
        () async {
      final uploader = FakeVideoUploader();
      final states = await submit(
        buildGame(status: startedSecondsAgo(5)),
        SubmitTask(
          gameId: 'game-1',
          taskIndex: 0,
          userId: userId,
          photoBytes: Uint8List.fromList(List.filled(64, 3)),
          displayName: 'Alice',
        ),
        uploader: uploader,
      );

      expect(states.whereType<TaskExecutionUploading>(), isEmpty);
      expect(uploader.calls, isEmpty);

      final done = states.last as TaskExecutionSubmitted;
      final post = (await feedRepository.watchPost(done.feedPostId!).first)!;
      expect(post.mediaType, SubmissionMediaType.photo);
      expect(post.photoData, isNotNull);
      expect(post.videoUrl, isNull);
      expect(post.videoStoragePath, isNull);
      expect(post.clockOffsetSeconds, isNull);
      expect(post.timerSeconds, isNull);

      final submission = written.last.tasks.first.submissions.single;
      expect(submission.videoStoragePath, isNull);
      expect(submission.clockOffsetSeconds, isNull);
      expect(submission.timerSeconds, isNull);
    });

    test('a text submission still posts text only', () async {
      final uploader = FakeVideoUploader();
      final states = await submit(
        buildGame(status: startedSecondsAgo(5)),
        const SubmitTask(
          gameId: 'game-1',
          taskIndex: 0,
          userId: userId,
          text: 'A very sad potato.',
          displayName: 'Alice',
        ),
        uploader: uploader,
      );

      expect(states.whereType<TaskExecutionUploading>(), isEmpty);
      expect(uploader.calls, isEmpty);

      final done = states.last as TaskExecutionSubmitted;
      final post = (await feedRepository.watchPost(done.feedPostId!).first)!;
      expect(post.mediaType, SubmissionMediaType.text);
      expect(post.text, 'A very sad potato.');
      expect(post.videoUrl, isNull);
    });
  });
}
