import 'package:flutter/material.dart';

import '../../../../core/models/game.dart';
import '../../../../core/models/player_task_status.dart';
import '../../../../core/models/task.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/peer_grading.dart';
import 'timer_pill.dart';

/// What the hero button on the game screen does.
enum UpNextAction {
  /// Open the current task to play it (start, continue or submit).
  play,

  /// Open the judging screen for the current task.
  judge,

  /// Group-graded game (WP-13): open the grade queue for the current task.
  grade,

  /// Show the current task's results.
  results,

  /// Open the full scoreboard.
  scoreboard,

  /// Nothing to do yet (waiting on others) — the button is disabled.
  none,
}

/// The single next step for [currentUserId] in an in-progress [game]: which
/// task, a one-line situation, and exactly one button. Pure (no context), so
/// it is unit-testable and the game screen is driven entirely by it.
///
/// Mirrors the routing rules of the old status banner, including the House
/// Hunt case: a non-playing judge (judgePlays=false) is driven by the TASK
/// state and is never sent into the player's submit flow.
@immutable
class UpNext {
  /// Small all-caps overline: "YOUR TURN", "SUBMITTED", "TIME TO JUDGE"…
  final String kicker;

  /// The headline — normally the current task's title.
  final String title;

  /// One supporting line under the title (may be null).
  final String? detail;

  /// The one button's label.
  final String buttonLabel;
  final UpNextAction action;

  /// True when the clock is nearly out (styles the kicker as urgent).
  final bool urgent;

  /// Index of the task this hero is about (for "Task 2 of 5"), or -1.
  final int taskIndex;

  const UpNext({
    required this.kicker,
    required this.title,
    this.detail,
    required this.buttonLabel,
    required this.action,
    this.urgent = false,
    this.taskIndex = -1,
  });

  bool get isWaiting => action == UpNextAction.none;

  static String _entries(int n) => n == 1 ? '1 entry' : '$n entries';

  /// [alsoGraded]: entry authors this device graded on the current task
  /// that the server has not echoed into `Task.peerGraders` yet.
  static UpNext resolve(
    Game game, {
    required String currentUserId,
    required bool isJudge,
    DateTime? now,
    Set<String> alsoGraded = const {},
  }) {
    final task = game.currentTask;
    if (task == null) {
      return const UpNext(
        kicker: 'ALL TASKS PLAYED',
        title: 'Waiting for the final scores',
        buttonLabel: 'See scoreboard',
        action: UpNextAction.scoreboard,
      );
    }
    final index = game.currentTaskIndex;
    final expected = task.playerStatuses.length;
    final submitted = task.submittedCount;
    final remaining = (expected - submitted).clamp(0, expected);
    final unjudged = (submitted - task.judgedCount).clamp(0, submitted);

    UpNext make(String kicker, String button, UpNextAction action,
            {String? detail, bool urgent = false}) =>
        UpNext(
          kicker: kicker,
          title: task.title,
          detail: detail,
          buttonLabel: button,
          action: action,
          urgent: urgent,
          taskIndex: index,
        );

    // Non-playing judge (House Hunt hider): driven by the task, never by a
    // (non-existent) personal status.
    if (isJudge && !game.settings.judgePlays) {
      if (task.status == TaskStatus.ready_to_judge || unjudged > 0) {
        return make('TIME TO JUDGE', 'Grade ${_entries(unjudged < 1 ? 1 : unjudged)}',
            UpNextAction.judge,
            detail: 'The seeker has submitted. Score their find.');
      }
      if (task.status == TaskStatus.completed) {
        return make('SCORES ARE IN', 'See results', UpNextAction.results);
      }
      return make(
        'WAITING FOR THE SEEKER',
        remaining > 1 ? 'Waiting for $remaining more' : 'Waiting for the seeker…',
        UpNextAction.none,
        detail: 'They\'re hunting it down now.',
      );
    }

    final status = task.playerStatuses[currentUserId];
    final state = status?.state;

    if (task.status == TaskStatus.completed) {
      final score = status?.score;
      // Group grades are round(mean x 2): out of 10.
      final outOf = game.isGroupJudged ? 10 : 5;
      return make('SCORES ARE IN', 'See results', UpNextAction.results,
          detail: score != null ? 'You got $score/$outOf.' : null);
    }

    if (state == null || state == TaskPlayerState.not_started) {
      return make('YOUR TURN', 'Start', UpNextAction.play,
          detail: task.description.isEmpty ? null : task.description);
    }

    if (state == TaskPlayerState.in_progress) {
      final deadline = task.deadline;
      final urgent = deadline != null &&
          deadline.difference(now ?? DateTime.now()).inHours < 1;
      return make(urgent ? 'TIME RUNNING OUT' : 'IN PROGRESS',
          'Finish and submit', UpNextAction.play,
          detail: urgent ? 'Submit before the clock runs out.' : null,
          urgent: urgent);
    }

    // Group-graded (WP-13): posting unlocks grading, and EVERY player grades
    // every other entry. There is no judge to wait for.
    if (game.isGroupJudged) {
      final queue = PeerGrading.queue(game, index, currentUserId,
          alsoGraded: alsoGraded);
      if (queue.isNotEmpty) {
        return make('GRADE THE CREW', 'Grade ${_entries(queue.length)}',
            UpNextAction.grade,
            detail: 'Your entry is in. Score each friend\'s, 1 to 5.');
      }
      if (remaining > 0) {
        return make('SUBMITTED ✓', 'Waiting for $remaining more',
            UpNextAction.none,
            detail: 'You\'ll grade each entry as it comes in.');
      }
      return make('ALL GRADED ✓', 'Waiting for the crew', UpNextAction.none,
          detail: 'Scores lock when everyone has graded, or after 24 hours.');
    }

    // The player has submitted (or skipped / been judged).
    if (remaining > 0) {
      return make('SUBMITTED ✓', 'Waiting for $remaining more',
          UpNextAction.none,
          detail: '$submitted of $expected entries are in.');
    }
    if (isJudge && (task.status == TaskStatus.ready_to_judge || unjudged > 0)) {
      return make('TIME TO JUDGE', 'Grade ${_entries(unjudged < 1 ? expected : unjudged)}',
          UpNextAction.judge,
          detail: 'Everyone is in. Pick a winner.');
    }
    if (game.settings.crowdJudged) {
      return make('ALL ENTRIES IN', 'Waiting for the crowd', UpNextAction.none,
          detail: 'Strangers are grading in the Arena.');
    }
    return make('JUDGE IS REVIEWING', 'Scores coming soon', UpNextAction.none,
        detail: 'Everyone is in.');
  }
}

