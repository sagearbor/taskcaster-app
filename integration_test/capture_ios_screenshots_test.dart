// Captures the same 8 Play/App Store screenshots as
// scripts/capture_store_screenshots.sh (Android), but on a real booted iOS
// Simulator, driven by this file's `flutter test -d <device>` process
// instead of adb/uiautomator (which have no iOS equivalent).
//
// Unlike the Android script (which drives the REAL installed app externally
// via `adb shell input` taps located by parsing a `uiautomator dump`), this
// drives the app from INSIDE a `flutter test` process using ordinary
// `WidgetTester` finders/taps (`find.text`, `tester.tap`,
// `tester.pumpAndSettle`) — exactly like this repo's regular widget tests,
// except `IntegrationTestWidgetsFlutterBinding` runs them against the real
// rendering/gesture pipeline on an actual simulator, not the Dart-VM
// "flutter tester" target. That's more robust than coordinate/accessibility
// scraping and needs no separate automation tool.
//
// Screenshot mechanism: this process cannot itself run `xcrun simctl io
// screenshot` (an iOS app sandbox — even in the Simulator — can't spawn
// arbitrary host processes via dart:io Process). Instead, right after each
// screen settles this test `print()`s a "SHOT_READY:<name>" marker. Flutter
// forwards `print()` from the on-device test straight through to this
// process's own stdout (confirmed empirically: a `flutter test -d <sim-udid>`
// run shows print() output inline, no separate `log stream` needed). The
// driving shell script (scripts/capture_store_screenshots_ios.sh) tails that
// stdout and fires `xcrun simctl io <udid> screenshot <out>/<name>.png` the
// instant each marker appears — precise, and needs no fixed sleep guessing.
//
// Requires: Flutter 3.22.2 on PATH, a booted iOS Simulator passed via `-d`,
// e.g.:
//   flutter test integration_test/capture_ios_screenshots_test.dart \
//     -d <simulator-udid>
//
// Uses lib/main_screenshots.dart's exact init sequence (mock services, no
// Firebase/network required) — same entry point the Android script builds
// from, so the same seeded mock games / practice-bot flow are available
// here too.
//
// NEVER run this while another `flutter` build/run is in progress elsewhere
// in the repo (repo convention: no parallel flutter builds).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:taskcaster_app/main_screenshots.dart' as app;

/// Small delay after pumpAndSettle before printing a shot's "ready" marker —
/// gives the just-composited frame a moment to actually reach the display
/// before the external script's `xcrun simctl io screenshot` fires.
const _settleBuffer = Duration(milliseconds: 400);

Future<void> _ready(WidgetTester tester, String shotName) async {
  await tester.pumpAndSettle();
  await Future<void>.delayed(_settleBuffer);
  // ignore: avoid_print
  print('SHOT_READY:$shotName');
  // Give the external screenshot command time to actually run before this
  // test moves on and starts changing what's on screen. Pump gently (not a
  // bare Future.delayed) so any still-running mock-data-source timers /
  // stream emissions during the wait are reflected in the tree.
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Repeatedly pumps (real time, not FakeAsync) until [finder] matches at
/// least one widget. A plain `ListView(children: [...])` only builds
/// Elements for children within the current viewport + cache extent (the
/// full Dart widget list exists, but off-screen ones have no Element yet) —
/// the exact same "off-screen nodes don't exist yet" class of bug the
/// Android capture script hit with uiautomator's semantics-tree culling — so
/// if a plain wait doesn't turn it up, this also tries scrolling the
/// nearest Scrollable down (then up) before giving up. On total failure it
/// prints a diagnostic dump of every currently-mounted Text widget before
/// throwing, so a broken finder fails loudly with enough context to fix it
/// instead of a bare "Bad state: No element".
Future<void> _waitFor(WidgetTester tester, Finder finder, String what,
    {int maxTries = 15}) async {
  for (var i = 0; i < maxTries; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 300));
  }
  if (finder.evaluate().isNotEmpty) return;

  if (find.byType(Scrollable).evaluate().isNotEmpty) {
    final scrollable = find.byType(Scrollable).first;
    try {
      await tester.scrollUntilVisible(finder, 250, scrollable: scrollable);
      await tester.pumpAndSettle();
      if (finder.evaluate().isNotEmpty) return;
    } catch (_) {
      // Not found scrolling down; try scrolling back up in case it's above
      // the current position instead.
      try {
        await tester.scrollUntilVisible(finder, -250, scrollable: scrollable);
        await tester.pumpAndSettle();
        if (finder.evaluate().isNotEmpty) return;
      } catch (_) {
        // fall through to the diagnostic dump below.
      }
    }
  }

  final visibleTexts = tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? t.textSpan?.toPlainText())
      .toList();
  // ignore: avoid_print
  print('DIAGNOSTIC: timed out waiting for $what. '
      'Visible Text widgets: $visibleTexts');
  throw StateError('Timed out waiting for $what');
}

