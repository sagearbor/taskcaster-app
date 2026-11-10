import 'package:flutter/material.dart';

import '../../../../core/models/game.dart';
import '../../../../core/models/player.dart';
import '../../../../core/models/task.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../bloc/peer_grading_cubit.dart';
import '../screens/ar_task_screen.dart';
import '../screens/scoreboard_screen.dart';
import '../screens/task_execution_screen.dart';
import 'up_next_card.dart';

/// The in-progress game screen. Reads top to bottom as "what do I do now?":
///
///  1. **Up next** — the current task on the hero gradient with exactly one
///     button (Start / Waiting for 3 more / Grade 4 entries). See [UpNext].
///  2. **The crew** — a horizontal strip of player avatars, a ✓ on everyone
///     whose entry for the current task is in, and their running score.
///  3. **All tasks** — collapsed by default; any task can still be opened.
class GameInProgressView extends StatelessWidget {
  final Game game;
  final String currentUserId;
  final bool isJudge;

  /// Runs the hero's action. The game screen owns routing (judging needs the
  /// screen's bloc); null falls back to opening the current task.
  final ValueChanged<UpNextAction>? onUpNext;

  /// Group-graded games (WP-13): open task [index]'s results (the animated
  /// score reveal). Null hides the "scores are in" card.
  final ValueChanged<int>? onViewResults;

  const GameInProgressView({
    super.key,
    required this.game,
    this.currentUserId = '',
    this.isJudge = false,
    this.onUpNext,
    this.onViewResults,
  });

  /// The most recently completed task of a group-graded game, or -1. Its
  /// scores locked on the server, so everyone gets the reveal card.
  int get _latestScoredTask {
    if (!game.isGroupJudged) return -1;
    for (var i = game.tasks.length - 1; i >= 0; i--) {
      if (game.tasks[i].isCompleted) return i;
    }
    return -1;
  }

  void _openTask(BuildContext context, int index) {
    final task = game.tasks[index];
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => task.isArTask
            ? ARTaskScreen(
                gameId: game.id,
                taskIndex: index,
                arGameId: task.arGameId,
              )
            : TaskExecutionScreen(gameId: game.id, taskIndex: index),
      ),
    );
  }

  void _openScoreboard(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ScoreboardScreen(game: game)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = game.currentTask;
    final upNext = UpNext.resolve(
      game,
      currentUserId: currentUserId,
      isJudge: isJudge,
      alsoGraded: game.isGroupJudged && current != null
          ? RecentPeerGrades.targets(game.id, current.id)
          : const {},
    );
    final scored = _latestScoredTask;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        if (scored >= 0 && onViewResults != null) ...[
          _ScoresInCard(
            key: ValueKey('scores-in-${game.tasks[scored].id}'),
            taskNumber: scored + 1,
            title: game.tasks[scored].title,
            myScore: game.tasks[scored].playerStatuses[currentUserId]?.score,
            onPressed: () => onViewResults!(scored),
          ),
          const SizedBox(height: 16),
        ],
        UpNextCard(
          upNext: upNext,
          taskCount: game.tasks.length,
          timerSeconds: current?.teaserSeconds,
          onPressed: () {
            if (onUpNext != null) {
              onUpNext!(upNext.action);
            } else if (upNext.action == UpNextAction.scoreboard) {
              _openScoreboard(context);
            } else if (current != null) {
              _openTask(context, game.currentTaskIndex);
            }
          },
        ),
        const SizedBox(height: 24),
        _SectionHeader(
          title: 'The crew',
          trailing: TextButton(
            onPressed: () => _openScoreboard(context),
            child: const Text('Scoreboard'),
          ),
        ),
        const SizedBox(height: 8),
        _CrewStrip(
          players: game.players,
          currentTask: current,
          currentUserId: currentUserId,
        ),
        const SizedBox(height: 20),
        _AllTasks(
          game: game,
          currentUserId: currentUserId,
          onOpen: (i) => _openTask(context, i),
        ),
      ],
    );
  }
}

/// Group-graded games: "Task 2 scores are in" — slides and fades in for
/// every player the moment the server locks a task (keyed by task, so each
/// newly scored task animates afresh), and opens the animated reveal.
class _ScoresInCard extends StatelessWidget {
  final int taskNumber;
  final String title;
  final int? myScore;
  final VoidCallback onPressed;