/// The game screen's hero: the current task on the brand gradient, its
/// timer, and exactly one button. While waiting the button is shown
/// disabled so the player still sees what happens next.
class UpNextCard extends StatelessWidget {
  final UpNext upNext;
  final int taskCount;

  /// The current task's time limit in seconds (shown as a pill), if any.
  final int? timerSeconds;
  final VoidCallback? onPressed;

  const UpNextCard({
    super.key,
    required this.upNext,
    required this.taskCount,
    this.timerSeconds,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);
    final position = upNext.taskIndex >= 0 && taskCount > 0
        ? 'TASK ${upNext.taskIndex + 1} OF $taskCount'
        : null;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: tokens.heroGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: theme.brightness == Brightness.light
            ? [
                BoxShadow(
                  color: theme.colorScheme.primary.withOpacity(0.18),
                  blurRadius: 24,
                  spreadRadius: -6,
                  offset: const Offset(0, 12),
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    upNext.kicker,
                    key: const Key('up-next-kicker'),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: tokens.onHero,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.3,
                    ),
                  ),
                ),
                if (position != null) ...[
                  const Spacer(),
                  Text(
                    position,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: tokens.onHeroMuted,
                      letterSpacing: 1.1,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Text(
              upNext.title,
              key: const Key('up-next-title'),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: tokens.onHero,
                height: 1.15,
              ),
            ),
            if (upNext.detail != null) ...[
              const SizedBox(height: 8),
              Text(
                upNext.detail!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: tokens.onHeroMuted),
              ),
            ],
            if (timerSeconds != null && upNext.action == UpNextAction.play) ...[
              const SizedBox(height: 12),
              TimerPill(seconds: timerSeconds!, onGradient: true),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('up-next-button'),
                onPressed: upNext.isWaiting ? null : onPressed,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppTheme.violetDeep,
                  disabledBackgroundColor: Colors.white.withOpacity(0.18),
                  disabledForegroundColor: tokens.onHero,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (upNext.isWaiting) ...[
                      const Icon(Icons.hourglass_top_rounded, size: 18),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(upNext.buttonLabel,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
