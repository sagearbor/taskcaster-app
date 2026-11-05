import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Small "LATE" chip (the theme's late token) shown next to a submitted entry — never a blocker,
/// just a visible, funny badge (see docs/PRODUCT_DIRECTION.md §2.1).
class LateBadge extends StatelessWidget {
  const LateBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: tokens.late,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_fire_department, size: 13, color: tokens.onLate),
          const SizedBox(width: 4),
          Text(
            'LATE',
            style: TextStyle(
              color: tokens.onLate,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}
