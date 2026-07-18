import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/models/player_task_status.dart';
import '../../../../core/models/task.dart';
import '../../../../core/widgets/skeleton_loaders.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/repositories/game_repository.dart';
import '../bloc/task_execution_bloc.dart';
import '../bloc/task_execution_event.dart';
import '../bloc/task_execution_state.dart';
import '../widgets/submission_progress_widget.dart';
import '../widgets/task_timer_widget.dart';
import 'video_viewing_screen.dart';
import '../../../../core/utils/link_utils.dart';

class TaskExecutionScreen extends StatelessWidget {
  final String gameId;
  final int taskIndex;

  const TaskExecutionScreen({
    super.key,
    required this.gameId,
    required this.taskIndex,
  });

  @override
  Widget build(BuildContext context) {
    final authState = context.read<AuthBloc>().state;
    final userId = authState is AuthAuthenticated ? authState.user.id : '';

    return BlocProvider(
      create: (context) => TaskExecutionBloc(
        gameRepository: sl<GameRepository>(),
      )..add(LoadTask(
          gameId: gameId,
          taskIndex: taskIndex,
          userId: userId,
        )),
      child: TaskExecutionView(
        gameId: gameId,
        taskIndex: taskIndex,
        userId: userId,
      ),
    );
  }
}

class TaskExecutionView extends StatefulWidget {
  final String gameId;
  final int taskIndex;
  final String userId;

  const TaskExecutionView({
    super.key,
    required this.gameId,
    required this.taskIndex,
    required this.userId,
  });

  @override
  State<TaskExecutionView> createState() => _TaskExecutionViewState();
}

class _TaskExecutionViewState extends State<TaskExecutionView> {
  final _videoUrlController = TextEditingController();
  bool _isUrlValid = false;
  String? _urlError;
  // When true, show the submission form even though the user already submitted,
  // so they can change/replace their video.
  bool _editing = false;

  @override
  void dispose() {
    _videoUrlController.dispose();
    super.dispose();
  }

