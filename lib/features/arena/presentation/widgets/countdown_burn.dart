import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

/// The TASK clock, drawn over a clip in the bottom-right corner.
///
/// Every in-app video rendering — the pre-post preview, the Arena card and
/// Watch together — draws the same pill from the same three numbers, so a clip
/// looks identical wherever it is watched. A later server pass burns the same
/// clock into the pixels for export; this widget is what makes the in-app view
/// agree with it.
///
/// The value is `timerSeconds - clockOffsetSeconds - position`, floored at
/// zero: [clockOffsetSeconds] is how much of the task clock had already run
/// when the recorder opened, so a clip filmed 40 s into a 90 s task starts its
/// countdown at 50 s, exactly like the player's own screen did.
///
/// House clips have the clock burned in already, so callers skip this widget
/// for `post.isHouse` entries rather than double-drawing it.
class CountdownBurn extends StatelessWidget {
  /// The task's `durationSeconds`. Null means the task had no clock, and
  /// nothing is drawn.
  final int? timerSeconds;

  /// Seconds of the task clock already spent when the recorder opened.
  final int? clockOffsetSeconds;

  /// Playback position within the clip, in seconds.
  final double positionSeconds;

  /// The post's LATE flag. Only a late post is allowed to show `LATE` once the
  /// clock would go negative; an on-time clip just sits at `0:00`.
  final bool isLate;

  const CountdownBurn({
    super.key,
    required this.timerSeconds,
    required this.clockOffsetSeconds,
    required this.positionSeconds,
    this.isLate = false,
  });

  /// Seconds left on the task clock, or null when there is no clock to draw.
  /// Negative values are returned as-is so [label] can tell "ran out" from
  /// "nearly out".
  static double? remaining({
    required int? timerSeconds,
    required int? clockOffsetSeconds,
    required double positionSeconds,
  }) {
    if (timerSeconds == null || timerSeconds <= 0) return null;
    final position =
        positionSeconds.isNaN || positionSeconds < 0 ? 0.0 : positionSeconds;
    return timerSeconds - (clockOffsetSeconds ?? 0) - position;
  }

  /// What the pill reads: `M:SS`, or `LATE` once a late clip's clock has run
  /// out. Null when there is nothing to draw.
  static String? label({
    required int? timerSeconds,
    required int? clockOffsetSeconds,
    required double positionSeconds,
    bool isLate = false,
  }) {
    final left = remaining(
      timerSeconds: timerSeconds,
      clockOffsetSeconds: clockOffsetSeconds,
      positionSeconds: positionSeconds,
    );
    if (left == null) return null;
    if (left < 0 && isLate) return 'LATE';
    final clamped = left < 0 ? 0 : left.ceil();
    final minutes = clamped ~/ 60;
    final seconds = clamped % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// True once the clock is inside the last ten seconds (or gone) — the pill
  /// turns red.
  static bool isBurning({
    required int? timerSeconds,
    required int? clockOffsetSeconds,
    required double positionSeconds,
  }) {
    final left = remaining(
      timerSeconds: timerSeconds,
      clockOffsetSeconds: clockOffsetSeconds,
      positionSeconds: positionSeconds,
    );
    return left != null && left <= 10;
  }

  @override
  Widget build(BuildContext context) {
    final text = label(
      timerSeconds: timerSeconds,
      clockOffsetSeconds: clockOffsetSeconds,
      positionSeconds: positionSeconds,
      isLate: isLate,
    );
    if (text == null) return const SizedBox.shrink();

    final burning = isBurning(
      timerSeconds: timerSeconds,
      clockOffsetSeconds: clockOffsetSeconds,
      positionSeconds: positionSeconds,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: burning
            ? const Color(0xFFE0395E).withOpacity(0.92)
            : Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: const TextStyle(
          // Monospace so the digits do not jitter as the clock runs.
          fontFamily: 'monospace',
          fontFeatures: [FontFeature.tabularFigures()],
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          height: 1.2,
        ),
      ),
    );
  }
}
