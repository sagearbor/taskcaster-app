import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/models/game.dart';
import '../../../../core/models/task.dart';
import '../../../../core/models/player.dart';
import '../widgets/animated_score_reveal.dart';
import '../bloc/game_detail_bloc.dart';

class TaskScoreboardScreen extends StatefulWidget {
  final Game game;
  final Task completedTask;
  final int taskIndex;
  final Map<String, int> taskScores; // playerId -> score for this task
  final Map<String, int> previousTotals; // playerId -> total before this task

  const TaskScoreboardScreen({
    super.key,
    required this.game,
    required this.completedTask,
    required this.taskIndex,
    required this.taskScores,
    required this.previousTotals,
  });

  @override
  State<TaskScoreboardScreen> createState() => _TaskScoreboardScreenState();
}

class _TaskScoreboardScreenState extends State<TaskScoreboardScreen>
    with TickerProviderStateMixin {
  late AnimationController _countdownController;
  late AnimationController _celebrationController;
  late Animation<double> _countdownAnimation;
  bool _autoAdvance = true;
  int _countdownSeconds = 10;

  @override
  void initState() {
    super.initState();

    // Setup countdown animation
    _countdownController = AnimationController(
      duration: Duration(seconds: _countdownSeconds),
      vsync: this,
    );

    _countdownAnimation = Tween<double>(
      begin: _countdownSeconds.toDouble(),
      end: 0.0,
    ).animate(_countdownController);

    // Setup celebration animation
    _celebrationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    // Start countdown if auto-advance is enabled
    if (widget.game.settings.autoAdvanceTasks) {
      _startCountdown();
    }

    // Start celebration animation
    _celebrationController.forward();
  }

  void _startCountdown() {
    _countdownController.forward().then((_) {
      if (_autoAdvance && mounted) {
        _navigateToNext();
      }
    });
  }

  void _navigateToNext() {
    final isLastTask = widget.taskIndex >= widget.game.tasks.length - 1;

    if (isLastTask) {
      // Game is complete, navigate to final scoreboard
      context.read<GameDetailBloc>().add(CompleteGameEvent(widget.game.id));
    } else {
      // Navigate to next task
      context.read<GameDetailBloc>().add(
        AdvanceToNextTaskEvent(widget.game.id, widget.taskIndex + 1),
      );
    }

    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _countdownController.dispose();
    _celebrationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Defensive: a game with no players has no scoreboard to reveal. Guard
    // before any `.first` access below.
    if (widget.game.players.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text('Task ${widget.taskIndex + 1} Results')),
        body: const Center(child: Text('No players to score yet.')),
      );
    }

    // Calculate sorted players with position changes
    final playersWithScores = widget.game.players.map((player) {
      final taskScore = widget.taskScores[player.userId] ?? 0;
      final previousTotal = widget.previousTotals[player.userId] ?? 0;
      final newTotal = previousTotal + taskScore;

      return PlayerScoreData(
        player: player,
        taskScore: taskScore,
        previousTotal: previousTotal,
        newTotal: newTotal,
      );
    }).toList();

    // Sort by new total
    playersWithScores.sort((a, b) => b.newTotal.compareTo(a.newTotal));

    // Calculate position changes
    final previousOrder = List<PlayerScoreData>.from(playersWithScores)
      ..sort((a, b) => b.previousTotal.compareTo(a.previousTotal));

    for (var playerData in playersWithScores) {
      final newPosition = playersWithScores.indexOf(playerData);
      final oldPosition = previousOrder.indexOf(playerData);
      playerData.positionChange = oldPosition - newPosition;
    }

    final taskWinner = playersWithScores.first;
    final isLastTask = widget.taskIndex >= widget.game.tasks.length - 1;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text('Task ${widget.taskIndex + 1} Results'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Task Info Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.task_alt,
                  color: Colors.white,
                  size: 48,
                ),
                const SizedBox(height: 8),
                Text(
                  widget.completedTask.title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    'Task ${widget.taskIndex + 1} of ${widget.game.tasks.length}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Animated Score Reveals
          Expanded(
            child: AnimatedScoreReveal(
              playersWithScores: playersWithScores,
              taskWinner: taskWinner,
              celebrationController: _celebrationController,
              onRevealComplete: () {
                // Haptic feedback when all scores are revealed
                HapticFeedback.mediumImpact();
              },
            ),
          ),

          // Bottom Action Section
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              children: [
                // Auto-advance countdown or manual button
                if (widget.game.settings.autoAdvanceTasks) ...[
                  AnimatedBuilder(
                    animation: _countdownAnimation,
                    builder: (context, child) {
                      final seconds = _countdownAnimation.value.ceil();
                      return Column(
                        children: [
                          Text(
                            isLastTask
                              ? 'Showing final results in...'
                              : 'Next task in...',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Theme.of(context).colorScheme.primary,
                                    width: 3,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    '$seconds',
                                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                      color: Theme.of(context).colorScheme.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    _autoAdvance = false;
                                    _countdownController.stop();
                                  });
                                },
                                child: const Text('Stay here'),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ] else ...[
                  FilledButton.icon(
                    onPressed: _navigateToNext,
                    icon: Icon(isLastTask ? Icons.emoji_events : Icons.arrow_forward),
                    label: Text(
                      isLastTask ? 'View Final Results' : 'Continue to Next Task',
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 56),
                    ),
                  ),
                ],

                const SizedBox(height: 12),

                // Watch Videos Button
                OutlinedButton.icon(
                  onPressed: () {
                    // Navigate to video viewing screen
                    // This would be implemented based on your video viewing setup
                  },
                  icon: const Icon(Icons.video_library),
                  label: const Text('Watch All Submissions'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PlayerScoreData {
  final Player player;
  final int taskScore;
  final int previousTotal;
  final int newTotal;
  int positionChange;

  PlayerScoreData({
    required this.player,
    required this.taskScore,
    required this.previousTotal,
    required this.newTotal,
    this.positionChange = 0,
  });
}