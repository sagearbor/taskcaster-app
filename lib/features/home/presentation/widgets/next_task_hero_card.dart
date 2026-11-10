import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../games/presentation/widgets/timer_pill.dart';
import '../../../tasks/data/datasources/daily_task_data.dart';

/// Home zone 1 — "Your next task": the starter-pack hero, and (WP-6) today's
/// task with its 🔥 streak. Pure/stateless, so
/// it is fully testable without a bloc; [HomeView] derives which [mode] to
/// show from the games list (does the user have a starter game yet, and if
/// so is there an unsubmitted task left) and supplies the callback.
enum NextTaskHeroMode {
  /// The user has a starter game with a task left to do.
  hasTask,

  /// The user has completed all ten starter tasks. Headline is "Waiting for
  /// the crowd: N" (N = their entries still short of grades, see
  /// [NextTaskHeroCard.waitingCount]); the action is Challenge friends.
  allDone,

  /// The user has no starter game yet (e.g. an account from before this
  /// round shipped) — offer to start one.
  noStarterGame,

  /// WP-6: today's task (the same for everyone this UTC day), not yet
  /// posted. Title, timer pill and Start.
  dailyTask,

  /// WP-6: today's task is posted. "Done for today", the streak, when the
  /// next task arrives, and "See today's entries".
  dailyDone,
}

class NextTaskHeroCard extends StatelessWidget {
  final NextTaskHeroMode mode;
  final String? taskTitle;
  final int? timerSeconds;

  /// [NextTaskHeroMode.allDone] only: how many of the player's entries are
  /// still waiting on crowd grades. Null while unknown.
  final int? waitingCount;
  final VoidCallback onPrimary;

  /// The 🔥 streak in days. A chip in the top corner when above 0.
  final int streak;

  /// [NextTaskHeroMode.dailyDone]: time until the next task.
  final Duration? nextTaskIn;

  /// One quiet line under the headline (e.g. "Waiting for the crowd: 3").
  final String? subline;

  /// An optional text button under the primary one.
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  const NextTaskHeroCard({
    super.key,
    required this.mode,
    this.taskTitle,
    this.timerSeconds,
    this.waitingCount,
    required this.onPrimary,
    this.streak = 0,
    this.nextTaskIn,
    this.subline,
    this.secondaryLabel,
    this.onSecondary,
  });

  bool get _showsTimer =>
      (mode == NextTaskHeroMode.hasTask || mode == NextTaskHeroMode.dailyTask) &&
      timerSeconds != null;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Card(
      elevation: 3,
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(gradient: tokens.heroGradient),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _overline,
                    style: TextStyle(
                      color: tokens.onHeroMuted,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      fontSize: 12.5,
                    ),
                  ),
                ),
                if (streak > 0) StreakChip(days: streak),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _headline,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: tokens.onHero,
                    height: 1.15,
                  ),
            ),
            if (_showsTimer) ...[
              const SizedBox(height: 12),
              TimerPill(seconds: timerSeconds!, onGradient: true),
            ],
            if (mode == NextTaskHeroMode.dailyDone) ...[
              const SizedBox(height: 8),
              Text(
                _doneLine,
                key: const Key('hero-daily-done-line'),
                style: TextStyle(color: tokens.onHero, fontSize: 14.5),
              ),
            ],
            if (subline != null) ...[
              const SizedBox(height: 8),
              Text(
                subline!,
                key: const Key('hero-subline'),
                style: TextStyle(color: tokens.onHeroMuted, fontSize: 13.5),
              ),
            ],
            if (mode == NextTaskHeroMode.allDone) ...[
              const SizedBox(height: 8),
              Text(
                'All ten done. Now make your friends do one.',
                style: TextStyle(color: tokens.onHero, fontSize: 14.5),
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onPrimary,
                style: FilledButton.styleFrom(
                  backgroundColor: tokens.onHero,
                  foregroundColor: AppTheme.violetDeep,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  _buttonLabel,
                  style: const TextStyle(fontSize: 17),
                ),
              ),
            ),
            if (secondaryLabel != null && onSecondary != null) ...[
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  key: const Key('hero-secondary'),
                  onPressed: onSecondary,
                  style: TextButton.styleFrom(foregroundColor: tokens.onHero),
                  child: Text(
                    secondaryLabel!,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String get _overline {
    switch (mode) {
      case NextTaskHeroMode.hasTask:
        return 'YOUR NEXT TASK';
      case NextTaskHeroMode.allDone:
        return 'YOUR FIRST TEN';
      case NextTaskHeroMode.noStarterGame:
        return 'GET STARTED';
      case NextTaskHeroMode.dailyTask:
      case NextTaskHeroMode.dailyDone:
        return "TODAY'S TASK";
    }
  }

  /// "🔥 4 days running. New task in 5 h 12 m."
  String get _doneLine {
    final parts = <String>[
      if (streak == 1) '🔥 1 day running.',
      if (streak > 1) '🔥 $streak days running.',
      if (nextTaskIn != null)
        'New task in ${DailyTaskData.formatUntil(nextTaskIn!)}.',
    ];
    return parts.isEmpty ? 'Come back tomorrow.' : parts.join(' ');
  }

  String get _headline {
    switch (mode) {
      case NextTaskHeroMode.hasTask:
        return taskTitle ?? '';
      case NextTaskHeroMode.allDone:
        final n = waitingCount;
        return n != null && n > 0
            ? 'Waiting for the crowd: $n'
            : 'The crowd has spoken.';
      case NextTaskHeroMode.noStarterGame:
        return 'Your first ten tasks are waiting';
      case NextTaskHeroMode.dailyTask:
        return taskTitle ?? '';
      case NextTaskHeroMode.dailyDone:
        return 'Done for today.';
    }
  }

  String get _buttonLabel {
    switch (mode) {
      case NextTaskHeroMode.hasTask:
        return 'Start';
      case NextTaskHeroMode.allDone:
        return 'Challenge friends';
      case NextTaskHeroMode.noStarterGame:
        return 'Start';
      case NextTaskHeroMode.dailyTask:
        return 'Start';
      case NextTaskHeroMode.dailyDone:
        return "See today's entries";
    }
  }
}

/// "🔥 4" on the hero gradient: the streak, in days.
class StreakChip extends StatelessWidget {
  final int days;

  const StreakChip({super.key, required this.days});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Semantics(
      container: true,
      label: days == 1 ? '1-day streak' : '$days-day streak',
      excludeSemantics: true,
      child: Container(
        key: const Key('hero-streak-chip'),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: tokens.onHero.withOpacity(0.2),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: tokens.onHero.withOpacity(0.45)),
        ),
        child: Text(
          '🔥 $days',
          style: TextStyle(
            color: tokens.onHero,
            fontWeight: FontWeight.w800,
            fontSize: 13.5,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
