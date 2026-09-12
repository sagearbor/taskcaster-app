import 'package:flutter/material.dart';

/// Small red "LATE" chip shown next to a submitted entry — never a blocker,
/// just a visible, funny badge (see docs/PRODUCT_DIRECTION.md §2.1).
class LateBadge extends StatelessWidget {
  const LateBadge({super.key});

  static const Color _red = Color(0xFFE0395E);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _red,
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_fire_department, size: 13, color: Colors.white),
          SizedBox(width: 4),
          Text(
            'LATE',
            style: TextStyle(
              color: Colors.white,
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