  void _validateUrl(String url) {
    setState(() {
      // Accept any well-formed http(s) URL with a real host. We deliberately
      // do not gate on a hardcoded allowlist of platforms: players
      // legitimately host videos in many places. The platform names in the UI
      // are guidance only.
      _isUrlValid = LinkUtils.isLikelyUrl(url);
      _urlError = LinkUtils.describeUrlProblem(url);
    });
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (!mounted) return;
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing on the clipboard to paste')),
      );
      return;
    }
    _videoUrlController.text = text;
    _validateUrl(text);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Check if user has entered text but not submitted
        if (_videoUrlController.text.isNotEmpty) {
          final shouldPop = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Discard submission?'),
              content: const Text(
                'You have entered a video URL. Are you sure you want to leave without submitting?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Stay'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red,
                  ),
                  child: const Text('Leave'),
                ),
              ],
            ),
          );
          return shouldPop ?? false;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
        title: BlocBuilder<TaskExecutionBloc, TaskExecutionState>(
          builder: (context, state) {
            if (state is TaskExecutionLoaded) {
              return Text('Task ${state.taskNumber} of ${state.totalTasks}');
            }
            return const Text('Task Execution');
          },
        ),
      ),
      body: BlocConsumer<TaskExecutionBloc, TaskExecutionState>(
        listener: (context, state) {
          if (state is TaskExecutionError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.red,
              ),
            );
          }

          if (state is TaskExecutionSubmitted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Submission successful! ✅')),
            );
            // Return to the game. (The old code pushed a named route
            // '/video-viewing' that was never registered, which left the
            // screen stuck blank after a successful submit.)
            Future.delayed(const Duration(milliseconds: 600), () {
              if (context.mounted) Navigator.of(context).pop();
            });
          }
        },
        builder: (context, state) {
          if (state is TaskExecutionLoading) {
            return SkeletonLoaders.taskExecutionSkeleton(context);
          }

          if (state is TaskExecutionError) {
            return ErrorView(
              message: 'Failed to load task',
              details: state.message,
              onRetry: () {
                context.read<TaskExecutionBloc>().add(LoadTask(
                  gameId: widget.gameId,
                  taskIndex: widget.taskIndex,
                  userId: widget.userId,
                ));
              },
            );
          }

          if (state is TaskExecutionLoaded) {
            // Check if user already submitted (unless they tapped "Change
            // my video" to edit, in which case fall through to the form).
            if (state.hasUserSubmitted && !_editing) {
              return _buildAlreadySubmittedView(context, state);
            }

            return _buildTaskExecutionForm(context, state);
          }

          // Initial / Submitted — show a spinner instead of a blank screen.
          return const Center(child: CircularProgressIndicator());
        },
      ),
    ),
    );
  }

  Widget _buildAlreadySubmittedView(
      BuildContext context, TaskExecutionLoaded state) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle,
                size: 64,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Already Submitted ✅',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            Text(
              'You have already submitted this task!',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            if (state.userStatus?.submissionUrl != null) ...[
              const SizedBox(height: 24),
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
                            'Your submission',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: () => LinkUtils.openExternal(
                            context, state.userStatus!.submissionUrl),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.violetSoft,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.open_in_new,
                                      size: 16, color: AppTheme.violetDeep),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      state.userStatus!.submissionUrl!,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: AppTheme.violetDeep,
                                            decoration:
                                                TextDecoration.underline,
                                          ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              if (state.userStatus!.submittedAt != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Submitted ${_formatTimeAgo(state.userStatus!.submittedAt!)}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: AppTheme.inkSoft,
                                      ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      if (state.task.deadline != null &&
                          state.userStatus!.submittedAt != null &&
                          state.userStatus!.submittedAt!.isBefore(state.task.deadline!)) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(Icons.timer, size: 16, color: Colors.green[400]),
                            const SizedBox(width: 4),
                            Text(
                              'Submitted on time',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.green[400],
                                  ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 32),
            SubmissionProgressWidget(
              playerStatuses: state.allPlayerStatuses,
              currentUserId: widget.userId,
            ),
            const SizedBox(height: 32),
            if (state.canUserViewVideos)
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => VideoViewingScreen(
                      gameId: widget.gameId,
                      taskIndex: widget.taskIndex,
                    ),
                  ));
                },
                icon: const Icon(Icons.play_circle_outline),
                label: const Text('View Submissions'),
              ),
            const SizedBox(height: 16),
            // Let the player change their submission until it has been judged.
            if (state.userStatus?.state != TaskPlayerState.judged)
              OutlinedButton.icon(
                onPressed: () {
                  final current = state.userStatus?.submissionUrl ?? '';
                  setState(() {
                    _editing = true;
                    _videoUrlController.text = current;
                    _isUrlValid = LinkUtils.isLikelyUrl(current);
                    _urlError = LinkUtils.describeUrlProblem(current);
                  });
                },
                icon: const Icon(Icons.edit, size: 18),
                label: const Text('Change my video'),
              ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back to Game'),
            ),
          ],
        ),
    );
  }

  Widget _buildTaskExecutionForm(
      BuildContext context, TaskExecutionLoaded state) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Task reveal card — the big moment.
          _TaskRevealCard(task: state.task),

          const SizedBox(height: 16),

          // Timer Widget (if task has duration)
          if (state.task.durationSeconds != null)
            TaskTimerWidget(
              durationSeconds: state.task.durationSeconds!,
              onTimeExpired: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Time is up! Please submit your video.'),
                    backgroundColor: Colors.orange,
                  ),
                );
              },
            ),

          const SizedBox(height: 16),

          // Deadline (if task has deadline)
          if (state.task.deadline != null)
            Card(
              color: state.task.hasDeadlinePassed
                  ? Theme.of(context).colorScheme.error.withOpacity(0.1)
                  : AppTheme.violetSoft,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    Icon(
                      state.task.hasDeadlinePassed
                          ? Icons.warning
                          : Icons.schedule,
                      color: state.task.hasDeadlinePassed
                          ? Theme.of(context).colorScheme.error
                          : AppTheme.violet,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            state.task.hasDeadlinePassed
                                ? 'Deadline Passed'
                                : 'Submit by:',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AppTheme.violetDeep,
                                ),
                          ),
                          Text(
                            _formatDeadline(state.task.deadline!),
                            style:
                                Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.violetDeep,
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

          // Submission Progress
          SubmissionProgressWidget(
            playerStatuses: state.allPlayerStatuses,
            currentUserId: widget.userId,
          ),

          const SizedBox(height: 24),

          // The game plan — how to get your video in.
          _buildHowItWorksChecklist(context),

          const SizedBox(height: 20),

          // Video URL Input
          Text(
            'Submit Your Video',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _videoUrlController,
            decoration: InputDecoration(
              labelText: 'Video link',
              hintText: 'https://youtube.com/watch?v=...',
              helperText: 'Any shareable web link works',
              errorText: _urlError,
              errorMaxLines: 2,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.link),
              suffixIcon: _isUrlValid
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : IconButton(
                      icon: const Icon(Icons.content_paste),
                      tooltip: 'Paste from clipboard',
                      onPressed: _pasteFromClipboard,
                    ),
            ),
            keyboardType: TextInputType.url,
            onChanged: _validateUrl,
          ),

          const SizedBox(height: 24),

          // Submit Button
          ElevatedButton.icon(
            onPressed: _isUrlValid
                ? () {
                    context.read<TaskExecutionBloc>().add(
                          SubmitTask(
                            gameId: widget.gameId,
                            taskIndex: widget.taskIndex,
                            userId: widget.userId,
                            videoUrl: _videoUrlController.text.trim(),
                          ),
                        );
                  }
                : null,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.all(16),
            ),
            icon: const Icon(Icons.send_rounded),
            label: Text(
              'Submit Video',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),

          // Skip Button (if allowed)
          if (state.task.playerStatuses[widget.userId]?.state !=
              TaskPlayerState.skipped) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                _showSkipConfirmation(context);
              },
              child: const Text('Skip Task'),
            ),
          ],

        ],
      ),
    );
  }

  Widget _buildHowItWorksChecklist(BuildContext context) {
    const steps = [
      (Icons.videocam_outlined, 'Film it with your camera app'),
      (Icons.cloud_upload_outlined, 'Upload to Google Photos or YouTube'),
      (Icons.link, 'Paste the share link below'),
    ];

    return Card(
      color: AppTheme.violetSoft,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How it works',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.violetDeep,
                  ),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < steps.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              Row(
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: AppTheme.violet,
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(steps[i].$1, size: 18, color: AppTheme.violetDeep),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      steps[i].$2,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppTheme.violetDeep,
                          ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showSkipConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Skip Task?'),
        content: const Text(
          'Are you sure you want to skip this task? You won\'t be able to earn points for it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              context.read<TaskExecutionBloc>().add(
                    SkipTask(
                      gameId: widget.gameId,
                      taskIndex: widget.taskIndex,
                      userId: widget.userId,
                    ),
                  );
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Skip'),
          ),
        ],
      ),
    );
  }

  String _formatTimeAgo(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inSeconds < 60) {
      return 'just now';
    }

    if (difference.inMinutes < 60) {
      final minutes = difference.inMinutes;
      return '$minutes minute${minutes > 1 ? 's' : ''} ago';
    }

    if (difference.inHours < 24) {
      final hours = difference.inHours;
      return '$hours hour${hours > 1 ? 's' : ''} ago';
    }

    final days = difference.inDays;
    return '$days day${days > 1 ? 's' : ''} ago';
  }

  String _formatDeadline(DateTime deadline) {
    final now = DateTime.now();
    final difference = deadline.difference(now);

    if (difference.isNegative) {
      return 'Expired';
    }

    if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} remaining';
    }

    if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} remaining';
    }

    if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes > 1 ? 's' : ''} remaining';
    }

    return 'Less than a minute';
  }
}

/// The task, presented like the envelope-opening moment on the show:
/// a wax-seal overline, the title front and center, a category chip, and the
/// full brief underneath. Fades and slides in on first build.
class _TaskRevealCard extends StatelessWidget {
  final Task task;

  const _TaskRevealCard({required this.task});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 24 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Card(
        elevation: 4,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20.0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.violet, width: 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.theater_comedy, color: AppTheme.violet),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'YOUR TASK, SHOULD YOU ACCEPT IT…',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.violetDeep,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                task.title,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
              ),
              if (task.category != null) ...[
                const SizedBox(height: 10),
                Chip(
                  avatar: const Icon(Icons.category_outlined, size: 16),
                  label: Text(task.category!),
                  visualDensity: VisualDensity.compact,
                ),
              ],
              const SizedBox(height: 12),
              Text(
                task.description,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}