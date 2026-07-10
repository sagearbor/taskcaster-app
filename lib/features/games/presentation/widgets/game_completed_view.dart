import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/models/game.dart';
import '../../../../core/models/player.dart';
import '../../../../core/widgets/ar_fx.dart';

/// The winner ceremony shown when a game completes — the emotional peak of the
/// whole game, so it celebrates: confetti rains over the screen, the trophy
/// and winner name punch in elastically, and the final standings slide in row
/// by row while each score counts up from zero. Non-winners get a personal
/// "You placed #N" so everyone has a takeaway, and the crew can jump straight
/// into a rematch with the same roster.
class GameCompletedView extends StatefulWidget {
  final Game game;

  /// The signed-in player, used for the "You placed #N" line. Null/unknown ids
  /// simply hide that line.
  final String? currentUserId;

  /// Invoked when the user taps "Rematch — same crew". When null the rematch
  /// button is hidden (e.g. previews/tests without a bloc).
  final VoidCallback? onRematch;

  /// Invoked when the user taps "Send one back 🏠" — the House Hunt role swap.
  /// Null hides the button (non-House-Hunt games, previews/tests).
  final VoidCallback? onSendHouseHunt;

  const GameCompletedView({
    super.key,
    required this.game,
    this.currentUserId,
    this.onRematch,
    this.onSendHouseHunt,
  });

  @override
  State<GameCompletedView> createState() => _GameCompletedViewState();
}

