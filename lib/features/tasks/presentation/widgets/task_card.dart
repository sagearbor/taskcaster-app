import 'package:flutter/material.dart';
import '../../../../core/models/task.dart';

class TaskCard extends StatelessWidget {
  final Task task;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const TaskCard({
    super.key,
    required this.task,
    this.isSelected = false,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: isSelected ? 4 : 1,
      color: isSelected
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Icon and Type Badge
              Row(
                children: [
                  Icon(
                    _getIconForTaskType(task.taskType),
                    size: 24,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildTypeBadge(context),
                  ),
                  if (isSelected)
                    Icon(
                      Icons.check_circle,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // Title
              Text(
                task.title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),

              // Description
              Text(
                task.description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),

              // Duration (if available)
              if (task.durationSeconds != null)
                Row(
                  children: [
                    Icon(
                      Icons.timer,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _formatDuration(task.durationSeconds!),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getIconForTaskType(TaskType type) {
    switch (type) {
      case TaskType.video:
        return Icons.videocam;
      case TaskType.puzzle:
        return Icons.extension;
      case TaskType.ar:
        return Icons.view_in_ar;
    }
  }

  Widget _buildTypeBadge(BuildContext context) {
    final color = task.taskType == TaskType.video
        ? Colors.red[100]
        : Colors.blue[100];
    final textColor = task.taskType == TaskType.video
        ? Colors.red[900]
        : Colors.blue[900];

    // Prefer the library category ("Quick & Silly") over the bare task type —
    // it tells players far more about what they're picking.
    final label = task.category?.toUpperCase() ??
        (task.taskType == TaskType.video ? 'VIDEO' : 'PUZZLE');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) {
      return '${seconds}s';
    } else {
      final minutes = (seconds / 60).floor();
      final remainingSeconds = seconds % 60;
      if (remainingSeconds == 0) {
        return '${minutes}m';
      } else {
        return '${minutes}m ${remainingSeconds}s';
      }
    }
  }
}