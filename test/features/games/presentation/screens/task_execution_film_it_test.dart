import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:taskcaster_app/core/di/service_locator.dart';
import 'package:taskcaster_app/core/models/game.dart';
import 'package:taskcaster_app/core/models/game_settings.dart';
import 'package:taskcaster_app/core/models/player.dart';
import 'package:taskcaster_app/core/models/player_task_status.dart';
import 'package:taskcaster_app/core/models/task.dart';
import 'package:taskcaster_app/core/services/photo/photo_capture.dart';
import 'package:taskcaster_app/core/services/video/video_capture.dart';
import 'package:taskcaster_app/core/services/video/video_uploader.dart';
import 'package:taskcaster_app/features/arena/data/datasources/mock_feed_data_source.dart';
import 'package:taskcaster_app/features/arena/data/repositories/feed_repository_impl.dart';
import 'package:taskcaster_app/features/arena/domain/repositories/feed_repository.dart';
import 'package:taskcaster_app/core/models/user.dart';
import 'package:taskcaster_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:taskcaster_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:taskcaster_app/features/games/domain/repositories/game_repository.dart';
import 'package:taskcaster_app/features/games/presentation/bloc/task_execution_bloc.dart';
import 'package:taskcaster_app/features/games/presentation/bloc/task_execution_event.dart';
import 'package:taskcaster_app/features/games/presentation/bloc/task_execution_state.dart';
import 'package:taskcaster_app/features/games/presentation/screens/task_execution_screen.dart';
import 'package:taskcaster_app/features/games/presentation/widgets/clip_preview.dart';

import '../../../../helpers/fake_video_player_platform.dart';

class MockGameRepository extends Mock implements GameRepository {}

class MockAuthRepository extends Mock implements AuthRepository {}

class FakeGame extends Fake implements Game {}

class MockTaskExecutionBloc
    extends MockBloc<TaskExecutionEvent, TaskExecutionState>
    implements TaskExecutionBloc {}

Task starterTask({
  required SubmissionType submissionType,
  int durationSeconds = 30,
}) =>
    Task(
      id: 'starter-01',
      title: 'Egg on a spoon, to the far wall and back',
      description: 'Put an egg on a spoon and walk to the far wall.',
      taskType: TaskType.video,
      submissionType: submissionType,
      twist: 'You must narrate it like a nature documentary.',
      rubric: 'Distance covered before disaster.',
      durationSeconds: durationSeconds,
      submissions: const [],
      playerStatuses: {
        'user1': PlayerTaskStatus(
          playerId: 'user1',
          state: TaskPlayerState.in_progress,
          startedAt: DateTime.now().subtract(const Duration(seconds: 6)),
        ),
      },
    );

Game gameWith(Task task) => Game(
      id: 'game1',
      gameName: 'Your First Ten',
      creatorId: 'user1',
      judgeId: 'user1',
      status: GameStatus.inProgress,
      inviteCode: 'ABC123',
      createdAt: DateTime.now(),
      gameKind: Game.kindStarter,
      players: const [
        Player(userId: 'user1', displayName: 'Alice', totalScore: 0),
      ],
      tasks: [task],
      settings: const GameSettings(crowdJudged: true, shareToArena: true),
    );

PickedVideo fakeClip() => PickedVideo(
      bytes: Uint8List.fromList(List.filled(512, 4)),
      contentType: 'video/quicktime',
      fileName: 'IMG_0001.MOV',
      sourcePath: '/tmp/IMG_0001.MOV',
    );

