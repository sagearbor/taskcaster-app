import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../games/presentation/widgets/timer_pill.dart';

/// Home zone 1 — "Your next task": the starter-pack hero. Pure/stateless, so
/// it is fully testable without a bloc; [HomeView] derives which [mode] to
/// show from the games list (does the user have a starter game yet, and if
/// so is there an unsubmitted task left) and supplies the callback.
enum NextTaskHeroMode {
  /// The user has a starter game with a task left to do.
  hasTask,

  /// The user has completed all ten starter tasks.
  allDone,

  /// The user has no starter game yet (e.g. an account from before this
  /// round shipped) — offer to start one.
  noStarterGame,
}

class NextTaskHeroCard extends StatelessWidget {
  final NextTaskHeroMode mode;
  final String? taskTitle;
  final int? timerSeconds;
  final VoidCallback onPrimary;

  const NextTaskHeroCard({
    super.key,
    required this.mode,
    this.taskTitle,
    this.timerSeconds,
    required this.onPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppTheme.violet, AppTheme.coral],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _overline,
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                fontSize: 12.5,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _headline,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 22,
                height: 1.2,
              ),
            ),
            if (mode == NextTaskHeroMode.hasTask && timerSeconds != null) ...[
              const SizedBox(height: 12),
              TimerPill(seconds: timerSeconds!),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onPrimary,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppTheme.violetDeep,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  _buttonLabel,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
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
    }
  }

  String get _headline {
    switch (mode) {
      case NextTaskHeroMode.hasTask:
        return taskTitle ?? '';
      case NextTaskHeroMode.allDone:
        return 'You\'ve done all ten. Play with friends?';
      case NextTaskHeroMode.noStarterGame:
        return 'Your first ten tasks are waiting';
    }
  }

  String get _buttonLabel {
    switch (mode) {
      case NextTaskHeroMode.hasTask:
        return 'Start';
      case NextTaskHeroMode.allDone:
        return 'Play';
      case NextTaskHeroMode.noStarterGame:
        return 'Start';
    }
  }
}
