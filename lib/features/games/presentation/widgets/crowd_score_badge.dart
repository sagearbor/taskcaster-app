import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// "Waiting for the crowd" while ungraded, or "Crowd score: N/10" once the
/// post has crowd points. Pure — takes the nullable points value the caller
/// derives from a FeedPost / CrowdScorePolicy; this widget knows nothing
/// about the Arena data layer.
class CrowdScoreBadge extends StatelessWidget {
  final int? crowdPoints;

  const CrowdScoreBadge({super.key, required this.crowdPoints});

  @override
  Widget build(BuildContext context) {
    final done = crowdPoints != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: done ? AppTheme.violetSoft : Colors.grey.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            done ? Icons.emoji_events : Icons.hourglass_top,
            size: 18,
            color: done ? AppTheme.violetDeep : AppTheme.inkSoft,
          ),
          const SizedBox(width: 8),
          Text(
            done ? 'Crowd score: $crowdPoints/10' : 'Waiting for the crowd',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: done ? AppTheme.violetDeep : AppTheme.inkSoft,
            ),
          ),
        ],
      ),
    );
  }
}
