import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Pure/stateless "big digits" countdown — the hero of the task screen once
/// the player has hit Start. Takes plain values so it is trivially unit- and
/// widget-testable; the ticking (a Timer keyed off `startedAt`) lives in the
/// stateful wrapper that owns the real clock.
///
/// Rules (see docs/PRODUCT_DIRECTION.md §2.1 and CONTRACTS.md):
/// - `remainingSeconds >= 0`: normal countdown, turns red in the last 10 s.
/// - `remainingSeconds < 0` and not yet late (within the 30 s grace):
///   shows 00:00 in red — "overtime" but not blocking.
/// - `isLate == true`: shows a red "LATE" chip instead of the clock digits.
///   Never disables anything — the caller decides what buttons stay live.
class CountdownDisplay extends StatelessWidget {
  final int remainingSeconds;
  final bool isLate;

  const CountdownDisplay({
    super.key,
    required this.remainingSeconds,
    this.isLate = false,
  });

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
    // Brand violet while there is time; the error colour for the last 10 s.
    final color = urgent ? scheme.error : scheme.primary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _format(remainingSeconds),
          style: TextStyle(
            fontFamily: 'Fredoka',
            fontSize: 76,
            fontWeight: FontWeight.w800,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: color,
            height: 1.0,
          ),
        ),
        if (remainingSeconds <= 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Time is up — 30 s grace before LATE',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
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
                color: color,
              ),
            ),
          ),
      ],
    );
  }
}
