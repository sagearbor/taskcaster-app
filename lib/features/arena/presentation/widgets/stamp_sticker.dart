import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// The auto-stamp shown on every Arena post ("NAILED IT", "TECHNICALLY",
/// "SEND HELP", "ART", "NO REGRETS", "DON'T ASK" — see `Stamps.values` and
/// `AutoEdit.stamp`). Never player-chosen: the whole point is that nobody
/// picked it, the timing did.
///
/// Rendered as a slightly rotated gold sticker, like it was slapped on after
/// the fact.
class StampSticker extends StatelessWidget {
  final String stamp;

  const StampSticker(this.stamp, {super.key});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -8 * 3.1415926535 / 180,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.goldBright,
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          stamp,
          style: const TextStyle(
            fontFamily: 'Fredoka',
            fontWeight: FontWeight.w700,
            fontSize: 13,
            letterSpacing: 0.4,
            color: AppTheme.ink,
          ),
        ),
      ),
    );
  }
}
