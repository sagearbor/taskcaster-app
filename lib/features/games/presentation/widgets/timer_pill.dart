import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Small "⏱ 90 s" pill shown next to a task's title wherever the timer needs
/// a one-glance mention (cold open, home hero, task reveal). Pure/stateless —
/// takes the duration and renders it, nothing else.
class TimerPill extends StatelessWidget {
  final int seconds;
  final bool compact;

  /// Set when the pill sits on the violet→coral hero gradient: white text on
  /// a translucent white chip (gold text there is unreadable).
  final bool onGradient;

  const TimerPill({
    super.key,
    required this.seconds,
    this.compact = false,
    this.onGradient = false,
  });

  static String label(int seconds) => '⏱ $seconds s';

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final fill = onGradient ? tokens.onHero : tokens.gold;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 14,
        vertical: compact ? 4 : 7,
      ),
      decoration: BoxDecoration(
        color: fill.withOpacity(onGradient ? 0.2 : 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fill.withOpacity(0.45)),
      ),
      child: Text(
        label(seconds),
        style: TextStyle(
          fontSize: compact ? 12.5 : 14,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
          color: onGradient ? tokens.onHero : tokens.goldText,
        ),
      ),
    );
  }
}
