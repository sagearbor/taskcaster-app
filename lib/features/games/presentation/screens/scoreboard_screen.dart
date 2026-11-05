import 'package:flutter/material.dart';

import '../../../../core/models/game.dart';
import '../../../../core/models/player.dart';
import '../../../../core/theme/app_theme.dart';

class ScoreboardScreen extends StatelessWidget {
  final Game game;

  const ScoreboardScreen({
    super.key,
    required this.game,
  });

  @override
  Widget build(BuildContext context) {
    // Sort players by total score (highest first)
    final sortedPlayers = List<Player>.from(game.players)
      ..sort((a, b) => b.totalScore.compareTo(a.totalScore));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scoreboard'),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Game Info Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: context.tokens.heroGradient,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            child: Column(
              children: [
                Text(
                  game.gameName,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: context.tokens.onHero,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  '${game.players.length} players • ${game.tasks.length} tasks',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.tokens.onHero.withOpacity(0.9),
                  ),
                ),
                if (game.isCompleted) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: context.tokens.onHero.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      'Game Completed',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.tokens.onHero,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          
          // Winner Podium (for completed games)
          if (game.isCompleted && sortedPlayers.isNotEmpty) ...[
            const SizedBox(height: 20),
            _WinnerPodium(players: sortedPlayers.take(3).toList()),
            const SizedBox(height: 20),
          ],

          // Full Scoreboard
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!game.isCompleted) const SizedBox(height: 20),
                  Text(
                    'Rankings',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.builder(
                      itemCount: sortedPlayers.length,
                      itemBuilder: (context, index) {
                        final player = sortedPlayers[index];
                        final rank = index + 1;
                        
                        return _PlayerScoreCard(
                          player: player,
                          rank: rank,
                          isWinner: rank == 1 && game.isCompleted,
                          tasks: game.tasks,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Game Statistics
          if (game.tasks.isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Game Statistics',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _StatColumn(
                        icon: Icons.assignment_turned_in,
                        label: 'Tasks Completed',
                        value: '${game.tasks.where((t) => t.allSubmissionsJudged).length}/${game.tasks.length}',
                      ),
                      _StatColumn(
                        icon: Icons.video_library,
                        label: 'Total Submissions',
                        value: '${game.tasks.fold<int>(0, (sum, task) => sum + task.submissions.length)}',
                      ),
                      _StatColumn(
                        icon: Icons.star,
                        label: 'Highest Score',
                        value: sortedPlayers.isNotEmpty ? '${sortedPlayers.first.totalScore}' : '0',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WinnerPodium extends StatelessWidget {
  final List<Player> players;

  const _WinnerPodium({required this.players});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Second place
          if (players.length > 1)
            _PodiumPosition(
              player: players[1],
              rank: 2,
              height: 100,
              color: context.tokens.medalSilver,
            ),
          
          const SizedBox(width: 8),
          
          // First place
          if (players.isNotEmpty)
            _PodiumPosition(
              player: players[0],
              rank: 1,
              height: 140,
              color: context.tokens.medalGold,
            ),
          
          const SizedBox(width: 8),
          
          // Third place
          if (players.length > 2)
            _PodiumPosition(
              player: players[2],
              rank: 3,
              height: 80,
              color: context.tokens.medalBronze,
            ),
        ],
      ),
    );
  }
}

class _PodiumPosition extends StatelessWidget {
  final Player player;
  final int rank;
  final double height;
  final Color color;

  const _PodiumPosition({
    required this.player,
    required this.rank,
    required this.height,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: color,
          child: Text(
            player.displayName.isNotEmpty ? player.displayName[0].toUpperCase() : 'P',
            style: TextStyle(
              color: context.tokens.onMedal,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          player.displayName,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          '${player.totalScore} pts',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 60,
          height: height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(8),
              topRight: Radius.circular(8),
            ),
          ),
          child: Center(
            child: Text(
              '$rank',
              style: TextStyle(
                color: context.tokens.onMedal,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PlayerScoreCard extends StatelessWidget {
  final Player player;
  final int rank;
  final bool isWinner;
  final List tasks;

  const _PlayerScoreCard({
    required this.player,
    required this.rank,
    required this.isWinner,
    required this.tasks,
  });

  @override
  Widget build(BuildContext context) {
    Color? rankColor;
    IconData? rankIcon;
    
    if (rank == 1) {
      rankColor = context.tokens.medalGold;
      rankIcon = Icons.emoji_events;
    } else if (rank == 2) {
      rankColor = context.tokens.medalSilver;
      rankIcon = Icons.military_tech;
    } else if (rank == 3) {
      rankColor = context.tokens.medalBronze;
      rankIcon = Icons.military_tech;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isWinner ? context.tokens.gold.withOpacity(0.1) : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Rank
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: rankColor ?? Theme.of(context).colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: rankIcon != null
                    ? Icon(rankIcon, color: context.tokens.onMedal, size: 20)
                    : Text(
                        '$rank',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 16),
            
            // Player Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    player.displayName,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Rank #$rank',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            
            // Score
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: (rankColor ?? Theme.of(context).colorScheme.primary).withOpacity(0.16),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: rankColor ?? Theme.of(context).colorScheme.primary,
                ),
              ),
              child: Text(
                '${player.totalScore} pts',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatColumn({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(
          icon,
          color: Theme.of(context).colorScheme.primary,
          size: 24,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}