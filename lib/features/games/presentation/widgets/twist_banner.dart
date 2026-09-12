import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// The one-line twist, revealed only after the player hits Start (see
/// docs/PRODUCT_DIRECTION.md §5). Pure — renders nothing when [twist] is
/// null or blank, so callers can pass it unconditionally.
class TwistBanner extends StatelessWidget {
  final String? twist;

  const TwistBanner({super.key, required this.twist});

  @override
  Widget build(BuildContext context) {
    final text = twist?.trim();
    if (text == null || text.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.coral.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.bolt, color: AppTheme.coral, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.coral,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
