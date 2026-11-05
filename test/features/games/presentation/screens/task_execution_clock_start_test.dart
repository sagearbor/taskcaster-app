
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
import 'package:taskcaster_app/features/games/domain/repositories/game_repository.dart';
import 'package:taskcaster_app/features/games/presentation/bloc/task_execution_bloc.dart';
import 'package:taskcaster_app/features/games/presentation/bloc/task_execution_event.dart';
import 'package:taskcaster_app/features/games/presentation/screens/task_execution_screen.dart';
import 'package:taskcaster_app/features/games/presentation/widgets/countdown_display.dart';
import 'package:taskcaster_app/features/games/presentation/widgets/task_countdown.dart';

class MockGameRepository extends Mock implements GameRepository {}

class FakeGame extends Fake implements Game {}

/// WP-05: on the first task a new player used to be LATE by design — the
/// cold-open tap started a 30 s clock before they had even found an egg. The
/// starter clock now starts when the camera (or keyboard) opens.
void main() {
  late MockGameRepository repo;
  late FakeVideoCapture videoCapture;
  late FakePhotoCapture photoCapture;

  setUpAll(() => registerFallbackValue(FakeGame()));

  Task notStartedTask(SubmissionType type) => Task(
        id: 'starter-09-v2',
        title: 'The face of someone who has just remembered the oven is on',
        description: 'Selfie video. Show us every layer of that realisation.',
        taskType: TaskType.video,
        submissionType: type,
        twist: 'No hands in the shot.',
        rubric: 'Number of distinct regrets visible.',
        durationSeconds: 30,
        submissions: const [],
        playerStatuses: const {
          'user1': PlayerTaskStatus(
            playerId: 'user1',
            state: TaskPlayerState.not_started,
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

  setUp(() async {
    await sl.reset();
    repo = MockGameRepository();
    // Cancelled pickers: the test is about WHEN the clock starts, not what
    // gets captured.
    videoCapture = FakeVideoCapture();
    photoCapture = FakePhotoCapture();
    sl.registerLazySingleton<VideoCapture>(() => videoCapture);
    sl.registerLazySingleton<PhotoCapture>(() => photoCapture);
    when(() => repo.updateGame(any(), any())).thenAnswer((_) async {});
  });

  Future<void> pump(
    WidgetTester tester,
    SubmissionType type, {
    bool autoStart = true,
  }) async {
    tester.view.physicalSize = const Size(500, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    when(() => repo.getGameStream('game1'))
        .thenAnswer((_) => Stream.value(gameWith(notStartedTask(type))));

    final bloc = TaskExecutionBloc(gameRepository: repo)
      ..add(const LoadTask(gameId: 'game1', taskIndex: 0, userId: 'user1'));
    addTearDown(bloc.close);

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<TaskExecutionBloc>.value(
          value: bloc,
          child: TaskExecutionView(
            gameId: 'game1',
            taskIndex: 0,
            userId: 'user1',
            autoStart: autoStart,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  PlayerTaskStatus stampedStatus() {
    final game = verify(() => repo.updateGame('game1', captureAny()))
        .captured
        .single as Game;
    return game.tasks.single.playerStatuses['user1']!;
  }

  testWidgets('autoStart lands on the task with the full clock, not counting',
      (tester) async {
    await pump(tester, SubmissionType.video);
    await tester.pump(const Duration(seconds: 3));

    final waiting = tester.widget<CountdownDisplay>(
        find.byKey(const Key('starter-clock-waiting')));
    expect(waiting.remainingSeconds, 30);
    expect(find.byType(TaskCountdown), findsNothing);
    expect(find.text('The clock starts when your camera opens.'),
        findsOneWidget);
    // The twist and the capture buttons are already there: no second Start.
    expect(find.text('No hands in the shot.'), findsOneWidget);
    expect(find.textContaining('Film it'), findsOneWidget);
    // Nothing was stamped.
    verifyNever(() => repo.updateGame(any(), any()));
  });

  testWidgets('Film it stamps startedAt as the camera opens', (tester) async {
    await pump(tester, SubmissionType.video);

    final before = DateTime.now();
    await tester.tap(find.textContaining('Film it'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(videoCapture.calls, hasLength(1));
    final status = stampedStatus();
    expect(status.state, TaskPlayerState.in_progress);
    expect(status.startedAt, isNotNull);
    expect(
      status.startedAt!.isBefore(before.subtract(const Duration(seconds: 1))),
      isFalse,
    );
  });

  testWidgets('Snap it also starts the clock', (tester) async {
    await pump(tester, SubmissionType.photo);

    await tester.tap(find.textContaining('Snap it'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(photoCapture.calls, [true]);
    expect(stampedStatus().state, TaskPlayerState.in_progress);
  });

  testWidgets('a text task starts the clock when the keyboard opens',
      (tester) async {
    await pump(tester, SubmissionType.text);

    expect(find.text('The clock starts when you start typing.'),
        findsOneWidget);
    verifyNever(() => repo.updateGame(any(), any()));

    await tester.tap(find.byType(TextField));
    await tester.pump(const Duration(milliseconds: 100));

    expect(stampedStatus().state, TaskPlayerState.in_progress);
  });

  testWidgets('without autoStart, Start on the reveal card does not start it',
      (tester) async {
    await pump(tester, SubmissionType.video, autoStart: false);

    expect(find.text('Start — 30 s'), findsOneWidget);
    await tester.tap(find.text('Start — 30 s'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const Key('starter-clock-waiting')), findsOneWidget);
    expect(find.textContaining('Film it'), findsOneWidget);
    verifyNever(() => repo.updateGame(any(), any()));
  });
}