  const _ScoresInCard({
    super.key,
    required this.taskNumber,
    required this.title,
    required this.myScore,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, (1 - t) * 24), child: child),
      ),
      child: Card(
        key: const Key('scores-in-card'),
        color: tokens.successContainer,
        child: ListTile(
          onTap: onPressed,
          leading: Icon(Icons.emoji_events_rounded, color: tokens.gold),
          title: Text(
            'Task $taskNumber scores are in',
            style: theme.textTheme.titleMedium
                ?.copyWith(color: tokens.onSuccessContainer),
          ),
          subtitle: Text(
            myScore != null ? 'You got $myScore/10 · $title' : title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: tokens.onSuccessContainer),
          ),
          trailing: Text(
            'See results',
            style: theme.textTheme.labelLarge
                ?.copyWith(color: tokens.onSuccessContainer),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const _SectionHeader({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const Spacer(),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// Avatars in a horizontal strip, with a ✓ badge on anyone whose entry for
/// the current task is in, and each player's running score underneath.
class _CrewStrip extends StatelessWidget {
  final List<Player> players;
  final Task? currentTask;
  final String currentUserId;

  const _CrewStrip({
    required this.players,
    required this.currentTask,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: players.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          final p = players[i];
          final done =
              currentTask?.playerStatuses[p.userId]?.hasSubmitted ?? false;
          final isYou = p.userId == currentUserId;
          return SizedBox(
            width: 64,
            child: Column(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    UserAvatar(
                      displayName: p.displayName,
                      radius: 24,
                      borderColor: isYou ? theme.colorScheme.primary : null,
                    ),
                    if (done)
                      Positioned(
                        right: -4,
                        bottom: -2,
                        child: Container(
                          key: Key('crew-done-${p.userId}'),
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: tokens.success,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: theme.scaffoldBackgroundColor,
                                width: 2),
                          ),
                          child: Icon(Icons.check_rounded,
                              size: 13, color: tokens.onSuccess),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  isYou ? 'You' : p.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium,
                ),
                Text(
                  '${p.totalScore} pts',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Every task in the game, collapsed by default so the hero stays the focus.
class _AllTasks extends StatelessWidget {
  final Game game;
  final String currentUserId;
  final ValueChanged<int> onOpen;

  const _AllTasks({
    required this.game,
    required this.currentUserId,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final done = game.tasks.where((t) => t.isCompleted).length;

    if (game.tasks.isEmpty) {
      return Text(
        'No tasks yet. The judge will add some soon.',
        style: theme.textTheme.bodyMedium
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // No divider lines when the tile expands.
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const Key('all-tasks'),
          title: Text('All tasks', style: theme.textTheme.titleMedium),
          subtitle: Text(
            '$done of ${game.tasks.length} done',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          children: [
            for (var i = 0; i < game.tasks.length; i++)
              _taskRow(context, theme, tokens, i, game.tasks[i]),
          ],
        ),
      ),
    );
  }

  Widget _taskRow(BuildContext context, ThemeData theme, AppTokens tokens,
      int index, Task task) {
    final isCurrent = index == game.currentTaskIndex;
    final mine = task.playerStatuses[currentUserId];
    final String status;
    if (task.isCompleted) {
      status = 'Scored';
    } else if (mine?.hasSubmitted ?? false) {
      status = 'Your entry is in';
    } else if (isCurrent) {
      status = 'Up next';
    } else {
      status = task.isVideoTask ? 'Video' : 'Puzzle';
    }

    final Color badgeBg;
    final Color badgeFg;
    if (task.isCompleted) {
      badgeBg = tokens.success;
      badgeFg = tokens.onSuccess;
    } else if (isCurrent) {
      badgeBg = theme.colorScheme.primary;
      badgeFg = theme.colorScheme.onPrimary;
    } else {
      badgeBg = theme.colorScheme.primaryContainer;
      badgeFg = theme.colorScheme.onPrimaryContainer;
    }

    return ListTile(
      onTap: () => onOpen(index),
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: badgeBg,
        child: task.isCompleted
            ? Icon(Icons.check_rounded, size: 18, color: badgeFg)
            : Text(
                '${index + 1}',
                style: theme.textTheme.labelLarge?.copyWith(color: badgeFg),
              ),
      ),
      title: Text(
        // A gather -> reveal task stays a surprise until you have played it.
        (mine?.hasSubmitted ?? false) || task.isCompleted
            ? task.title
            : task.teaserTitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      subtitle: Text(
        status,
        style: theme.textTheme.bodySmall?.copyWith(
          color: isCurrent && !task.isCompleted
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Icon(Icons.chevron_right_rounded,
          color: theme.colorScheme.onSurfaceVariant),
    );
  }
}
