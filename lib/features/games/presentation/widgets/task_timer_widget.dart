import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_theme.dart';

class TaskTimerWidget extends StatefulWidget {
  final int durationSeconds;
  final VoidCallback? onTimeExpired;

  const TaskTimerWidget({
    super.key,
    required this.durationSeconds,
    this.onTimeExpired,
  });

  @override
  State<TaskTimerWidget> createState() => _TaskTimerWidgetState();
}

class _TaskTimerWidgetState extends State<TaskTimerWidget> {
  late int _remainingSeconds;
  Timer? _timer;
  bool _hasWarned10s = false;
  bool _hasWarned5s = false;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.durationSeconds;
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setState(() {
          _remainingSeconds--;
        });

        // Haptic feedback at key moments
        if (_remainingSeconds == 10 && !_hasWarned10s) {
          _triggerHapticFeedback();
          _hasWarned10s = true;
        } else if (_remainingSeconds == 5 && !_hasWarned5s) {
          _triggerHapticFeedback();
          _hasWarned5s = true;
        } else if (_remainingSeconds == 0) {
          _triggerHapticFeedback();
          widget.onTimeExpired?.call();
        }
      } else {
        timer.cancel();
      }
    });
  }

  void _triggerHapticFeedback() {
    try {
      HapticFeedback.mediumImpact();
    } catch (e) {
      // Haptic feedback not available on this platform
    }
  }

  Color _getTimerColor() {
    final percentage = _remainingSeconds / widget.durationSeconds;

    if (percentage > 0.5) {
      return context.tokens.success;
    } else if (percentage > 0.2) {
      return context.tokens.warning;
    } else {
      return Theme.of(context).colorScheme.error;
    }
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(1, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final timerColor = _getTimerColor();
    final progress = _remainingSeconds / widget.durationSeconds;

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              'Time Remaining',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 120,
                  height: 120,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 8,
                    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(timerColor),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatTime(_remainingSeconds),
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: timerColor,
                          ),
                    ),
                    if (_remainingSeconds <= 10)
                      Text(
                        'Hurry!',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.error,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                  ],
                ),
              ],
            ),
            if (_remainingSeconds == 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.warning,
                      size: 16,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Time\'s up!',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.bold,
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