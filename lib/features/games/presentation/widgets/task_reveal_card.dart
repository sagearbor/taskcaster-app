import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import 'timer_pill.dart';

/// The envelope-opening moment: task title, description and timer pill. The
/// [twist] line only ever appears once the player has hit Start (pass null
/// beforehand) — see docs/PRODUCT_DIRECTION.md §5. Pure/stateless: plain
/// strings and an int in, a card out. Used by the cold open and the task
/// screen alike so both look identical.
class TaskRevealCard extends StatelessWidget {
  final String title;
  final String description;
  final int? timerSeconds;
  final String? twist;
  final String overline;

  const TaskRevealCard({
    super.key,
    required this.title,
    required this.description,
    this.timerSeconds,
    this.twist,
    this.overline = 'YOUR TASK, SHOULD YOU ACCEPT IT…',
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.violet, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              overline,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.violetDeep,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              description,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (timerSeconds != null) ...[
              const SizedBox(height: 14),
              TimerPill(seconds: timerSeconds!),
            ],
            if (twist != null && twist!.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
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
                        twist!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppTheme.coral,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
