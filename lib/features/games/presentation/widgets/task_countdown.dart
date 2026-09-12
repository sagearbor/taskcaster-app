import 'dart:async';

import 'package:flutter/material.dart';

import 'countdown_display.dart';

/// Owns the real clock for the task screen's countdown hero: a Timer ticking
/// once a second, computing elapsed time from [startedAt] and handing the
/// result to the pure [CountdownDisplay]. Kept separate from CountdownDisplay
/// so the display itself stays trivially testable with fixed values.
class TaskCountdown extends StatefulWidget {
  final DateTime startedAt;
  final int durationSeconds;

  /// Grace period past the timer before an entry is flagged LATE. Mirrors
  /// `AutoEdit.graceSeconds` — never blocks submission, just changes the
  /// display.
  final int graceSeconds;

  const TaskCountdown({
    super.key,
    required this.startedAt,
    required this.durationSeconds,
    this.graceSeconds = 30,
  });

  @override
  State<TaskCountdown> createState() => _TaskCountdownState();
}

class _TaskCountdownState extends State<TaskCountdown> {
  Timer? _timer;
  late int _elapsed;

  @override
  void initState() {
    super.initState();
    _elapsed = DateTime.now().difference(widget.startedAt).inSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _elapsed = DateTime.now().difference(widget.startedAt).inSeconds;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.durationSeconds - _elapsed;
    final isLate = _elapsed > widget.durationSeconds + widget.graceSeconds;
    return CountdownDisplay(remainingSeconds: remaining, isLate: isLate);
  }
}
