import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/models/game.dart';
import '../../../../core/models/player_task_status.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/user_avatar.dart';

class GameCard extends StatelessWidget {
  final Game game;
  final VoidCallback onTap;

  const GameCard({
    super.key,
    required this.game,
    required this.onTap,
  });

  static Color _statusColor(GameStatus s) {
    switch (s) {
      case GameStatus.lobby:
        return AppTheme.gold;
      case GameStatus.inProgress:
        return AppTheme.violet;
      case GameStatus.completed:
        return AppTheme.coral;
    }
  }

  /// Solo, crowd-judged games (the Starter Pack, and the daily game whose
  /// `Game.isDaily` lands separately in WP-6). No crew to list.
  bool get _isSolo => game.isStarter || game.gameKind == 'daily';

  /// "1 player" / "3 players".
  static String playersLabel(int n) => n == 1 ? '1 player' : '$n players';

  /// "7 of 10 graded · 34 pts": how many of the creator's entries have a
  /// crowd score locked in, and their total.
  static String soloProgressLabel(Game game) {
    var graded = 0;
    var points = 0;
    for (final t in game.tasks) {
      final s = t.playerStatuses[game.creatorId];
      if (s?.state == TaskPlayerState.judged) {
        graded++;
        points += s?.score ?? 0;
      }
    }
    return '$graded of ${game.tasks.length} graded · $points pts';
  }

  @override
  Widget build(BuildContext context) {
    final accent = _statusColor(game.status);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [accent, Color.lerp(accent, Colors.black, 0.18)!],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                            color: accent.withOpacity(0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4)),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      game.gameName.isNotEmpty
                          ? game.gameName[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                          fontFamily: 'Fredoka',
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          color: UserAvatar.foregroundFor(accent)),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      game.gameName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  _StatusChip(status: game.status),
                ],
              ),
              const SizedBox(height: 14),
              if (_isSolo)
                Row(
                  children: [
                    Icon(Icons.star_rounded, size: 16, color: muted),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        soloProgressLabel(game),
                        key: const Key('game-card-solo-progress'),
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: muted),
                      ),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Icon(Icons.people, size: 16, color: muted),
                    const SizedBox(width: 4),
                    Text(
                      playersLabel(game.players.length),
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: muted),
                    ),
                    const SizedBox(width: 16),
                    Icon(Icons.assignment, size: 16, color: muted),
                    const SizedBox(width: 4),
                    Text(
                      game.tasks.length == 1
                          ? '1 task'
                          : '${game.tasks.length} tasks',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: muted),
                    ),
                  ],
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.schedule,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Created ${DateFormat('MMM d, y').format(game.createdAt)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  if (game.isInLobby)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: context.tokens.gold.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: context.tokens.gold,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        'Code: ${game.inviteCode}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.tokens.goldText,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              // A solo game's only player is you; a lone "Guest" chip read
              // like test data.
              if (game.players.isNotEmpty && !_isSolo) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: game.players.take(4).map((player) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Text(
                        player.displayName,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    );
                  }).toList(),
                ),
                if (game.players.length > 4)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '+ ${game.players.length - 4} more',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final GameStatus status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    late final Color accent;
    late final Color textColor;
    late final String text;

    switch (status) {
      case GameStatus.lobby:
        accent = tokens.gold;
        textColor = tokens.goldText;
        text = 'Lobby';
        break;
      case GameStatus.inProgress:
        accent = Theme.of(context).colorScheme.primary;
        textColor = accent;
        text = 'Live';
        break;
      case GameStatus.completed:
        accent = tokens.coral;
        textColor = tokens.coralText;
        text = 'Done';
        break;
    }
    final backgroundColor = accent.withOpacity(0.14);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: textColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}