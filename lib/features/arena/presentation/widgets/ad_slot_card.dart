import 'package:flutter/material.dart';

import '../../../../core/config/environment.dart';
import '../../../../core/theme/app_theme.dart';

/// A placeholder ad slot shown every [ArenaLoaded.adEvery] posts in the
/// Arena queue (see docs/PRODUCT_DIRECTION.md §2.6). No real ad SDK is wired
/// up tonight — this is layout + cadence only, gated by [AppConfig.adsEnabled]
/// so it renders as nothing (not even a blank slot) while ads are off.
///
/// [debugAlwaysShow] lets tests and screenshots force the card to render
/// even with ads disabled, so the cadence logic stays covered without
/// flipping the real flag.
class AdSlotCard extends StatelessWidget {
  final VoidCallback? onContinue;

  const AdSlotCard({super.key, this.onContinue});

  /// Test/screenshot-only override. Never set outside test code.
  static bool debugAlwaysShow = false;

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.adsEnabled && !debugAlwaysShow) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sponsored',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppTheme.inkSoft,
                    letterSpacing: 0.6,
                  ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 140,
              width: double.infinity,
              child: CustomPaint(
                painter: _DashedBorderPainter(color: AppTheme.inkSoft),
                child: Center(
                  child: Text(
                    'Ad',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: AppTheme.inkSoft,
                        ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onContinue,
                child: const Text('Continue'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Simple dashed rounded-rect border for the ad placeholder box — Flutter has
/// no built-in dashed [Border], so this paints one directly.
class _DashedBorderPainter extends CustomPainter {
  final Color color;
  static const double _dashWidth = 6;
  static const double _dashGap = 4;
  static const double _radius = 12;

  const _DashedBorderPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(_radius),
    );
    final path = Path()..addRRect(rrect);

    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final next = distance + _dashWidth;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + _dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color;
}
