import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/models/game.dart';
import '../../../../core/models/task.dart';
import '../../../../core/models/player_task_status.dart';

/// Floating banner showing current game state
class GameStatusBanner extends StatelessWidget {
  final Game game;
  final String currentUserId;
  final bool isJudge;
  final VoidCallback? onAction;

  const GameStatusBanner({
    super.key,
    required this.game,
    required this.currentUserId,
    required this.isJudge,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final bannerInfo = _getBannerInfo();
    if (bannerInfo == null) return const SizedBox.shrink();

    return Dismissible(
      key: Key('status_banner_${game.id}_${DateTime.now()}'),
      direction: DismissDirection.horizontal,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(12),
          color: bannerInfo.backgroundColor,
          child: InkWell(
            onTap: onAction,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    bannerInfo.icon,
                    color: bannerInfo.iconColor,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          bannerInfo.title,
                          style: TextStyle(
                            color: bannerInfo.textColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        if (bannerInfo.subtitle != null)
                          Text(
                            bannerInfo.subtitle!,
                            style: TextStyle(
                              color: bannerInfo.textColor.withOpacity(0.8),
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (bannerInfo.actionText != null)
                    TextButton(
                      onPressed: onAction,
                      child: Text(
                        bannerInfo.actionText!,
                        style: TextStyle(
                          color: bannerInfo.textColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  _BannerInfo? _getBannerInfo() {
    if (game.status == GameStatus.lobby) {
      if (game.creatorId == currentUserId && game.players.length >= 2) {
        return _BannerInfo(
          title: 'Ready to start!',
          subtitle: '${game.players.length} players joined',
          icon: Icons.play_arrow,
          backgroundColor: Colors.green,
          iconColor: Colors.white,
          textColor: Colors.white,
          actionText: 'Start',
        );
      } else if (game.players.length < 2) {
        return _BannerInfo(
          title: 'Waiting for players',
          subtitle: 'Share invite code: ${game.inviteCode}',
          icon: Icons.people_outline,
          backgroundColor: Colors.orange,
          iconColor: Colors.white,
          textColor: Colors.white,
          actionText: 'Share',
        );
      }
    }

    if (game.status == GameStatus.inProgress && game.currentTask != null) {
      // Safe getter avoids a RangeError if currentTaskIndex is out of bounds.
      final currentTask = game.currentTask!;

      // Non-playing judge (asymmetric modes like House Hunt: the hider only
      // judges, the seeker plays). Such a judge is never seeded a per-task
      // playerStatus, so we must drive the banner from the TASK state — not the
      // judge's (absent) status. Without this, the judge falls through to the
      // player branches below (playerStatus == null) and gets routed into the
      // seeker's submit UI, and could never reach judging.
      if (isJudge && !game.settings.judgePlays) {
        final hasUnjudgedSubmissions =
            currentTask.submittedCount > currentTask.judgedCount;
        if (currentTask.status == TaskStatus.ready_to_judge ||
            hasUnjudgedSubmissions) {
          return _BannerInfo(
            title: 'Ready to judge!',
            subtitle: 'The seeker has submitted — score their find',
            icon: Icons.gavel,
            backgroundColor: Colors.purple,
            iconColor: Colors.white,
            textColor: Colors.white,
            actionText: 'Judge',
          );
        }
        if (currentTask.status != TaskStatus.completed) {
          // Waiting on the seeker: an info banner with no action (tapping it
          // must never open the seeker's submit UI).
          return _BannerInfo(
            title: 'Waiting for the seeker…',
            subtitle: 'They\'re hunting down "${currentTask.title}"',
            icon: Icons.hourglass_empty,
            backgroundColor: Colors.indigo,
            iconColor: Colors.white,
            textColor: Colors.white,
          );
        }
        // Task just completed and the game hasn't advanced yet — no banner.
        return null;
      }

      final playerStatus = currentTask.playerStatuses[currentUserId];

      // Check submission status for current player
      if (playerStatus?.state == TaskPlayerState.not_started) {
        return _BannerInfo(
          title: 'New task available!',
          subtitle: currentTask.title,
          icon: Icons.assignment,
          backgroundColor: Colors.blue,
          iconColor: Colors.white,
          textColor: Colors.white,
          actionText: 'View',
        );
      }

      if (playerStatus?.state == TaskPlayerState.in_progress) {
        final deadline = currentTask.deadline;
        if (deadline != null) {
          final timeRemaining = deadline.difference(DateTime.now());
          if (timeRemaining.inHours < 1) {
            return _BannerInfo(
              title: 'Time running out!',
              subtitle: 'Submit your video soon',
              icon: Icons.timer,
              backgroundColor: Colors.red,
              iconColor: Colors.white,
              textColor: Colors.white,
              actionText: 'Submit',
            );
          }
        }
        return _BannerInfo(
          title: 'Task in progress',
          subtitle: 'Don\'t forget to submit!',
          icon: Icons.hourglass_empty,
          backgroundColor: Colors.amber,
          iconColor: AppTheme.ink,
          textColor: AppTheme.ink,
        );
      }

      if (playerStatus?.state == TaskPlayerState.submitted) {
        // Count submissions
        final submittedCount = currentTask.playerStatuses.values
            .where((status) => status.state == TaskPlayerState.submitted)
            .length;
        // Denominator is the number of EXPECTED submitters (the players seeded a
        // per-task status), not every player — in judgePlays=false games the
        // judge is excluded from statuses, so game.players.length would never be
        // reachable (n/n could never show).
        final expectedSubmitters = currentTask.playerStatuses.length;

        if (submittedCount < expectedSubmitters) {
          return _BannerInfo(
            title: 'Submission received!',
            subtitle:
                'Waiting for others ($submittedCount/$expectedSubmitters done)',
            icon: Icons.check_circle,
            backgroundColor: Colors.green,
            iconColor: Colors.white,
            textColor: Colors.white,
          );
        }

        if (isJudge && currentTask.status == TaskStatus.ready_to_judge) {
          return _BannerInfo(
            title: 'Ready to judge!',
            subtitle: 'All submissions are in',
            icon: Icons.gavel,
            backgroundColor: Colors.purple,
            iconColor: Colors.white,
            textColor: Colors.white,
            actionText: 'Judge',
          );
        }
      }

      if (currentTask.status == TaskStatus.judging) {
        if (!isJudge) {
          return _BannerInfo(
            title: 'Judge is reviewing',
            subtitle: 'Scores coming soon...',
            icon: Icons.hourglass_full,
            backgroundColor: Colors.indigo,
            iconColor: Colors.white,
            textColor: Colors.white,
          );
        }
      }

      if (currentTask.status == TaskStatus.completed) {
        // Check if there are player scores
        final hasScores = currentTask.playerStatuses.values
            .any((status) => status.score != null && status.score! > 0);

        if (hasScores) {
          final playerScore = currentTask.playerStatuses[currentUserId]?.score;
          if (playerScore != null) {
            // Calculate position
            final scores = currentTask.playerStatuses.entries
                .where((e) => e.value.score != null)
                .map((e) => e.value.score!)
                .toList()
              ..sort((a, b) => b.compareTo(a));
            final position = scores.indexOf(playerScore) + 1;

            return _BannerInfo(
              title: 'Scores posted!',
              subtitle: 'You got $playerScore/5 points (#$position place)',
              icon: Icons.emoji_events,
              backgroundColor: position == 1 ? Colors.amber : Colors.teal,
              iconColor: Colors.white,
              textColor: Colors.white,
              actionText: 'View',
            );
          }
        }
      }
    }

    if (game.status == GameStatus.completed) {
      // Calculate winner
      final playerScores = <String, int>{};
      for (final player in game.players) {
        playerScores[player.userId] = player.totalScore;
      }

      final sortedScores = playerScores.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      if (sortedScores.isNotEmpty) {
        final winnerId = sortedScores.first.key;
        final winnerName = game.players
            .firstWhere((p) => p.userId == winnerId)
            .displayName;

        if (winnerId == currentUserId) {
          return _BannerInfo(
            title: 'You won! 🎉',
            subtitle: 'Final score: ${sortedScores.first.value} points',
            icon: Icons.emoji_events,
            backgroundColor: Colors.amber,
            iconColor: AppTheme.ink,
            textColor: AppTheme.ink,
          );
        } else {
          final yourScore = playerScores[currentUserId] ?? 0;
          final yourPosition = sortedScores
              .indexWhere((e) => e.key == currentUserId) + 1;

          return _BannerInfo(
            title: 'Game complete!',
            subtitle: '$winnerName won! You placed #$yourPosition with $yourScore points',
            icon: Icons.flag,
            backgroundColor: Colors.blueGrey,
            iconColor: Colors.white,
            textColor: Colors.white,
          );
        }
      }
    }

    return null;
  }
}

class _BannerInfo {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color backgroundColor;
  final Color iconColor;
  final Color textColor;
  final String? actionText;

  _BannerInfo({
    required this.title,
    this.subtitle,
    required this.icon,
    required this.backgroundColor,
    required this.iconColor,
    required this.textColor,
    this.actionText,
  });
}