import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Stand-in for `lib/features/arena/presentation/screens/arena_screen.dart`,
/// which the Arena-UI agent builds on `feat/arena-ui` in this same round (see
/// docs/PRODUCT_DIRECTION.md §2.3-2.5 and tmp/round7/CONTRACTS.md's
/// `ArenaBloc`). Every place in this branch that needs to push the Arena
/// (Home's "Arena — grade the crowd" button, the task screen's "See what
/// everyone else did", the Posted screen's "See theirs") pushes THIS screen
/// for now so the surrounding flows are fully wired and testable; swapping it
/// for the real `ArenaScreen()` once both branches land on `main` is a
/// one-import change per call site — grep for `ArenaScreenPlaceholder`.
///
/// DO NOT build the real Arena screen here — that is the Arena-UI agent's
/// deliverable on `feat/arena-ui`.
class ArenaScreenPlaceholder extends StatelessWidget {
  const ArenaScreenPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Arena')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.theater_comedy, size: 56, color: AppTheme.violet),
              const SizedBox(height: 16),
              Text(
                'The Arena is on its way',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Grading the crowd\'s attempts lands with feat/arena-ui.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.inkSoft,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
