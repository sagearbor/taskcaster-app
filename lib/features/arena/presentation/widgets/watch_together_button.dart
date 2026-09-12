import 'package:flutter/material.dart';

import '../screens/watch_together_screen.dart';

/// Drop-in button for a task's already-submitted view: "Watch together"
/// opens the full-screen slideshow of every entry for that task. Available
/// once the viewer has submitted their own attempt at [taskId] (the caller
/// decides when to show it).
class WatchTogetherButton extends StatelessWidget {
  final String gameId;
  final String taskId;
  final String taskTitle;

  const WatchTogetherButton({
    super.key,
    required this.gameId,
    required this.taskId,
    required this.taskTitle,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => WatchTogetherScreen(
              gameId: gameId,
              taskId: taskId,
              taskTitle: taskTitle,
            ),
          ),
        );
      },
      icon: const Icon(Icons.groups_outlined),
      label: const Text('Watch together'),
    );
  }
}
