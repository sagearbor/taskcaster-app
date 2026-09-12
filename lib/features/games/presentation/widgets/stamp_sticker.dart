import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// The auto-chosen stamp ('NAILED IT', 'TECHNICALLY', 'SEND HELP', 'ART',
/// 'NO REGRETS', "DON'T ASK"), rendered as a rotated sticker — like something
/// slapped on a photo, never a manually-placed one (see AutoEdit; there is no
/// stamp picker anywhere in this app). Pure: takes the stamp string, picks a
/// deterministic tilt + color from it.
class StampSticker extends StatelessWidget {
  final String stamp;
  final double scale;

  const StampSticker({super.key, required this.stamp, this.scale = 1.0});

  static const Map<String, Color> _colors = {
    'NAILED IT': Color(0xFF16A34A),
    'TECHNICALLY': AppTheme.gold,
    'NO REGRETS': AppTheme.violet,
    "DON'T ASK": AppTheme.coral,
    'ART': Color(0xFF0EA5E9),
    'SEND HELP': Color(0xFFE0395E),
  };

  Color get _color => _colors[stamp] ?? AppTheme.violet;

  /// Deterministic tilt in [-8, 8] degrees derived from the stamp text so the
  /// same stamp always looks the same, without needing a Random seed.
  double get _tiltDegrees {
    final h = stamp.codeUnits.fold<int>(0, (a, b) => a + b);
    return (h % 17) - 8;
  }

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: _tiltDegrees * 3.1415926535 / 180,
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: 16 * scale, vertical: 8 * scale),
        decoration: BoxDecoration(
          color: _color,
          borderRadius: BorderRadius.circular(6 * scale),
          border: Border.all(color: Colors.white, width: 2.5 * scale),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Text(
          stamp,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 16 * scale,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }
}