void main() {
  late MockGameRepository gameRepository;
  late FakeVideoCapture videoCapture;
  late FakeVideoUploader uploader;
  late MockFeedDataSource feedSource;
  late AuthBloc authBloc;

  setUpAll(() => registerFallbackValue(FakeGame()));

  setUp(() async {
    await sl.reset();
    FakeVideoPlayerPlatform.install();
    gameRepository = MockGameRepository();
    videoCapture = FakeVideoCapture(fakeClip());
    uploader = FakeVideoUploader();
    feedSource = MockFeedDataSource();

    sl.registerLazySingleton<VideoCapture>(() => videoCapture);
    sl.registerLazySingleton<VideoUploader>(() => uploader);
    sl.registerLazySingleton<PhotoCapture>(() => FakePhotoCapture());
    // Posting lands on PostedScreen, which reads these off the locator.
    sl.registerLazySingleton<GameRepository>(() => gameRepository);
    sl.registerLazySingleton<FeedRepository>(
      () => FeedRepositoryImpl(feedSource),
    );

    when(() => gameRepository.updateGame(any(), any()))
        .thenAnswer((_) async {});

    final authRepository = MockAuthRepository();
    when(() => authRepository.getCurrentUser()).thenAnswer((_) async => User(
          id: 'user1',
          displayName: 'Alice',
          createdAt: DateTime(2026, 1, 1),
        ));
    authBloc = AuthBloc(authRepository: authRepository)
      ..add(AuthCheckRequested());
  });

  tearDown(() async {
    feedSource.dispose();
    await authBloc.close();
  });

  Future<TaskExecutionBloc> pumpStartedTask(
    WidgetTester tester,
    Task task,
  ) async {
    // A tall surface so the preview and the Retake / Post it row are both on
    // screen; tester.tap only warns when it misses.
    tester.view.physicalSize = const Size(500, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    when(() => gameRepository.getGameStream('game1'))
        .thenAnswer((_) => Stream.value(gameWith(task)));

    final bloc = TaskExecutionBloc(
      gameRepository: gameRepository,
      feedRepository: FeedRepositoryImpl(feedSource),
      videoUploader: uploader,
    )..add(const LoadTask(gameId: 'game1', taskIndex: 0, userId: 'user1'));
    addTearDown(bloc.close);

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<AuthBloc>.value(value: authBloc),
            BlocProvider<TaskExecutionBloc>.value(value: bloc),
          ],
          child: const TaskExecutionView(
            gameId: 'game1',
            taskIndex: 0,
            userId: 'user1',
          ),
        ),
      ),
    );
    // The countdown ticks every second, so never pumpAndSettle here.
    await tester.pump(const Duration(milliseconds: 100));
    return bloc;
  }

  testWidgets('a video task leads with Film it and offers Snap it too',
      (tester) async {
    await pumpStartedTask(tester, starterTask(
      submissionType: SubmissionType.video,
    ));

    expect(find.textContaining('Film it'), findsOneWidget);
    expect(find.textContaining('Snap it'), findsOneWidget);
    // The cap is shown so the player knows how long they get.
    expect(find.text('up to 30 s'), findsOneWidget);
  });

  testWidgets('a photo task also leads with Film it — video is the default',
      (tester) async {
    await pumpStartedTask(tester, starterTask(
      submissionType: SubmissionType.photo,
      durationSeconds: 120,
    ));

    expect(find.textContaining('Film it'), findsOneWidget);
    expect(find.textContaining('Snap it'), findsOneWidget);
    // min(task timer, 30 s): a 120 s task still only gets a 30 s clip.
    expect(find.text('up to 30 s'), findsOneWidget);
  });

  testWidgets('a short task shortens the clip cap', (tester) async {
    await pumpStartedTask(tester, starterTask(
      submissionType: SubmissionType.video,
      durationSeconds: 20,
    ));
    expect(find.text('up to 20 s'), findsOneWidget);
  });

  testWidgets('a text task shows Write it and neither camera button',
      (tester) async {
    await pumpStartedTask(tester, starterTask(
      submissionType: SubmissionType.text,
      durationSeconds: 60,
    ));

    expect(find.textContaining('Write it'), findsOneWidget);
    expect(find.textContaining('Film it'), findsNothing);
    expect(find.textContaining('Snap it'), findsNothing);
  });

  testWidgets('Film it records with the cap and shows Retake / Post it',
      (tester) async {
    await pumpStartedTask(tester, starterTask(
      submissionType: SubmissionType.video,
    ));

    await tester.tap(find.textContaining('Film it'));
    await tester.pump();
    await tester.pump();

    // The recorder's own maxDuration IS the trim.
    expect(videoCapture.calls.single.fromCamera, isTrue);
    expect(videoCapture.calls.single.maxSeconds, 30);

    expect(find.byType(ClipPreview), findsOneWidget);
    expect(find.text('Retake'), findsOneWidget);
    expect(find.text('Post it'), findsOneWidget);
    // No manual edit UI, ever.
    expect(find.byType(Slider), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('Retake clears the clip and brings the buttons back',
      (tester) async {
    await pumpStartedTask(tester, starterTask(
      submissionType: SubmissionType.video,
    ));

    await tester.tap(find.textContaining('Film it'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Retake'));
    await tester.pump();

    expect(find.byType(ClipPreview), findsNothing);
    expect(find.textContaining('Film it'), findsOneWidget);
  });

  testWidgets('Post it uploads the clip with the task-clock offset',
      (tester) async {
    await pumpStartedTask(tester, starterTask(
      submissionType: SubmissionType.video,
      durationSeconds: 60,
    ));

    await tester.tap(find.textContaining('Film it'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Post it'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(uploader.calls, hasLength(1));
    final metadata = uploader.calls.single.metadata!;
    expect(metadata['taskId'], 'starter-01');
    expect(metadata['timerSeconds'], '60');
    // Started ~6 s ago, so the recorder opened ~6 s into the task clock.
    expect(int.parse(metadata['clockOffsetSeconds']!), inInclusiveRange(5, 9));
  });

  testWidgets('a cancelled recording leaves the buttons alone', (tester) async {
    await sl.reset();
    FakeVideoPlayerPlatform.install();
    videoCapture = FakeVideoCapture(); // null = the player backed out
    sl.registerLazySingleton<VideoCapture>(() => videoCapture);
    sl.registerLazySingleton<VideoUploader>(() => uploader);
    sl.registerLazySingleton<PhotoCapture>(() => FakePhotoCapture());
    sl.registerLazySingleton<GameRepository>(() => gameRepository);
    sl.registerLazySingleton<FeedRepository>(
      () => FeedRepositoryImpl(feedSource),
    );

    await pumpStartedTask(tester, starterTask(
      submissionType: SubmissionType.video,
    ));

    await tester.tap(find.textContaining('Film it'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(ClipPreview), findsNothing);
    expect(find.textContaining('Film it'), findsOneWidget);
  });

  group('the uploading screen', () {
    testWidgets('shows a progress bar, a percentage and dead buttons',
        (tester) async {
      final bloc = MockTaskExecutionBloc();
      whenListen(
        bloc,
        const Stream<TaskExecutionState>.empty(),
        initialState: TaskExecutionUploading(
          progress: 0.42,
          task: starterTask(submissionType: SubmissionType.video),
        ),
      );
      addTearDown(bloc.close);

      await tester.pumpWidget(
        MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<AuthBloc>.value(value: authBloc),
              BlocProvider<TaskExecutionBloc>.value(value: bloc),
            ],
            child: const TaskExecutionView(
              gameId: 'game1',
              taskIndex: 0,
              userId: 'user1',
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Uploading… 42%'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byKey(const Key('clip-upload-progress')),
      );
      expect(bar.value, closeTo(0.42, 0.001));

      // Nothing is tappable mid-upload: the player has already committed.
      expect(
        tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Retake')).onPressed,
        isNull,
      );
      expect(
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Post it')).onPressed,
        isNull,
      );
    });
  });
}
