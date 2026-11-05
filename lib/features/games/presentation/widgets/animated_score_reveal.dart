import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../screens/task_scoreboard_screen.dart';

class AnimatedScoreReveal extends StatefulWidget {
  final List<PlayerScoreData> playersWithScores;
  final PlayerScoreData taskWinner;
  final AnimationController celebrationController;
  final VoidCallback? onRevealComplete;

  const AnimatedScoreReveal({
    super.key,
    required this.playersWithScores,
    required this.taskWinner,
    required this.celebrationController,
    this.onRevealComplete,
  });

  @override
  State<AnimatedScoreReveal> createState() => _AnimatedScoreRevealState();
}

class _AnimatedScoreRevealState extends State<AnimatedScoreReveal>
    with TickerProviderStateMixin {
  final List<AnimationController> _revealControllers = [];
  final List<AnimationController> _scoreCountControllers = [];
  final List<Animation<double>> _slideAnimations = [];
  final List<Animation<double>> _fadeAnimations = [];
  final List<Animation<int>> _scoreAnimations = [];

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _startStaggeredReveal();
  }

  void _setupAnimations() {
    for (int i = 0; i < widget.playersWithScores.length; i++) {
      final playerData = widget.playersWithScores[i];

      // Reveal animation controller
      final revealController = AnimationController(
        duration: const Duration(milliseconds: 600),
        vsync: this,
      );
      _revealControllers.add(revealController);

      // Score count animation controller
      final scoreCountController = AnimationController(
        duration: const Duration(milliseconds: 1000),
        vsync: this,
      );
      _scoreCountControllers.add(scoreCountController);

      // Slide in animation
      _slideAnimations.add(
        Tween<double>(
          begin: 100.0,
          end: 0.0,
        ).animate(CurvedAnimation(
          parent: revealController,
          curve: Curves.easeOutCubic,
        )),
      );

      // Fade in animation
      _fadeAnimations.add(
        Tween<double>(
          begin: 0.0,
          end: 1.0,
        ).animate(CurvedAnimation(
          parent: revealController,
          curve: Curves.easeIn,
        )),
      );

      // Score counting animation
      _scoreAnimations.add(
        IntTween(
          begin: playerData.previousTotal,
          end: playerData.newTotal,
        ).animate(CurvedAnimation(
          parent: scoreCountController,
          curve: Curves.easeOutQuart,
        )),
      );
    }
  }

  Future<void> _startStaggeredReveal() async {
    // Reveal each player with staggered delay
    for (int i = 0; i < _revealControllers.length; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        _revealControllers[i].forward();
        _scoreCountControllers[i].forward();

        // Haptic feedback for each reveal
        HapticFeedback.lightImpact();

        // Extra celebration for winner
        if (i == 0) {
          await Future.delayed(const Duration(milliseconds: 600));
          _showWinnerCelebration();
        }
      }
    }

    // Mark all revealed and callback
    if (mounted) {
      widget.onRevealComplete?.call();
    }
  }

  void _showWinnerCelebration() {
    HapticFeedback.heavyImpact();
    // Additional winner celebration could be added here
  }

  @override
  void dispose() {
    for (var controller in _revealControllers) {
      controller.dispose();
    }
    for (var controller in _scoreCountControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: widget.playersWithScores.length,
      itemBuilder: (context, index) {
        final playerData = widget.playersWithScores[index];
        final isWinner = index == 0;
        final rank = index + 1;

        return AnimatedBuilder(
          animation: Listenable.merge([
            _revealControllers[index],
            _scoreCountControllers[index],
          ]),
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(_slideAnimations[index].value, 0),
              child: Opacity(
                opacity: _fadeAnimations[index].value,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Stack(
                    children: [
                      // Player card
                      _PlayerScoreCard(
                        playerData: playerData,
                        rank: rank,
                        isWinner: isWinner,
                        currentScore: _scoreAnimations[index].value,
                        isRevealed: _revealControllers[index].isCompleted,
                      ),

                      // Winner confetti overlay
                      if (isWinner && _revealControllers[index].isCompleted)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: _ConfettiOverlay(
                              controller: widget.celebrationController,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _PlayerScoreCard extends StatelessWidget {
  final PlayerScoreData playerData;
  final int rank;
  final bool isWinner;
  final int currentScore;
  final bool isRevealed;

  const _PlayerScoreCard({
    required this.playerData,
    required this.rank,
    required this.isWinner,
    required this.currentScore,
    required this.isRevealed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Color rankColor;
    IconData rankIcon;

    if (rank == 1) {
      rankColor = Colors.amber[700]!;
      rankIcon = Icons.emoji_events;
    } else if (rank == 2) {
      rankColor = theme.colorScheme.onSurfaceVariant;
      rankIcon = Icons.military_tech;
    } else if (rank == 3) {
      rankColor = Colors.brown[400]!;
      rankIcon = Icons.military_tech;
    } else {
      rankColor = theme.colorScheme.primary;
      rankIcon = Icons.star_border;
    }

    return Card(
      elevation: isWinner ? 8 : 2,
      color: isWinner && isRevealed
        ? Colors.amber.withOpacity(0.1)
        : null,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: isWinner && isRevealed
            ? Border.all(color: Colors.amber, width: 2)
            : null,
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Rank badge
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: rankColor,
                shape: BoxShape.circle,
                boxShadow: isWinner ? [
                  BoxShadow(
                    color: rankColor.withOpacity(0.4),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ] : null,
              ),
              child: Center(
                child: Icon(
                  rankIcon,
                  color: Colors.white,
                  size: isWinner ? 28 : 24,
                ),
              ),
            ),

            const SizedBox(width: 16),

            // Player info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        playerData.player.displayName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (isWinner && isRevealed) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'WINNER',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      // Task points earned
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '+${playerData.taskScore} pts',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),

                      const SizedBox(width: 8),

                      // Position change indicator
                      if (playerData.positionChange != 0 && isRevealed)
                        _PositionChangeIndicator(
                          change: playerData.positionChange,
                        ),
                    ],
                  ),
                ],
              ),
            ),

            // Total score
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$currentScore',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: rankColor,
                  ),
                ),
                Text(
                  'points',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
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

class _PositionChangeIndicator extends StatelessWidget {
  final int change;

  const _PositionChangeIndicator({required this.change});

  @override
  Widget build(BuildContext context) {
    if (change == 0) return const SizedBox.shrink();

    final isUp = change > 0;
    final color = isUp ? Colors.green : Colors.red;
    final icon = isUp ? Icons.arrow_upward : Icons.arrow_downward;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: color,
          ),
          Text(
            '${change.abs()}',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfettiOverlay extends StatefulWidget {
  final AnimationController controller;

  const _ConfettiOverlay({required this.controller});

  @override
  State<_ConfettiOverlay> createState() => _ConfettiOverlayState();
}

class _ConfettiOverlayState extends State<_ConfettiOverlay>
    with SingleTickerProviderStateMixin {
  final List<_ConfettiParticle> particles = [];
  final Random random = Random();

  @override
  void initState() {
    super.initState();
    _generateParticles();
    widget.controller.addListener(() {
      setState(() {});
    });
  }

  void _generateParticles() {
    final colors = [
      Colors.red,
      Colors.blue,
      Colors.green,
      Colors.yellow,
      Colors.purple,
      Colors.orange,
      Colors.pink,
    ];

    for (int i = 0; i < 30; i++) {
      particles.add(_ConfettiParticle(
        color: colors[random.nextInt(colors.length)],
        x: random.nextDouble(),
        y: random.nextDouble() * -0.5,
        vx: (random.nextDouble() - 0.5) * 2,
        vy: random.nextDouble() * 3 + 2,
        size: random.nextDouble() * 6 + 4,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ConfettiPainter(
        particles: particles,
        progress: widget.controller.value,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _ConfettiParticle {
  final Color color;
  double x;
  double y;
  final double vx;
  final double vy;
  final double size;

  _ConfettiParticle({
    required this.color,
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
  });
}

class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiParticle> particles;
  final double progress;

  _ConfettiPainter({
    required this.particles,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress == 0) return;

    for (var particle in particles) {
      final paint = Paint()
        ..color = particle.color.withOpacity(1.0 - progress * 0.7)
        ..style = PaintingStyle.fill;

      final x = (particle.x + particle.vx * progress) * size.width;
      final y = (particle.y + particle.vy * progress) * size.height;

      canvas.drawCircle(
        Offset(x, y),
        particle.size * (1.0 - progress * 0.3),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}