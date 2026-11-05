import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/models/community_task.dart';
import '../../../../core/models/task.dart';
import '../../../../core/theme/app_theme.dart';

class CommunityTaskCard extends StatelessWidget {
  final CommunityTask task;
  final VoidCallback onUpvote;
  final VoidCallback onUse;

  const CommunityTaskCard({
    super.key,
    required this.task,
    required this.onUpvote,
    required this.onUse,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with task type and upvotes
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: task.taskType == TaskType.video 
                        ? Theme.of(context).colorScheme.error.withOpacity(0.1)
                        : context.tokens.info.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: task.taskType == TaskType.video 
                          ? Theme.of(context).colorScheme.error
                          : context.tokens.info,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        task.taskType == TaskType.video ? Icons.videocam : Icons.quiz,
                        size: 16,
                        color: task.taskType == TaskType.video 
                            ? Theme.of(context).colorScheme.error
                            : context.tokens.info,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        task.taskType == TaskType.video ? 'Video' : 'Puzzle',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: task.taskType == TaskType.video 
                              ? Theme.of(context).colorScheme.error
                              : context.tokens.info,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Row(
                  children: [
                    Icon(
                      Icons.thumb_up,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${task.upvotes}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Title
            Text(
              task.title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),

            // Description
            Text(
              task.description,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),

            // Metadata
            Row(
              children: [
                Icon(
                  Icons.person,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  'by Player ${task.submittedBy.substring(0, 8)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 16),
                Icon(
                  Icons.schedule,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  DateFormat('MMM d, y').format(task.createdAt),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Action Buttons
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: onUpvote,
                  icon: const Icon(Icons.thumb_up_outlined, size: 16),
                  label: const Text('Upvote'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: onUse,
                  icon: const Icon(Icons.add_circle_outline, size: 16),
                  label: const Text('Use in Game'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}