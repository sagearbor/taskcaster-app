// Captures the 8 App Store screenshots on a booted iOS Simulator, driven from
// inside this file's `flutter test -d <device>` process with ordinary
// WidgetTester finders/taps against the real rendering pipeline.
//
// The shots sell the core loop (docs/PRODUCT_DIRECTION.md):
//   01_cold_open      — the first task, before any sign-in
//   02_task_clock     — a task mid-attempt, its clock running
//   03_posted         — the Posted polaroid with its auto-stamp
//   04_arena_reveal   — grading someone in the Arena: the reveal
//   05_first_ten      — the Starter Pack recap ("Your First Ten")
//   06_today_streak   — Home: today's task and the streak
//   07_house_entries  — the Arena tease of other people's entries
//   08_friend_game    — a friend game lobby with the invite up
//
// Data: lib/main_screenshots.dart runs the real app shell on MOCK services.
// Everything this test seeds (the guest's earlier days, a friend game, a few
// crowd grades) goes into those in-memory mocks. Nothing here can reach
// Firebase or production.
//
// Screenshot mechanism: an iOS app sandbox can't run `xcrun simctl`, so after
// each screen settles this test prints "SHOT_READY:<name>";
// scripts/capture_store_screenshots_ios.sh tails the `flutter test` output
// and fires `xcrun simctl io <udid> screenshot <out>/<name>.png` on each one.
//
//   flutter test integration_test/capture_ios_screenshots_test.dart \
//     -d <simulator-udid>
//
// NEVER run this while another `flutter` build/run is in progress elsewhere
// in the repo (repo convention: no parallel flutter builds).

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:taskcaster_app/core/di/service_locator.dart';
import 'package:taskcaster_app/core/models/submission.dart';
import 'package:taskcaster_app/core/models/task.dart';
import 'package:taskcaster_app/features/arena/domain/models/feed_post.dart';
import 'package:taskcaster_app/features/arena/domain/repositories/feed_repository.dart';
import 'package:taskcaster_app/features/arena/presentation/screens/arena_screen.dart';
import 'package:taskcaster_app/features/arena/presentation/widgets/grade_bar.dart';
import 'package:taskcaster_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:taskcaster_app/features/games/domain/repositories/game_repository.dart';
import 'package:taskcaster_app/features/games/presentation/bloc/task_execution_bloc.dart';
import 'package:taskcaster_app/features/games/presentation/bloc/task_execution_event.dart';
import 'package:taskcaster_app/features/games/presentation/bloc/task_execution_state.dart';
import 'package:taskcaster_app/features/games/presentation/screens/game_detail_screen.dart';
import 'package:taskcaster_app/features/games/presentation/screens/task_execution_screen.dart';
import 'package:taskcaster_app/features/tasks/data/datasources/daily_task_data.dart';
import 'package:taskcaster_app/main_screenshots.dart' as app;

/// Small delay after pumpAndSettle before printing a shot's "ready" marker —
/// gives the just-composited frame a moment to reach the display before the
/// external script's `xcrun simctl io screenshot` fires.
const _settleBuffer = Duration(milliseconds: 600);

Future<void> _settle(WidgetTester tester) async {
  try {
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 6),
    );
  } catch (_) {
    // A looping animation (a pulsing chip, a ticking clock) never settles;
    // that is fine for a screenshot.
  }
}

Future<void> _ready(WidgetTester tester, String shotName) async {
  await _settle(tester);
  await Future<void>.delayed(_settleBuffer);
  // ignore: avoid_print
  print('SHOT_READY:$shotName');
  // Give the external screenshot command time to run before this test moves
  // on and starts changing what's on screen.
  for (var i = 0; i < 25; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Pumps (real time) until [finder] matches. On failure, prints every
/// mounted Text so a broken finder fails with enough context to fix it.
Future<void> _waitFor(WidgetTester tester, Finder finder, String what,
    {int maxTries = 40}) async {
  for (var i = 0; i < maxTries; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 250));
  }
  if (finder.evaluate().isNotEmpty) return;
  final visibleTexts = tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? t.textSpan?.toPlainText())
      .toList();
  // ignore: avoid_print
  print('DIAGNOSTIC: timed out waiting for $what. '
      'Visible Text widgets: $visibleTexts');
  throw StateError('Timed out waiting for $what');
}

Future<void> _tap(WidgetTester tester, Finder finder, String what) async {
  await _waitFor(tester, finder, what);
  await tester.ensureVisible(finder.first);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.tap(finder.first);
  await tester.pump(const Duration(milliseconds: 300));
}

