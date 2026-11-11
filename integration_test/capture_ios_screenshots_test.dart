// Captures the 8 App Store screenshots on a booted iOS Simulator, driven from
// inside this file's `flutter test -d <device>` process with ordinary
// WidgetTester finders/taps against the real rendering pipeline.
//
// The shots sell the core loop (docs/PRODUCT_DIRECTION.md). File names are
// the App Store order; the test captures them in whatever order the flow
// allows:
//   01_daily_task     — Home: today's task and the streak
//   02_task_clock     — a task mid-attempt, its clock running
//   03_arena_reveal   — grading someone in the Arena: the reveal
//   04_party_mode     — Party mode: one phone, the room competes
//   05_first_ten      — the Starter Pack recap ("Your First Ten")
//   06_posted         — the Posted polaroid with its auto-stamp
//   07_play_sheet     — the Play sheet: friends, party, join, Telephone
//   08_cold_open      — the first task, before any sign-in
//
// Data: lib/main_screenshots.dart runs the real app shell on MOCK services,
// and the driving script also passes --dart-define=E2E=true (E2eMode: Arena
// grades are not written, posts are not shareable). Everything this test
// seeds (the guest's earlier days, a few crowd grades) goes into in-memory
// mocks. Nothing here can reach Firebase or production.
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

    // ---- 08: the cold open — the first task, nobody signed in yet --------
    final coldStart = find.textContaining('Start —');
    await _waitFor(tester, coldStart, 'the cold open');
    await _ready(tester, '08_cold_open');

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

    // ---- 06: Posted — the polaroid and its stamp -------------------------
    await _tap(tester, find.text('Post it'), 'Post it');
    await _waitFor(tester, find.text('Posted.'), 'the Posted screen');
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await _ready(tester, '06_posted');

    // ---- 03: the Arena — grade an entry, catch the reveal ----------------
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
    await _ready(tester, '03_arena_reveal');
    ArenaScreen.revealHold = ArenaScreen.defaultRevealHold;
    await _popToHome(tester);

    // ---- Seed the guest's history (mock store only) ----------------------
    // Four earlier days of posts, so with today's post the streak reads 5.
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
    await _settle(tester);

    // ---- 01: Home — today's task and the streak --------------------------
    await _waitFor(tester, find.byKey(const Key('home-hero-daily')),
        "today's task hero");
    await _waitFor(tester, find.byKey(const Key('hero-streak-chip')),
        'the streak chip');
    await _ready(tester, '01_daily_task');

    // ---- 05: Your First Ten — the Starter Pack recap ---------------------
    _nav(tester).push(MaterialPageRoute<void>(
      builder: (_) => GameDetailScreen(gameId: starter.id),
    ));
    await _waitFor(tester, find.textContaining('First Ten'), 'the recap');
    await _ready(tester, '05_first_ten');
    await _popToHome(tester);

    // ---- 07: the Play sheet ----------------------------------------------
    await _tap(tester, find.byKey(const Key('home-play-plus')), 'the + button');
    final partyRow = find.text('Party mode (same room)');
    await _waitFor(tester, partyRow, 'the Play sheet');
    await _ready(tester, '07_play_sheet');

    // ---- 04: Party mode — four of you, task 1 read aloud -----------------
    await _tap(tester, partyRow, 'Party mode');
    for (final who in const ['Me', 'Mum', 'Gran', 'Bestie']) {
      await _tap(tester, find.text('+ $who'), 'the + $who chip');
    }
    // No secret missions: go straight to the first task.
    await _tap(tester, find.byKey(const ValueKey('party-missions-switch')),
        'the missions switch');
    await _tap(tester, find.text('Start the party'), 'Start the party');
    await _waitFor(tester, find.text('Read it aloud. Then start the clock.'),
        'the first party task');
    await _ready(tester, '04_party_mode');
  });
}
