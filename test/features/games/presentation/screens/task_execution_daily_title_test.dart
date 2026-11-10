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
import 'package:taskcaster_app/core/models/submission.dart';
import 'package:taskcaster_app/core/models/user.dart';
import 'package:taskcaster_app/features/arena/domain/models/feed_post.dart';
import 'package:taskcaster_app/features/arena/domain/repositories/feed_repository.dart';
import 'package:taskcaster_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:taskcaster_app/features/games/domain/repositories/game_repository.dart';
import 'package:taskcaster_app/features/games/presentation/bloc/task_execution_bloc.dart';
import 'package:taskcaster_app/features/games/presentation/bloc/task_execution_event.dart';
import 'package:taskcaster_app/features/games/presentation/screens/task_execution_screen.dart';
import 'package:taskcaster_app/features/tasks/data/datasources/daily_task_data.dart';

class MockGameRepository extends Mock implements GameRepository {}

class MockFeedRepository extends Mock implements FeedRepository {}

class MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

class FakeGame extends Fake implements Game {}

/// Integration pass: a daily game has one task, so its app bar says "Today's
/// task" (never "Task 1 of 1") and carries the 🔥 streak chip.
void main() {
  late MockGameRepository gameRepo;

  setUpAll(() => registerFallbackValue(FakeGame()));
  setUp(() async {
    await sl.reset();
    gameRepo = MockGameRepository();
  });
  tearDown(() async => sl.reset());

  Game game({required bool daily}) {
    final task = daily
        ? DailyTaskData.tasks()[1]
        : DailyTaskData.tasks()[1].copyWith(id: 'friend-1');
    return Game(
      id: 'g1',
      gameName: daily ? 'Daily task, 9 Nov' : 'Friends',
      creatorId: 'user1',
      judgeId: 'user1',
      status: GameStatus.inProgress,
      inviteCode: 'ABC123',
      createdAt: DateTime.now(),
      gameKind: daily ? Game.kindDaily : null,
      players: const [
        Player(userId: 'user1', displayName: 'Alice', totalScore: 0),
      ],
      tasks: [
        task.copyWith(playerStatuses: {
          'user1': const PlayerTaskStatus(
            playerId: 'user1',
            state: TaskPlayerState.not_started,
          ),
        }),
      ],
      settings: const GameSettings(crowdJudged: true, shareToArena: true),
    );
  }

  Future<void> pump(WidgetTester tester, Game g,
      {Size size = const Size(360, 640), AuthBloc? auth}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    when(() => gameRepo.getGameStream('g1'))
        .thenAnswer((_) => Stream.value(g));
    Widget child = MaterialApp(
      home: BlocProvider(
        create: (_) => TaskExecutionBloc(gameRepository: gameRepo)
          ..add(const LoadTask(gameId: 'g1', taskIndex: 0, userId: 'user1')),
        child:
            const TaskExecutionView(gameId: 'g1', taskIndex: 0, userId: 'user1'),
      ),
    );
    if (auth != null) {
      child = BlocProvider<AuthBloc>.value(value: auth, child: child);
    }
    await tester.pumpWidget(child);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets("a daily game says Today's task, not Task 1 of 1, at 360x640",
      (tester) async {
    await pump(tester, game(daily: true));
    expect(find.text("Today's task"), findsOneWidget);
    expect(find.text('Task 1 of 1'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('any other one-task game keeps Task 1 of 1', (tester) async {
    await pump(tester, game(daily: false));
    expect(find.text('Task 1 of 1'), findsOneWidget);
    expect(find.text("Today's task"), findsNothing);
  });

  testWidgets('the streak chip sits beside the title', (tester) async {
    final feed = MockFeedRepository();
    sl.registerSingleton<FeedRepository>(feed);
    final now = DateTime.now();
    FeedPost mine(int daysAgo) => FeedPost(
          id: 'p$daysAgo',
          gameId: 'x',
          taskId: 'starter-01',
          taskTitle: 't',
          rubric: 'r',
          userId: 'user1',
          displayName: 'Alice',
          mediaType: SubmissionMediaType.text,
          text: 'hi',
          createdAt: now.subtract(Duration(days: daysAgo)),
        );
    when(() => feed.watchPostsByUser('user1'))
        .thenAnswer((_) => Stream.value([mine(0), mine(1), mine(2)]));

    final auth = MockAuthBloc();
    whenListen(
      auth,
      const Stream<AuthState>.empty(),
      initialState: AuthAuthenticated(
        user: User(
          id: 'user1',
          displayName: 'Alice',
          createdAt: DateTime(2026, 1, 1),
        ),
      ),
    );

    await pump(tester, game(daily: true), auth: auth);
    await tester.pump();
    expect(find.text('🔥 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
