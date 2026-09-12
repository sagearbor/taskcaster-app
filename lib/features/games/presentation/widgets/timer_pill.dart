import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Small "⏱ 90 s" pill shown next to a task's title wherever the timer needs
/// a one-glance mention (cold open, home hero, task reveal). Pure/stateless —
/// takes the duration and renders it, nothing else.
class TimerPill extends StatelessWidget {
  final int seconds;
  final bool compact;

  const TimerPill({super.key, required this.seconds, this.compact = false});

  static String label(int seconds) => '⏱ $seconds s';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 14,
        vertical: compact ? 4 : 7,
      ),
      decoration: BoxDecoration(
        color: AppTheme.gold.withOpacity(0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.gold.withOpacity(0.4)),
      ),
      child: Text(
        label(seconds),
        style: TextStyle(
          fontSize: compact ? 12.5 : 14,
          fontWeight: FontWeight.w700,
          color: AppTheme.gold,
        ),
      ),
    );
  }
}
