import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_theme.dart';

import '../../../../core/di/service_locator.dart';
import '../../domain/repositories/game_repository.dart';
import '../bloc/judging_bloc.dart';
import '../bloc/judging_event.dart';
import '../bloc/judging_state.dart';
import 'task_scoreboard_screen.dart';
import '../bloc/game_detail_bloc.dart';

class SubmissionReviewScreen extends StatelessWidget {
  final String gameId;
  final int taskIndex;

  const SubmissionReviewScreen({
    super.key,
    required this.gameId,
    required this.taskIndex,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => JudgingBloc(
        gameRepository: sl<GameRepository>(),
      )..add(LoadSubmissions(
          gameId: gameId,
          taskIndex: taskIndex,
        )),
      child: SubmissionReviewView(
        gameId: gameId,
        taskIndex: taskIndex,
      ),
    );
  }
}

class SubmissionReviewView extends StatefulWidget {
  final String gameId;
  final int taskIndex;

  const SubmissionReviewView({
    super.key,
    required this.gameId,
    required this.taskIndex,
  });

  @override
  State<SubmissionReviewView> createState() => _SubmissionReviewViewState();
}

class _SubmissionReviewViewState extends State<SubmissionReviewView> {
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open URL: $url'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review Submissions'),
      ),
      body: BlocConsumer<JudgingBloc, JudgingState>(
        listener: (context, state) {
          if (state is JudgingError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.red,
              ),
            );
          }

          if (state is JudgingCompleted) {
            // Get the game from GameDetailBloc to navigate to scoreboard
            final gameDetailState = context.read<GameDetailBloc>().state;
            if (gameDetailState is GameDetailLoaded) {
              final game = gameDetailState.game;
              final task = game.tasks[state.taskIndex];

              // Calculate task scores from the per-player task statuses, which
              // judgeSubmission always populates with the awarded score. (The
              // submissions list can be empty when players submit through the
              // task-execution flow, so reading from it risked a crash and
              // zeroed-out scoreboards.)
              final Map<String, int> taskScores = {};
              final Map<String, int> previousTotals = {};

              for (final player in game.players) {
                final status = task.getPlayerStatus(player.userId);
                final taskScore = status?.score ?? 0;
                taskScores[player.userId] = taskScore;
                // player.totalScore already includes this task's score, so
                // subtract it to recover the pre-task total for the reveal.
                previousTotals[player.userId] = player.totalScore - taskScore;
              }

              // Navigate to task scoreboard
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => BlocProvider.value(
                    value: context.read<GameDetailBloc>(),
                    child: TaskScoreboardScreen(
                      game: game,
                      completedTask: task,
                      taskIndex: state.taskIndex,
                      taskScores: taskScores,
                      previousTotals: previousTotals,
                    ),
                  ),
                ),
              );
            } else {
              // Fallback to original behavior
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            }
          }
        },
        builder: (context, state) {
          if (state is JudgingLoading) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (state is JudgingError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.red,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Error',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    state.message,
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Go Back'),
                  ),
                ],
              ),
            );
          }

          if (state is JudgingLoaded) {
            // Filter to only show submitted submissions
            final submittedSubmissions = state.submissions
                .where((s) => s.status.hasSubmitted)
                .toList();

            if (submittedSubmissions.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.assignment,
                      size: 64,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No submissions to review',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Go Back'),
                    ),
                  ],
                ),
              );
            }

            final allJudged = state.scoredCount >= submittedSubmissions.length;

            return Column(
              children: [
                // Progress indicator
                Container(
                  padding: const EdgeInsets.all(16),
                  color: allJudged
                      ? Colors.green.withOpacity(0.15)
                      : Theme.of(context).colorScheme.primaryContainer,
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            allJudged
                                ? 'All judged! 🎉'
                                : '${state.scoredCount} of ${submittedSubmissions.length} judged',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: allJudged ? Colors.green[800] : null,
                                ),
                          ),
                          if (state.canFinish)
                            ElevatedButton.icon(
                              onPressed: () {
                                _showFinishConfirmation(context);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                              ),
                              icon: const Icon(Icons.check),
                              label: Text(allJudged
                                  ? 'Reveal the scores'
                                  : 'Finish'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: submittedSubmissions.isEmpty
                              ? 0
                              : state.scoredCount /
                                  submittedSubmissions.length,
                          minHeight: 6,
                          backgroundColor: Colors.white.withOpacity(0.5),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            allJudged ? Colors.green : AppTheme.violet,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // PageView for submissions
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: submittedSubmissions.length,
                    onPageChanged: (index) {
                      setState(() {});
                    },
                    itemBuilder: (context, index) {
                      final submission = submittedSubmissions[index];
                      return _buildSubmissionCard(context, state, submission, index, submittedSubmissions.length);
                    },
                  ),
                ),
              ],
            );
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildSubmissionCard(
    BuildContext context,
    JudgingLoaded state,
    SubmissionData submission,
    int index,
    int total,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Navigation indicator
          Center(
            child: Text(
              'Submission ${index + 1} of $total',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          const SizedBox(height: 16),

          // Player Card
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    child: Text(
                      submission.playerName.isNotEmpty
                          ? submission.playerName[0].toUpperCase()
                          : 'P',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    submission.playerName,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  if (submission.score != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star, color: Colors.amber),
                          const SizedBox(width: 8),
                          Text(
                            'Scored: ${submission.score} pts',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Colors.green[700],
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Video Link Card
          if (submission.submissionUrl != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.videocam, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          'Video Submission',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () => _openUrl(submission.submissionUrl!),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                      ),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Open Video'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      submission.submissionUrl!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 24),

          // Scoring Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your verdict, judge',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '0 = tragic · 10 = legendary',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      for (var score = JudgingBloc.minScore;
                          score <= JudgingBloc.maxScore;
                          score++)
                        _buildScoreChip(context, submission, score),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: submission.skipped
                        ? null
                        : () {
                            context.read<JudgingBloc>().add(
                                  SkipSubmission(playerId: submission.playerId),
                                );
                            // Move to next page
                            if (_pageController.page! < total - 1) {
                              _pageController.nextPage(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              );
                            }
                          },
                    icon: const Icon(Icons.skip_next),
                    label: const Text('Skip This Submission'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Navigation Buttons
          Row(
            children: [
              if (index > 0)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      _pageController.previousPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    },
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Previous'),
                  ),
                ),
              if (index > 0 && index < total - 1) const SizedBox(width: 8),
              if (index < total - 1)
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      _pageController.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    },
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('Next'),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScoreChip(
      BuildContext context, SubmissionData submission, int score) {
    final isSelected = submission.score == score;
    return Semantics(
      button: true,
      selected: isSelected,
      label: 'Score $score point${score == 1 ? '' : 's'}',
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () {
          // A satisfying tick per tap; a firmer thunk when it lands.
          HapticFeedback.selectionClick();
          HapticFeedback.mediumImpact();
          context.read<JudgingBloc>().add(
                ScoreSubmission(
                  playerId: submission.playerId,
                  score: score,
                ),
              );
          // Auto-advance to next submission after short delay
          Future.delayed(const Duration(milliseconds: 500), () {
            if (_pageController.hasClients) {
              final currentPage = _pageController.page?.round() ?? 0;
              final state = context.read<JudgingBloc>().state;
              if (state is JudgingLoaded) {
                final total = state.submissions
                    .where((s) => s.status.hasSubmitted)
                    .length;
                if (currentPage < total - 1) {
                  _pageController.nextPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                }
              }
            }
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSelected ? AppTheme.violet : Colors.transparent,
            border: Border.all(
              color: isSelected
                  ? AppTheme.violet
                  : Theme.of(context).colorScheme.outline,
              width: 2,
            ),
          ),
          child: Text(
            '$score',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isSelected
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurface,
                ),
          ),
        ),
      ),
    );
  }

  void _showFinishConfirmation(BuildContext context) {
    final state = context.read<JudgingBloc>().state as JudgingLoaded;

    // Edge case: Judge hasn't scored any submissions
    if (state.scoredCount == 0) {
      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('No Scores Given'),
          icon: const Icon(Icons.warning, color: Colors.orange, size: 48),
          content: const Text(
            'You haven\'t scored any submissions yet. '
            'Please score at least one submission before finishing.',
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Go Back'),
            ),
          ],
        ),
      );
      return;
    }

    // Edge case: Judge hasn't scored all submissions (warning)
    final unscored = state.submissions.where((s) => s.status.hasSubmitted && s.score == null).length;
    final warningMessage = unscored > 0
        ? 'You have scored ${state.scoredCount} submissions but $unscored are still unscored. '
        : 'You have scored ${state.scoredCount} submissions. ';

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Finish Judging?'),
        content: Text(
          '$warningMessage'
          'This will finalize the scores and update player totals.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          if (unscored > 0)
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('Review Unscored ($unscored)'),
            ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              context.read<JudgingBloc>().add(const FinishJudging());
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Finish'),
          ),
        ],
      ),
    );
  }
}