class _GameCompletedViewState extends State<GameCompletedView>
    with SingleTickerProviderStateMixin {
  /// Drives the whole ceremony: trophy pops first, then the winner reveal,
  /// then the standings stagger in.
  late final AnimationController _ceremony;

  @override
  void initState() {
    super.initState();
    _ceremony = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..forward();
  }

  @override
  void dispose() {
    _ceremony.dispose();
    super.dispose();
  }

  /// Curved sub-animation of the ceremony between [start] and [end] (0..1).
  Animation<double> _slice(double start, double end,
      {Curve curve = Curves.easeOutCubic}) {
    return CurvedAnimation(
      parent: _ceremony,
      curve: Interval(start, end, curve: curve),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Sort players by total score.
    final sortedPlayers = List<Player>.from(widget.game.players)
      ..sort((a, b) => b.totalScore.compareTo(a.totalScore));

    final winner = sortedPlayers.isNotEmpty ? sortedPlayers.first : null;
    final myRank = widget.currentUserId == null
        ? -1
        : sortedPlayers.indexWhere((p) => p.userId == widget.currentUserId);

    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (winner != null)
                _WinnerCard(
                  winner: winner,
                  trophyScale: _slice(0.0, 0.45, curve: Curves.elasticOut),
                  reveal: _slice(0.15, 0.5),
                  // "You placed #N" for everyone who didn't win.
                  placementLine: (myRank > 0)
                      ? 'You placed #${myRank + 1}'
                      : (myRank == 0 ? 'That\'s you! 🎉' : null),
                ),
              const SizedBox(height: 16),

              // Final standings — staggered rows with count-up scores.
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Final Standings',
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: ListView.builder(
                            itemCount: sortedPlayers.length,
                            itemBuilder: (context, index) {
                              // Stagger: each row starts a beat after the
                              // previous, all inside the ceremony window.
                              final start =
                                  (0.35 + index * 0.08).clamp(0.0, 0.85);
                              final anim = _slice(start, start + 0.15);
                              return _StandingRow(
                                player: sortedPlayers[index],
                                rank: index + 1,
                                isYou: sortedPlayers[index].userId ==
                                    widget.currentUserId,
                                animation: anim,
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Game statistics.
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _StatItem(
                        icon: Icons.people,
                        label: 'Players',
                        value: '${widget.game.players.length}',
                      ),
                      _StatItem(
                        icon: Icons.assignment,
                        label: 'Tasks',
                        value: '${widget.game.tasks.length}',
                      ),
                      _StatItem(
                        icon: Icons.video_library,
                        label: 'Submissions',
                        value:
                            '${widget.game.tasks.fold<int>(0, (sum, task) => sum + task.submissions.length)}',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Actions: rematch is the hero — same crew, fresh tasks.
              if (widget.onRematch != null) ...[
                FilledButton.icon(
                  onPressed: widget.onRematch,
                  icon: const Icon(Icons.replay),
                  label: const Text('Rematch — same crew'),
                ),
                const SizedBox(height: 12),
              ],
              // House Hunt role swap: fire a fresh hunt back at the hider.
              if (widget.onSendHouseHunt != null) ...[
                OutlinedButton.icon(
                  onPressed: widget.onSendHouseHunt,
                  icon: const Icon(Icons.home_work_outlined),
                  label: const Text('Send one back 🏠'),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _shareResults(sortedPlayers),
                      icon: const Icon(Icons.share),
                      label: const Text('Share Results'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      icon: const Icon(Icons.home),
                      label: const Text('Back to Home'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Celebration rain over the whole view (one-shot, self-completing).
        const Positioned.fill(child: ConfettiBurst()),
      ],
    );
  }

  void _shareResults(List<Player> sortedPlayers) {
    final standings = sortedPlayers
        .asMap()
        .entries
        .map((e) => '${e.key + 1}. ${e.value.displayName} — ${e.value.totalScore} pts')
        .join('\n');
    final text = '🏆 ${widget.game.gameName} — Final Results\n\n'
        '$standings\n\n'
        'Played on TaskCaster!';
    Share.share(text, subject: '${widget.game.gameName} — Results');
  }
}

/// Amber winner card: trophy elastic scale-in, then the winner name/score
/// fade-slide into place, plus the viewer's own placement line.
class _WinnerCard extends StatelessWidget {
  final Player winner;
  final Animation<double> trophyScale;
  final Animation<double> reveal;
  final String? placementLine;

  const _WinnerCard({
    required this.winner,
    required this.trophyScale,
    required this.reveal,
    this.placementLine,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.amber.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            ScaleTransition(
              scale: trophyScale,
              child: Icon(
                Icons.emoji_events,
                size: 64,
                color: Colors.amber[700],
              ),
            ),
            const SizedBox(height: 12),
            FadeTransition(
              opacity: reveal,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.35),
                  end: Offset.zero,
                ).animate(reveal),
                child: Column(
                  children: [
                    Text(
                      '🎉 Winner! 🎉',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.amber[700],
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      winner.displayName,
                      textAlign: TextAlign.center,
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                    ),
                    const SizedBox(height: 4),
                    // Winner score counts up from 0 for the reveal.
                    TweenAnimationBuilder<int>(
                      tween: IntTween(begin: 0, end: winner.totalScore),
                      duration: const Duration(milliseconds: 1200),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, _) => Text(
                        '$value points',
                        style:
                            Theme.of(context).textTheme.titleLarge?.copyWith(
                                  color: Colors.amber[700],
                                  fontWeight: FontWeight.w600,
                                ),
                      ),
                    ),
                    if (placementLine != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        placementLine!,
                        style:
                            Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One standings row: slides in from the right while its score counts up.
class _StandingRow extends StatelessWidget {
  final Player player;
  final int rank;
  final bool isYou;
  final Animation<double> animation;

  const _StandingRow({
    required this.player,
    required this.rank,
    required this.isYou,
    required this.animation,
  });

  @override
  Widget build(BuildContext context) {
    Color? rankColor;
    IconData? rankIcon;

    if (rank == 1) {
      rankColor = Colors.amber[700];
      rankIcon = Icons.emoji_events;
    } else if (rank == 2) {
      rankColor = Colors.grey[600];
      rankIcon = Icons.military_tech;
    } else if (rank == 3) {
      rankColor = Colors.brown[400];
      rankIcon = Icons.military_tech;
    }

    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.25, 0),
          end: Offset.zero,
        ).animate(animation),
        child: Card(
          margin: const EdgeInsets.only(bottom: 8),
          color: rank <= 3 ? rankColor?.withOpacity(0.1) : null,
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: rankColor ?? Colors.grey[400],
              child: rankIcon != null
                  ? Icon(rankIcon, color: Colors.white, size: 20)
                  : Text(
                      '$rank',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
            title: Text(
              player.displayName,
              style: TextStyle(
                fontWeight: rank <= 3 ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            subtitle: Text(isYou ? 'Rank #$rank · You' : 'Rank #$rank'),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              // Count-up score, synchronized with the row's slide-in.
              child: TweenAnimationBuilder<int>(
                tween: IntTween(begin: 0, end: player.totalScore),
                duration: const Duration(milliseconds: 1200),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => Text(
                  '$value pts',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatItem({
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
          size: 32,
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
