import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/models/task.dart';
import '../../../../core/models/submission.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../games/presentation/bloc/game_detail_bloc.dart';
import '../../../../core/theme/app_theme.dart';

class VideoTaskSubmission extends StatefulWidget {
  final Task task;
  final String gameId;
  final Submission? existingSubmission;

  const VideoTaskSubmission({
    super.key,
    required this.task,
    required this.gameId,
    this.existingSubmission,
  });

  @override
  State<VideoTaskSubmission> createState() => _VideoTaskSubmissionState();
}

class _VideoTaskSubmissionState extends State<VideoTaskSubmission> {
  final _formKey = GlobalKey<FormState>();
  final _videoUrlController = TextEditingController();
  bool _isSubmitting = false;
  static const Uuid _uuid = Uuid();

  @override
  void initState() {
    super.initState();
    if (widget.existingSubmission != null && widget.existingSubmission!.hasVideoUrl) {
      _videoUrlController.text = widget.existingSubmission!.videoUrl!;
    }
  }

  @override
  void dispose() {
    _videoUrlController.dispose();
    super.dispose();
  }

  String? _validateVideoUrl(String? value) {
    if (value == null || value.isEmpty) {
      return 'Video URL is required';
    }
    
    // Basic URL validation
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme) {
      return 'Please enter a valid URL';
    }
    
    // Check for common video hosting platforms
    final host = uri.host.toLowerCase();
    if (!host.contains('youtube') && 
        !host.contains('youtu.be') && 
        !host.contains('drive.google') &&
        !host.contains('photos.google') &&
        !host.contains('dropbox') &&
        !host.contains('vimeo') &&
        !host.contains('icloud')) {
      return 'Please use a supported video hosting platform (YouTube, Google Drive, etc.)';
    }
    
    return null;
  }

  Future<void> _submitVideo() async {
    if (!_formKey.currentState!.validate()) return;

    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      final submission = Submission(
        id: _uuid.v4(),
        userId: authState.user.id,
        videoUrl: _videoUrlController.text.trim(),
        textAnswer: null,
        score: 0,
        isJudged: false,
        submittedAt: DateTime.now(),
      );

      context.read<GameDetailBloc>().add(
        SubmitTaskAnswer(
          gameId: widget.gameId,
          taskId: widget.task.id,
          submission: submission,
        ),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Video submitted successfully!'),
            backgroundColor: context.tokens.success,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit video: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
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

  @override
  Widget build(BuildContext context) {
    final hasExistingSubmission = widget.existingSubmission != null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.videocam,
                    color: Theme.of(context).colorScheme.error,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    hasExistingSubmission ? 'Update Your Video' : 'Submit Your Video',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.tokens.info.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.tokens.info.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: context.tokens.info),
                        const SizedBox(width: 8),
                        Text(
                          'How to submit',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: context.tokens.info,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '1. Record your video attempt\n'
                      '2. Upload to YouTube, Google Drive, or similar\n'
                      '3. Copy the share link\n'
                      '4. Paste the link below and submit',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: context.tokens.info,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              
              TextFormField(
                controller: _videoUrlController,
                decoration: const InputDecoration(
                  labelText: 'Video URL',
                  hintText: 'https://youtube.com/watch?v=...',
                  prefixIcon: Icon(Icons.link),
                  helperText: 'Paste a link to your video submission',
                ),
                validator: _validateVideoUrl,
                enabled: !_isSubmitting,
                keyboardType: TextInputType.url,
                maxLines: 2,
              ),
              const SizedBox(height: 24),
              
              if (hasExistingSubmission && !widget.existingSubmission!.isJudged) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.tokens.gold.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: context.tokens.gold),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.edit, color: context.tokens.goldText),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'You can update your submission until it\'s judged',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: context.tokens.goldText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              
              ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _submitVideo,
                icon: _isSubmitting 
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(hasExistingSubmission ? Icons.update : Icons.send),
                label: Text(
                  _isSubmitting 
                      ? 'Submitting...'
                      : hasExistingSubmission 
                          ? 'Update Submission'
                          : 'Submit Video',
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              
              if (hasExistingSubmission && widget.existingSubmission!.isJudged) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.lock, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This submission has been judged and cannot be changed',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
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
      ),
    );
  }
}