NavigatorState _nav(WidgetTester tester) =>
    tester.state<NavigatorState>(find.byType(Navigator).first);

Future<void> _popToHome(WidgetTester tester) async {
  _nav(tester).popUntil((r) => r.isFirst);
  await _settle(tester);
}

/// Seeds an entry through the same bloc the task screen uses, so the game,
/// the submission and the Arena post all line up exactly as a real attempt.
Future<void> _seedEntry({
  required String gameId,
  required int taskIndex,
  required String userId,
  required String displayName,
  required String text,
}) async {
  final bloc = TaskExecutionBloc(
    gameRepository: sl<GameRepository>(),
    feedRepository: sl<FeedRepository>(),
  );
  bloc.add(LoadTask(gameId: gameId, taskIndex: taskIndex, userId: userId));
  await bloc.stream.firstWhere((s) => s is TaskExecutionLoaded);
  bloc.add(StartTask(gameId: gameId, taskIndex: taskIndex, userId: userId));
  await bloc.stream.firstWhere((s) =>
      s is TaskExecutionLoaded && s.userStatus?.startedAt != null);
  await Future<void>.delayed(const Duration(milliseconds: 1500));
  bloc.add(SubmitTask(
    gameId: gameId,
    taskIndex: taskIndex,
    userId: userId,
    displayName: displayName,
    text: text,
  ));
  await bloc.stream.firstWhere(
      (s) => s is TaskExecutionSubmitted || s is TaskExecutionError);
  await bloc.close();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // An empty description on purpose: the live test binding paints the test's
  // name in the top-left corner of the screen, which would end up in every
  // screenshot.
  testWidgets('', (tester) async {
    app.main();
    await tester.pump(const Duration(seconds: 1));

    // ---- 01: the cold open — the first task, nobody signed in yet --------
    final coldStart = find.textContaining('Start —');
    await _waitFor(tester, coldStart, 'the cold open');
    await _ready(tester, '01_cold_open');

    // Start: guest sign-in, the Starter Pack opens on task 1.
    await _tap(tester, coldStart, 'cold open Start');
    await _waitFor(tester, find.byKey(const Key('starter-task-title')),
        'Starter task 1');
    await _settle(tester);

    final ctx = tester.element(find.byType(Navigator).first);
    final auth = BlocProvider.of<AuthBloc>(ctx).state as AuthAuthenticated;
    final uid = auth.user.id;
    final name = auth.user.displayName;
    final games = sl<GameRepository>();
    final feed = sl<FeedRepository>();
    final starter = (await games.getGamesStream().first)
        .firstWhere((g) => g.isStarter && g.players.any((p) => p.userId == uid));

    // ---- 07: the Arena tease — everyone else's entries on task 1 ---------
    await _popToHome(tester);
    await _tap(tester, find.text('Arena — see how others did'),
        'the Arena tease row');
    await _waitFor(tester, find.byKey(const Key('arena-your-turn')),
        'the Arena tease');
    await _ready(tester, '07_house_entries');
    await _popToHome(tester);

    // ---- 02: a text task mid-attempt, clock running ----------------------
    final textIndex = starter.tasks
        .indexWhere((t) => t.submissionType == SubmissionType.text);
    _nav(tester).push(MaterialPageRoute<void>(
      builder: (_) => TaskExecutionScreen(
        gameId: starter.id,
        taskIndex: textIndex,
        autoStart: true,
      ),
    ));
    await _waitFor(tester, find.byType(TextField), 'the write box');
    await tester.enterText(find.byType(TextField).first,
        'The kettle is now "Steve". Steve screams when he is happy.');
    await tester.pump(const Duration(milliseconds: 300));
    FocusManager.instance.primaryFocus?.unfocus();
    // Let the clock visibly run.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await _ready(tester, '02_task_clock');

    // ---- 03: Posted — the polaroid and its stamp -------------------------
    await _tap(tester, find.text('Post it'), 'Post it');
    await _waitFor(tester, find.text('Posted.'), 'the Posted screen');
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await _ready(tester, '03_posted');

    // ---- 04: the Arena — grade an entry, catch the reveal ----------------
    await _tap(tester, find.byKey(const Key('see-theirs-button')),
        'See theirs');
    final gradeFive = find.descendant(
        of: find.byType(GradeBar), matching: find.text('5'));
    await _waitFor(tester, gradeFive, 'the grade bar');
    await _settle(tester);
    ArenaScreen.revealHold = const Duration(seconds: 12);
    await tester.tap(gradeFive.first);
    await tester.pump(const Duration(milliseconds: 100));
    await _waitFor(tester, find.byKey(const Key('grade-reveal')), 'the reveal');
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await _ready(tester, '04_arena_reveal');
    ArenaScreen.revealHold = ArenaScreen.defaultRevealHold;
    await _popToHome(tester);

    // ---- Seed the guest's history (mock store only) ----------------------
    // Four earlier days of posts, so today's post makes a 5-day streak.
    final now = DateTime.now();
    for (var k = 1; k <= 4; k++) {
      final day = now.subtract(Duration(days: k));
      final task = DailyTaskData.taskFor(day);
      await feed.createPost(FeedPost(
        id: '',
        gameId: DailyTaskData.gameIdFor(uid, DailyTaskData.dayKey(day)),
        taskId: task.id,
        taskTitle: task.title,
        userId: uid,
        displayName: name,
        mediaType: SubmissionMediaType.text,
        text: 'Day -$k entry',
        createdAt: day,
      ));
    }
    // A few more Starter Pack entries, so the recap has something to show.
    const entries = <String>[
      'Remembered the oven. Then remembered I do not own an oven.',
      'I am the lamp now. Nobody has noticed. Day three.',
      'Mona Lisa, but she is a dishcloth and a spoon.',
      'It went in the fridge. It did not come out.',
    ];
    var seeded = 0;
    for (var i = 0; i < starter.tasks.length && seeded < entries.length; i++) {
      if (i == textIndex) continue;
      await _seedEntry(
        gameId: starter.id,
        taskIndex: i,
        userId: uid,
        displayName: name,
        text: entries[seeded++],
      );
    }
    // The crowd has been at them.
    final mine = await feed.watchPostsByUser(uid).first;
    var g = 0;
    for (final p in mine.where((p) => p.gameId == starter.id)) {
      for (var j = 0; j < 3; j++) {
        await feed.gradePost(
            postId: p.id, graderId: 'crowd-${g++}', score: 3 + (g + j) % 3);
      }
    }
    // The mock store ships demo games the guest isn't in; a real guest's
    // Home never lists strangers' games, so clear them out of the mock.
    for (final game in await games.getGamesStream().first) {
      if (!game.players.any((p) => p.userId == uid)) {
        await games.deleteGame(game.id);
      }
    }
    await _settle(tester);

    // ---- 06: Home — today's task and the streak --------------------------
    // Earlier taps scrolled Home down to the Arena row; back to the top.
    final homeScroll = find.byType(Scrollable).first;
    for (var i = 0; i < 3; i++) {
      await tester.drag(homeScroll, const Offset(0, 1500));
      await _settle(tester);
    }
    await _waitFor(tester, find.byKey(const Key('hero-streak-chip')),
        'the streak chip');
    await _ready(tester, '06_today_streak');

    // ---- 05: Your First Ten — the Starter Pack recap ---------------------
    _nav(tester).push(MaterialPageRoute<void>(
      builder: (_) => GameDetailScreen(gameId: starter.id),
    ));
    await _waitFor(tester, find.textContaining('First Ten'), 'the recap');
    await _ready(tester, '05_first_ten');
    await _popToHome(tester);

    // ---- 08: a friend game, lobby with the crew arriving -----------------
    final friendId = await games.createGame('Friday Night Tasks', uid, uid);
    final friendGame = (await games.getGameStream(friendId).first)!;
    for (final f in const [
      ('friend-1', 'Priya'),
      ('friend-2', 'Marcus'),
      ('friend-3', 'Jo'),
    ]) {
      await games.joinGame(friendGame.inviteCode, f.$1, f.$2);
    }
    await games.addTasksToGame(friendId, const [
      Task(
        id: 'friend-task-1',
        title: 'Make the most magnificent sandwich',
        description: 'Only what is in your kitchen right now.',
        taskType: TaskType.video,
        submissions: [],
      ),
      Task(
        id: 'friend-task-2',
        title: 'Wear as many hats as possible',
        description: 'Each one has to stay on for five seconds.',
        taskType: TaskType.video,
        submissions: [],
      ),
    ]);
    // The mock's createGame names the creator "Creator"; read as "You".
    final crewed = (await games.getGameStream(friendId).first)!;
    await games.updateGame(
      friendId,
      crewed.copyWith(players: [
        for (final p in crewed.players)
          p.userId == uid ? p.copyWith(displayName: 'You') : p,
      ]),
    );
    _nav(tester).push(MaterialPageRoute<void>(
      builder: (_) => GameDetailScreen(gameId: friendId),
    ));
    await _waitFor(tester, find.text('Friday Night Tasks'), 'the friend game');
    await _ready(tester, '08_friend_game');

  });
}