Future<void> _tapText(WidgetTester tester, String text, {bool first = false}) async {
  // IMPORTANT: check existence on the plain (un-`.first`-wrapped) finder.
  // A `.first`-wrapped Finder's `.evaluate()` throws "Bad state: No element"
  // immediately when there are zero matches (it isn't a safe/lazy
  // existence check like a normal finder), which would break _waitFor's
  // retry loop by throwing on its very first (empty) attempt instead of
  // actually waiting.
  final baseFinder = find.text(text);
  await _waitFor(tester, baseFinder, '"$text"');
  final tapFinder = first ? baseFinder.first : baseFinder;
  await tester.ensureVisible(tapFinder);
  await tester.pumpAndSettle();
  await tester.tap(tapFinder);
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture the 8 store-listing screenshots', (tester) async {
    app.main();
    await tester.pumpAndSettle();

    // 1. Onboarding — "Party games for everyone" (first/only page, fresh
    // launch of a mock-services app has no persisted "seen onboarding" flag).
    // The driving script uninstalls the app first specifically so this is
    // always reachable, but tolerate a stale install (e.g. a debug rerun on
    // an already-provisioned simulator) skipping straight to the login
    // screen instead of failing the whole capture over one missed shot.
    for (var i = 0; i < 30; i++) {
      if (find.text("Let's play").evaluate().isNotEmpty ||
          find.text('Sign in or create account').evaluate().isNotEmpty) {
        break;
      }
      await tester.pump(const Duration(milliseconds: 300));
    }
    if (find.text("Let's play").evaluate().isNotEmpty) {
      await _ready(tester, '01_onboarding');
      await _tapText(tester, "Let's play");
    } else {
      // ignore: avoid_print
      print('DIAGNOSTIC: onboarding not shown (stale app install?) — '
          'skipping 01_onboarding shot.');
    }

    // 2. Guest sign-in (login screen's one big "Play" button) -> Home.
    await _tapText(tester, 'Play');
    // AuthBloc: AuthLoading (spinner) -> AuthAuthenticated -> HomeScreen,
    // which mounts its own GamesBloc and dispatches LoadGames(). Wait for a
    // Home-only landmark (not just any "Play" text, which also exists on the
    // login screen we're leaving) before treating this as settled.
    await _waitFor(tester, find.text('Invites from friends'),
        'Home screen ("Invites from friends")');
    await _ready(tester, '02_home');

    // 3. Play sheet — the Home screen's own big "Play" button.
    await _tapText(tester, 'Play', first: true);
    await _waitFor(tester, find.text('Quick Play'), 'the Play sheet');
    await _ready(tester, '03_play_sheet');

    // 4. Game lobby — dismiss the sheet, open the seeded lobby game
    // ("Saturday Night Shenanigans", 3-player, invite code PARTY1) directly.
    // Pop it via the root NavigatorState directly rather than tapping a
    // barrier/background coordinate — coordinate- and
    // ModalBarrier-hit-testing both proved unreliable across screen sizes
    // (either missed the barrier and mis-tapped a still-visible sheet row
    // underneath, e.g. into "Tower Trials"/"Quick Play"). A direct
    // NavigatorState.pop() is deterministic regardless of screen geometry.
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    await _tapText(tester, 'Saturday Night Shenanigans');
    await _waitFor(tester, find.text('Creator'), 'the game lobby');
    await _ready(tester, '04_game_lobby');

    // Back to Home for the Quick Play flow (5+6+7).
    await tester.pageBack();
    await tester.pumpAndSettle();
    await _waitFor(tester, find.text('Invites from friends'), 'Home screen');

    await _tapText(tester, 'Play', first: true);
    await _tapText(tester, 'Quick Play');
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Open the first task via the "New task available!" banner's "View".
    await _tapText(tester, 'View', first: true);

    // 5. Task view — a prebuilt task with the video-link submit box.
    await _waitFor(tester, find.byType(TextField), 'the task submit field');
    await _ready(tester, '05_task_view');

    await tester.enterText(
        find.byType(TextField).first, 'https://youtube.com/watch?v=demo123');
    await tester.pumpAndSettle();
    await _tapText(tester, 'Submit Video');
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Judging: solo Quick Play makes the guest both sole player and judge.
    await _tapText(tester, 'Judge', first: true);
    await _tapText(tester, 'Judge All Submissions');

    // 6. Judging screen — scoring a submission (score chips visible). Wait
    // for the verdict scale's own heading, not just pumpAndSettle timing —
    // this screen is reached via an async bloc load, and pumpAndSettle can
    // return once its own animations quiesce even if a later async state
    // update (unrelated to any AnimationController) hasn't landed yet.
    await _waitFor(tester, find.text('Your verdict, judge'), 'the judging screen');
    await _ready(tester, '06_judging');

    // "Finish" pushes TaskScoreboardScreen only if the shared GameDetailBloc
    // is already in a GameDetailLoaded state at that instant (see
    // submission_review_screen.dart's JudgingCompleted listener); if not, it
    // falls back to popping twice, landing back on the "Judge Submissions"
    // list instead of ever reaching the scoreboard. This looks like a
    // pre-existing race in the app (outside this script's scope to fix),
    // that this test's fast automated pace can trigger far more often than
    // a real user would — so retry the score -> reveal -> finish sequence a
    // couple of times (each retry gives GameDetailBloc more real wall-clock
    // time to settle) rather than either hard-failing the whole 8-shot
    // capture or silently accepting a wrong screenshot.
    var reachedScoreboard = false;
    for (var attempt = 0; attempt < 3 && !reachedScoreboard; attempt++) {
      // The score chip's Semantics(label: 'Score N points') wraps a
      // Text('N') child whose own implicit semantics merge in and change
      // the resolved label, so bySemanticsLabel doesn't reliably match —
      // tap the visible digit text directly instead.
      if (find.text('8').evaluate().isEmpty) {
        // A retry landed back on "Judge Submissions" instead of "Review
        // Submissions" — step back in via "Judge All Submissions" first.
        await _tapText(tester, 'Judge All Submissions');
      }
      await _tapText(tester, '8', first: true);
      await _tapText(tester, 'Reveal the scores');
      await _tapText(tester, 'Finish');

      for (var i = 0; i < 20; i++) {
        if (find.textContaining('Results').evaluate().isNotEmpty) {
          reachedScoreboard = true;
          break;
        }
        await tester.pump(const Duration(milliseconds: 300));
      }
    }
    if (!reachedScoreboard) {
      // ignore: avoid_print
      print('DIAGNOSTIC: never reached the scoreboard screen after 3 '
          'attempts — capturing whatever is currently on screen for '
          '07_scoreboard instead of failing the whole 8-shot run.');
    }

    // 7. Scoreboard — animated reveal (confetti + WINNER badge).
    await _ready(tester, '07_scoreboard');

    // Back to Home. TaskScoreboardScreen (and some fallback screens landed
    // on above) has `automaticallyImplyLeading: false` — no standard back
    // button for tester.pageBack() to find — so pop the root Navigator
    // directly instead, which works regardless of which screen we're
    // actually on.
    final navigator =
        tester.state<NavigatorState>(find.byType(Navigator).first);
    for (var i = 0; i < 8; i++) {
      if (find.text('Invites from friends').evaluate().isNotEmpty) break;
      if (navigator.canPop()) {
        navigator.pop();
      }
      await tester.pumpAndSettle();
    }
    await _waitFor(tester, find.text('Invites from friends'), 'Home screen');

    // 8. Drawing Telephone canvas — Play sheet -> Drawing Telephone ->
    // Options -> Practice solo (fully offline, deterministic, no
    // networking) -> submit a prompt -> sketch a few strokes.
    await _tapText(tester, 'Play', first: true);
    await _tapText(tester, 'Drawing Telephone');

    await _tapText(tester, 'Options');
    await _tapText(tester, 'Practice solo — play vs bots, no internet');
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // Round 1 asks for a prompt; the default player name ("Player") is fine.
    await _waitFor(tester, find.byType(TextField), 'the prompt field');
    await tester.enterText(
        find.byType(TextField).first, 'A dinosaur riding a skateboard');
    await tester.pumpAndSettle();
    await _tapText(tester, 'Submit prompt');
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // Sketch a few strokes so the canvas isn't blank in the screenshot.
    await _waitFor(tester, find.byType(GestureDetector), 'the drawing canvas');
    final canvasCenter = tester.getCenter(find.byType(GestureDetector).last);
    await tester.dragFrom(
        canvasCenter - const Offset(60, 0), const Offset(120, 0));
    await tester.pumpAndSettle();
    await tester.dragFrom(
        canvasCenter - const Offset(0, 40), const Offset(0, 80));
    await tester.pumpAndSettle();

    await _ready(tester, '08_drawing_telephone_canvas');
  });
}
