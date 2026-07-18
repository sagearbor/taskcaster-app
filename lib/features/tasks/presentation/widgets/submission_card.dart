import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/models/task.dart';
import '../../../../core/models/submission.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/link_utils.dart';

class SubmissionCard extends StatefulWidget {
  final Submission submission;
  final String playerName;
  final Task task;
  final String gameId;
  final VoidCallback onScored;

  const SubmissionCard({
    super.key,
    required this.submission,
    required this.playerName,
    required this.task,
    required this.gameId,
    required this.onScored,
  });

  @override
  State<SubmissionCard> createState() => _SubmissionCardState();
}

class _SubmissionCardState extends State<SubmissionCard> {
  int _selectedScore = 0;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _selectedScore = widget.submission.score;
  }

  Future<void> _submitScore() async {
    setState(() {
      _isSubmitting = true;
    });

    try {
      // TODO: This old judging code is deprecated - use new JudgingBloc instead
      // context.read<GameDetailBloc>().add(
      //   JudgeSubmission(
      //     gameId: widget.gameId,
      //     taskIndex: 0, // Need task index
      //     playerId: '', // Need player ID
      //     score: _selectedScore,
      //   ),
      // );

      widget.onScored();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Scored ${widget.playerName}\'s submission: $_selectedScore points'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to score submission: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _showScoringDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Score ${widget.playerName}\'s Submission'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'How many points should this submission receive?',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [0, 1, 2, 3, 4, 5].map((score) {
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedScore = score;
                    });
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _selectedScore == score
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _selectedScore == score
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outline,
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '$score',
                        style: TextStyle(
                          color: _selectedScore == score
                              ? Theme.of(context).colorScheme.onPrimary
                              : Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Text(
              'Selected: $_selectedScore point${_selectedScore == 1 ? '' : 's'}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: _isSubmitting ? null : () {
              Navigator.of(context).pop();
              _submitScore();
            },
            child: _isSubmitting 
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Submit Score'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: widget.submission.isJudged 
          ? Colors.green.withOpacity(0.05)
          : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: widget.submission.isJudged 
                      ? Colors.green 
                      : Theme.of(context).colorScheme.primary,
                  child: Text(
                    widget.playerName.isNotEmpty 
                        ? widget.playerName[0].toUpperCase()
                        : 'P',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.playerName,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Submitted ${DateFormat('MMM d, y \'at\' h:mm a').format(widget.submission.submittedAt)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.submission.isJudged)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.green),
                    ),
                    child: Text(
                      '${widget.submission.score} pts',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.green[700],
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.orange),
                    ),
                    child: Text(
                      'Pending',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange[700],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // Submission Content
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        widget.task.isVideoTask ? Icons.videocam : Icons.text_fields,
                        color: widget.task.isVideoTask ? Colors.red[700] : Colors.blue[700],
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.task.isVideoTask ? 'Video Submission' : 'Text Answer',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: widget.task.isVideoTask ? Colors.red[700] : Colors.blue[700],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  
                  if (widget.submission.hasVideoUrl) ...[
                    InkWell(
                      onTap: () => LinkUtils.openExternal(
                          context, widget.submission.videoUrl),
                      onLongPress: () => LinkUtils.copyToClipboard(
                          context, widget.submission.videoUrl ?? '',
                          label: 'Link copied'),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.play_circle_filled, color: Colors.blue[700]),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.submission.videoUrl!,
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Colors.blue[700],
                                  decoration: TextDecoration.underline,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Icon(Icons.open_in_new, color: Colors.blue[700], size: 20),
                          ],
                        ),
                      ),
                    ),
                  ],
                  
                  if (widget.submission.hasTextAnswer) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant),
                      ),
                      child: Text(
                        widget.submission.textAnswer!,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: AppTheme.ink,
                        ),
                      ),
                    ),
                    if (widget.task.isPuzzleTask && widget.submission.isJudged) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            widget.submission.score > 0 ? Icons.check_circle : Icons.cancel,
                            color: widget.submission.score > 0 ? Colors.green : Colors.red,
                            size: 20,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            widget.submission.score > 0 ? 'Correct Answer' : 'Incorrect Answer',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: widget.submission.score > 0 ? Colors.green : Colors.red,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ],
              ),
            ),

            // Scoring Actions
            if (!widget.submission.isJudged && widget.task.isVideoTask) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isSubmitting ? null : _showScoringDialog,
                      icon: const Icon(Icons.score),
                      label: const Text('Score Submission'),
                    ),
                  ),
                ],
              ),
            ],

            // Already Judged Info
            if (widget.submission.isJudged) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green[700]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This submission has been judged and scored',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.green[700],
                          fontWeight: FontWeight.w600,
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
}