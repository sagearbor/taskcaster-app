// Golden tests for the game screen states (WP-10): lobby, in progress (your
// turn), waiting on others, and completed — each in light and dark at a
// 390x844 phone viewport, rendered with the real bundled fonts so the
// images double as design review screenshots.
//
// Regenerate after an intentional visual change:
//   flutter test --update-goldens test/features/games/presentation/goldens/
//
// The images are rendered on macOS (where the owner runs the suite); font
// rasterisation differs slightly on other platforms, so the comparison is
// skipped there rather than failing on anti-aliasing noise.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:taskcaster_app/core/di/service_locator.dart';
import 'package:taskcaster_app/core/models/game.dart';
import 'package:taskcaster_app/core/models/game_settings.dart';
import 'package:taskcaster_app/core/models/player.dart';
import 'package:taskcaster_app/core/models/player_task_status.dart';
import 'package:taskcaster_app/core/models/task.dart';
import 'package:taskcaster_app/core/models/user.dart';
import 'package:taskcaster_app/core/theme/app_theme.dart';
import 'package:taskcaster_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:taskcaster_app/features/friends/data/repositories/mock_friends_repository.dart';
import 'package:taskcaster_app/features/friends/domain/repositories/friends_repository.dart';
import 'package:taskcaster_app/features/games/presentation/widgets/game_completed_view.dart';
import 'package:taskcaster_app/features/games/presentation/widgets/game_in_progress_view.dart';
import 'package:taskcaster_app/features/games/presentation/widgets/game_lobby_view.dart';

class _MockAuthBloc extends Mock implements AuthBloc {}

const _me = 'me';

final _players = const [
  Player(userId: _me, displayName: 'Sage', totalScore: 7),
  Player(userId: 'p2', displayName: 'Greg', totalScore: 9),
  Player(userId: 'p3', displayName: 'Priya', totalScore: 4),
  Player(userId: 'p4', displayName: 'Wanda', totalScore: 6),
];

Task _task(String id, String title,
        {Map<String, PlayerTaskStatus> statuses = const {},
        TaskStatus status = TaskStatus.waiting_for_submissions,
        int? seconds = 45}) =>
    Task(
      id: id,
      title: title,
      description: 'Pick any topic and talk fluently. One slip and you start '
          'again.',
      taskType: TaskType.video,
      submissions: const [],
      status: status,
      playerStatuses: statuses,
      durationSeconds: seconds,
    );

Map<String, PlayerTaskStatus> _all(TaskPlayerState s,
        {Map<String, TaskPlayerState> except = const {}}) =>
    {
      for (final p in _players)
        p.userId: PlayerTaskStatus(
            playerId: p.userId, state: except[p.userId] ?? s),
    };

Game _game(GameStatus status, List<Task> tasks, {int current = 1}) => Game(
      id: 'g1',
      gameName: 'Awesome Challenge #31',
      creatorId: _me,
      judgeId: _me,
      status: status,
      inviteCode: 'EJHYE5',
      createdAt: DateTime(2026, 11, 5),
      players: status == GameStatus.lobby ? _players.take(1).toList() : _players,
      tasks: tasks,
      currentTaskIndex: current,
      settings: GameSettings.quickPlay(),
    );

List<Task> _tasks({required Map<String, PlayerTaskStatus> current}) => [
      _task('t1', 'Recreate a famous statue using yourself and the landscape',
          status: TaskStatus.completed,
          statuses: _all(TaskPlayerState.judged)),
      _task('t2', 'Speak for 45 seconds without saying "um", "uh", or "like"',
          statuses: current),
      _task('t3', 'Perform a slow-motion replay of picking up a pencil'),
      _task('t4', 'Balance a spoon on your nose for ten seconds'),
      _task('t5', 'Peel a fruit in one unbroken piece'),
    ];

Future<void> _loadFonts() async {
  Future<void> load(String family, Future<ByteData> data) async {
    final loader = FontLoader(family)..addFont(data);
    await loader.load();
  }

  await load('Fredoka', rootBundle.load('assets/fonts/Fredoka.ttf'));
  await load(
      'PlusJakartaSans', rootBundle.load('assets/fonts/PlusJakartaSans.ttf'));
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    final icons = File(
        '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      await load('MaterialIcons',
          Future.value(ByteData.view(icons.readAsBytesSync().buffer)));
    }
  }
}

void main() {
  late _MockAuthBloc auth;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
  });

  setUp(() async {
    await sl.reset();
    sl.registerSingleton<FriendsRepository>(
        MockFriendsRepository(currentUserId: _me));
    auth = _MockAuthBloc();
    final state = AuthAuthenticated(
      user: User(id: _me, displayName: 'Sage', createdAt: DateTime(2026)),
    );
    when(() => auth.state).thenReturn(state);
    when(() => auth.stream).thenAnswer((_) => const Stream.empty());
    when(() => auth.close()).thenAnswer((_) async {});
  });

  tearDown(() async => sl.reset());

  Future<void> shoot(WidgetTester tester, String name, Brightness brightness,
      Widget body) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      BlocProvider<AuthBloc>.value(
        value: auth,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: brightness == Brightness.light
              ? AppTheme.lightTheme
              : AppTheme.darkTheme,
          home: Scaffold(
            appBar: AppBar(
              title: const Text('Awesome Challenge #31'),
              actions: [
                IconButton(
                    onPressed: () {}, icon: const Icon(Icons.more_horiz)),
              ],
            ),
            body: body,
          ),
        ),
      ),
    );
    // Let entrance animations (ceremony, confetti) finish.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 3));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('game_${name}_${brightness.name}.png'),
    );
  }

  for (final b in Brightness.values) {
    testWidgets('lobby (${b.name})', (tester) async {
      await shoot(
        tester,
        'lobby',
        b,
        GameLobbyView(
          game: _game(GameStatus.lobby, _tasks(current: const {}), current: 0),
        ),
      );
      // One filled button above the fold: the hero's.
      expect(find.byKey(const Key('lobby-hero-button')), findsOneWidget);
    }, skip: !Platform.isMacOS);

    testWidgets('in progress, your turn (${b.name})', (tester) async {
      await shoot(
        tester,
        'in_progress',
        b,
        GameInProgressView(
          game: _game(
            GameStatus.inProgress,
            _tasks(
                current: _all(TaskPlayerState.not_started, except: {
              'p2': TaskPlayerState.submitted,
            })),
          ),
          currentUserId: _me,
          isJudge: true,
        ),
      );
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.text('Start'), findsOneWidget);
    }, skip: !Platform.isMacOS);

    testWidgets('waiting on others (${b.name})', (tester) async {
      await shoot(
        tester,
        'waiting',
        b,
        GameInProgressView(
          game: _game(
            GameStatus.inProgress,
            _tasks(
                current: _all(TaskPlayerState.not_started, except: {
              _me: TaskPlayerState.submitted,
            })),
          ),
          currentUserId: _me,
          isJudge: true,
        ),
      );
      expect(find.text('Waiting for 3 more'), findsOneWidget);
    }, skip: !Platform.isMacOS);

    testWidgets('completed (${b.name})', (tester) async {
      await shoot(
        tester,
        'completed',
        b,
        GameCompletedView(
          game: _game(GameStatus.completed,
              _tasks(current: _all(TaskPlayerState.judged))),
          currentUserId: _me,
          onRematch: () {},
        ),
      );
    }, skip: !Platform.isMacOS);
  }
}
