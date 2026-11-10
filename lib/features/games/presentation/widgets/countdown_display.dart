import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Pure/stateless "big digits" countdown — the hero of the task screen once
/// the player has hit Start. Takes plain values so it is trivially unit- and
/// widget-testable; the ticking (a Timer keyed off `startedAt`) lives in the
/// stateful wrapper that owns the real clock.
///
/// Rules (see docs/PRODUCT_DIRECTION.md §2.1 and CONTRACTS.md):
/// - `remainingSeconds >= 0`: normal countdown. In the last 10 s it turns
///   coral and the digits pulse (1.08 -> 1.0) once per second, unless the
///   platform asks for reduced motion.
/// - `remainingSeconds <= 0` and not yet late (within the grace period):
///   shows 0:00 in coral with the "Overtime" line — not blocking.
/// - `isLate == true`: shows a red "LATE" chip instead of the clock digits.
///   Never disables anything — the caller decides what buttons stay live.
class CountdownDisplay extends StatelessWidget {
  final int remainingSeconds;
  final bool isLate;

  /// Grace period past zero before LATE, for the overtime line.
  final int graceSeconds;

  const CountdownDisplay({
    super.key,
    required this.remainingSeconds,
    this.isLate = false,
    this.graceSeconds = 30,
  });

  /// Peak scale of the once-a-second pulse in the last 10 s.
  static const double pulseScale = 1.08;

  String _format(int seconds) {
    final clamped = seconds < 0 ? 0 : seconds;
    final minutes = clamped ~/ 60;
    final secs = clamped % 60;
    return '${minutes.toString().padLeft(1, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    if (isLate) {
      final late = tokens.late;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
            decoration: BoxDecoration(
              color: late.withOpacity(0.14),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: late, width: 2),
            ),
            child: Text(
              'LATE',
              style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
                color: late,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Posting late still counts — send it',
            style: TextStyle(fontSize: 13, color: late),
          ),
        ],
      );
    }

    final urgent = remainingSeconds <= 10;
    // Brand violet while there is time; coral (the show's panic colour) for
    // the last 10 s and the overtime.
    final color = urgent ? AppTheme.coral : scheme.primary;
    // The small lines keep the theme's error red: coral is too light for
    // 13 px text on the light background.
    final lineColor = urgent ? scheme.error : scheme.primary;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    Widget digits = Text(
      _format(remainingSeconds),
      key: const Key('countdown-digits'),
      style: TextStyle(
        fontFamily: 'Fredoka',
        fontSize: 76,
        fontWeight: FontWeight.w800,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: color,
        height: 1.0,
      ),
    );
    if (urgent && remainingSeconds > 0 && !reduceMotion) {
      // Keyed on the second, so each new number starts the pulse again:
      // one beat per second without a repeating controller.
      digits = TweenAnimationBuilder<double>(
        key: ValueKey<int>(remainingSeconds),
        tween: Tween(begin: pulseScale, end: 1.0),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
        builder: (context, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: digits,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        digits,
        if (remainingSeconds <= 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              "Overtime: $graceSeconds s grace, then it's LATE",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: lineColor,
              ),
            ),
          )
        else if (urgent)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Hurry',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: lineColor,
              ),
            ),
          ),
      ],
    );
  }
}
