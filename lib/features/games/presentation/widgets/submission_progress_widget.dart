import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/models/player_task_status.dart';

class SubmissionProgressWidget extends StatelessWidget {
  final Map<String, PlayerTaskStatus> playerStatuses;
  final String currentUserId;

  const SubmissionProgressWidget({
    super.key,
    required this.playerStatuses,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    final submittedCount =
        playerStatuses.values.where((s) => s.hasSubmitted).length;
    final totalPlayers = playerStatuses.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Submission Progress',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _getProgressColor(submittedCount, totalPlayers)
                        .withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$submittedCount / $totalPlayers',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: _getProgressColor(submittedCount, totalPlayers),
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: totalPlayers > 0 ? submittedCount / totalPlayers : 0,
              backgroundColor: AppTheme.violetSoft,
              valueColor: AlwaysStoppedAnimation<Color>(
                _getProgressColor(submittedCount, totalPlayers),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: playerStatuses.entries.map((entry) {
                final playerId = entry.key;
                final status = entry.value;
                final isCurrentUser = playerId == currentUserId;

                return _buildPlayerChip(
                  context,
                  playerId,
                  status,
                  isCurrentUser,
                );
              }).toList(),
            ),
            if (totalPlayers > 0 && submittedCount == totalPlayers) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'All players have submitted! Ready for judging.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.green[300],
                              fontWeight: FontWeight.bold,
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

  Widget _buildPlayerChip(
    BuildContext context,
    String playerId,
    PlayerTaskStatus status,
    bool isCurrentUser,
  ) {
    IconData icon;
    Color iconColor;
    String statusText;

    switch (status.state) {
      case TaskPlayerState.submitted:
      case TaskPlayerState.judged:
        icon = Icons.check_circle;
        iconColor = Colors.green;
        statusText = 'Submitted';
        break;
      case TaskPlayerState.in_progress:
        icon = Icons.hourglass_empty;
        iconColor = Colors.orange;
        statusText = 'In Progress';
        break;
      case TaskPlayerState.skipped:
        icon = Icons.skip_next;
        iconColor = Theme.of(context).colorScheme.onSurfaceVariant;
        statusText = 'Skipped';
        break;
      case TaskPlayerState.not_started:
      default:
        icon = Icons.circle_outlined;
        iconColor = Theme.of(context).colorScheme.onSurfaceVariant;
        statusText = 'Not Started';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: isCurrentUser
            ? Theme.of(context).colorScheme.secondary.withOpacity(0.1)
            : AppTheme.violetSoft.withOpacity(0.5),
        borderRadius: BorderRadius.circular(20),
        border: isCurrentUser
            ? Border.all(
                color: Theme.of(context).colorScheme.secondary,
                width: 2,
              )
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Avatar (first letter of player ID)
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: _getAvatarColor(playerId),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                playerId.isNotEmpty ? playerId[0].toUpperCase() : '?',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isCurrentUser ? 'You' : _getShortPlayerId(playerId),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight:
                              isCurrentUser ? FontWeight.bold : FontWeight.normal,
                        ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    icon,
                    size: 14,
                    color: iconColor,
                  ),
                ],
              ),
              if (status.submittedAt != null)
                Text(
                  _formatSubmissionTime(status.submittedAt!),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getProgressColor(int submitted, int total) {
    if (submitted == total) return Colors.green;
    if (submitted >= total / 2) return Colors.orange;
    return Colors.red;
  }

  Color _getAvatarColor(String playerId) {
    // Generate a consistent color based on player ID
    final hash = playerId.hashCode;
    final colors = [
      Colors.blue,
      Colors.purple,
      Colors.pink,
      Colors.teal,
      Colors.indigo,
      Colors.deepOrange,
      Colors.cyan,
      Colors.lime,
    ];
    return colors[hash % colors.length];
  }

  String _getShortPlayerId(String playerId) {
    // Return first 8 characters or "Player" if too short
    if (playerId.length > 8) {
      return playerId.substring(0, 8);
    }
    return playerId;
  }

  String _formatSubmissionTime(DateTime submittedAt) {
    final now = DateTime.now();
    final difference = now.difference(submittedAt);

    if (difference.inMinutes < 1) {
      return 'Just now';
    }
    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    }
    if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    }
    return '${difference.inDays}d ago';
  }
}