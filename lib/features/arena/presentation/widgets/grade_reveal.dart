import 'package:flutter/material.dart';

import '../../domain/models/feed_post.dart';
import 'stamp_sticker.dart';

/// What the crowd thought, the moment after the viewer grades a post: "You 4 ·
/// Crowd 3.2 (12 grades)" plus a one-word verdict on the viewer's taste.
///
/// The crowd mean INCLUDES the viewer's own grade: the post the viewer was
/// shown is the pre-grade snapshot, so the viewer's score is folded in here
/// rather than waiting for the grade transaction to echo back.
class GradeReveal {
  /// The post that was just graded (pre-grade snapshot).
  final FeedPost post;

  /// The viewer's grade, 1..5.
  final int you;

  /// Grades including the viewer's.
  final int count;

  /// Mean grade including the viewer's.
  final double crowdMean;

  const GradeReveal._({
    required this.post,
    required this.you,
    required this.count,
    required this.crowdMean,
  });

  factory GradeReveal.of(FeedPost post, int score) {
    final count = post.gradeCount + 1;
    return GradeReveal._(
      post: post,
      you: score,
      count: count,
      crowdMean: (post.gradeSum + score) / count,
    );
  }

  /// How far from the mean still counts as agreeing with the crowd.
  static const double inTuneTolerance = 0.5;

  static const String inTune = 'IN TUNE';
  static const String generous = 'GENEROUS';
  static const String harsh = 'HARSH';
  static const String firstGradeLine = 'First grade. You set the bar.';

  /// Nobody had graded it before the viewer.
  bool get isFirst => count == 1;

  /// The crowd's mean to one decimal: "3.2".
  String get crowdLabel => crowdMean.toStringAsFixed(1);

  /// "12 grades".
  String get countLabel => '$count grade${count == 1 ? '' : 's'}';

  /// "You: 4 · Crowd: 3.2 (12 grades)" — also the screen-reader summary.
  String get summary => isFirst
      ? 'You: $you. $firstGradeLine'
      : 'You: $you · Crowd: $crowdLabel ($countLabel)';

  /// IN TUNE / GENEROUS / HARSH, or null on the first grade (no crowd yet).
  String? get verdict {
    if (isFirst) return null;
    final diff = you - crowdMean;
    if (diff.abs() <= inTuneTolerance) return inTune;
    return diff > 0 ? generous : harsh;
  }

  /// A crowd average that rounds to 5: worth a fanfare.
  bool get isCrowdFive => crowdMean >= 4.5;
}

/// The reveal, laid over the graded post's media. Fades in fast, holds while
/// the Arena waits, and says how to skip the wait. The caller owns the timing
/// and the tap.
class GradeRevealOverlay extends StatelessWidget {
  final GradeReveal reveal;

  const GradeRevealOverlay({super.key, required this.reveal});

  static const String skipHint = 'Tap to skip';

  @override
  Widget build(BuildContext context) {
    final verdict = reveal.verdict;
    return Semantics(
      liveRegion: true,
      label: reveal.summary,
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        key: const Key('grade-reveal'),
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.scale(scale: 0.94 + 0.06 * t, child: child),
        ),
        child: DecoratedBox(
          // Near-opaque: a text entry's big white words must not read
          // through the numbers. The clip keeps playing underneath.
          decoration: BoxDecoration(
            color: const Color(0xFF120C22).withOpacity(0.9),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Spacer(),
                if (reveal.isFirst)
                  _Figure(label: 'You', value: '${reveal.you}')
                else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: _Figure(label: 'You', value: '${reveal.you}'),
                      ),
                      Container(
                        width: 1,
                        height: 56,
                        margin: const EdgeInsets.symmetric(horizontal: 24),
                        color: Colors.white24,
                      ),
                      Flexible(
                        child: _Figure(
                          label: 'Crowd',
                          value: reveal.crowdLabel,
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 8),
                Text(
                  reveal.isFirst
                      ? GradeReveal.firstGradeLine
                      : reveal.countLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (verdict != null) ...[
                  const SizedBox(height: 18),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 1.8, end: 1),
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutBack,
                    builder: (context, s, child) =>
                        Transform.scale(scale: s, child: child),
                    child: StampSticker(verdict),
                  ),
                ],
                const Spacer(),
                const Text(
                  skipHint,
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  final String label;
  final String value;

  const _Figure({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: const TextStyle(
              fontFamily: 'Fredoka',
              fontWeight: FontWeight.w700,
              fontSize: 52,
              height: 1.1,
              color: Colors.white,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}
