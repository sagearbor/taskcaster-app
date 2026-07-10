import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/services/ar/ar_capability_service.dart';
import '../../../../core/services/ar/ar_games.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/repositories/game_repository.dart';
import '../bloc/ar_task_bloc.dart';
import '../widgets/ar_minigame_view.dart';
import '../widgets/ar_unsupported_view.dart';

/// Entry point for an AR task. Runs the capability check and routes to the
/// right state UI. On an AR-capable device it shows an instructions card and
/// then launches the real mini-game ([ArMinigameView]) identified by
/// [arGameId]; on unsupported devices it falls back gracefully so a player is
/// never stuck.
class ARTaskScreen extends StatelessWidget {
  final String gameId;
  final int taskIndex;

  /// Which AR mini-game to launch (e.g. 'ar_balloon_pop'). Comes from the
  /// task's [Task.arGameId]. When null/unknown the screen offers a graceful
  /// skip instead of crashing.
  final String? arGameId;

  const ARTaskScreen({
    super.key,
    required this.gameId,
    required this.taskIndex,
    this.arGameId,
  });

  @override
  Widget build(BuildContext context) {
    final authState = context.read<AuthBloc>().state;
    final userId = authState is AuthAuthenticated ? authState.user.id : '';

    return BlocProvider(
      create: (_) => ArTaskBloc(
        capabilityService: sl<ArCapabilityService>(),
        gameRepository: sl<GameRepository>(),
        gameId: gameId,
        taskIndex: taskIndex,
        userId: userId,
      )..add(const ArCheckRequested()),
      child: _ARTaskView(arGameId: arGameId),
    );
  }
}

class _ARTaskView extends StatelessWidget {
  final String? arGameId;

  const _ARTaskView({required this.arGameId});

  @override
  Widget build(BuildContext context) {
    final config = ArGameConfig.byId(arGameId);

    return Scaffold(
      appBar: AppBar(title: Text(config?.title ?? 'AR Task')),
      body: BlocConsumer<ArTaskBloc, ArTaskState>(
        listener: (context, state) {
          if (state is ArTaskSubmitted) {
            // The full loop is done — return to the game so the scoreboard
            // (driven by the game stream) reflects the new score.
            Navigator.of(context).maybePop();
          }
        },
        builder: (context, state) {
          final bloc = context.read<ArTaskBloc>();

          if (state is ArTaskChecking || state is ArTaskSubmitting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is ArTaskUnsupported) {
            return ArUnsupportedView(
              reason: state.reason,
              onSkip: () => bloc.add(const ArSkipRequested()),
              onUpdateArCore: state.reason == ArSupport.needsArCoreUpdate
                  ? () => bloc.add(const ArCheckRequested())
                  : null,
            );
          }

          if (state is ArTaskPermissionDenied) {
            return ArUnsupportedView(
              reason: ArSupport.cameraDenied,
              onSkip: () => bloc.add(const ArSkipRequested()),
              onOpenSettings: () => sl<ArCapabilityService>().openSettings(),
            );
          }

          if (state is ArTaskError) {
            return _ErrorView(
              message: state.message,
              onRetry: () => bloc.add(const ArCheckRequested()),
              onSkip: () => bloc.add(const ArSkipRequested()),
            );
          }

          // Capable path. If we somehow don't know which game to run, offer a
          // graceful skip rather than a blank/crashing screen.
          if (config == null) {
            return _ErrorView(
              message: 'Unknown AR game "${arGameId ?? ''}".',
              onRetry: () => bloc.add(const ArCheckRequested()),
              onSkip: () => bloc.add(const ArSkipRequested()),
            );
          }

          // Playing — the live AR mini-game.
          if (state is ArTaskPlaying) {
            return ArMinigameView(
              config: config,
              onFinished: (score, rawResult) => bloc.add(
                ArScoreSubmitted(score: score, rawResult: rawResult),
              ),
              onSkip: () => bloc.add(const ArSkipRequested()),
            );
          }

          // Ready (or any post-check capable state) — instructions + Start.
          return _IntroCard(
            config: config,
            onStart: () => bloc.add(const ArPlayStarted()),
            onSkip: () => bloc.add(const ArSkipRequested()),
          );
        },
      ),
    );
  }
}

/// Pre-game instructions with a Start button. Gives the camera a beat to settle
/// and tells the player what to do before the timer starts.
class _IntroCard extends StatelessWidget {
  final ArGameConfig config;
  final VoidCallback onStart;
  final VoidCallback onSkip;

  const _IntroCard({
    required this.config,
    required this.onStart,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isGemRush = config.speedBonus;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isGemRush ? Icons.diamond : Icons.celebration,
              size: 72,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              config.title,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              isGemRush
                  ? 'Tap all ${config.objectCount} gems before the clock runs '
                      'out. Faster finishes score higher — you have '
                      '${config.duration.inSeconds}s.'
                  : 'Pop as many balloons as you can in '
                      '${config.duration.inSeconds} seconds. Move your phone to '
                      'find them and tap to pop!',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onSkip,
              icon: const Icon(Icons.skip_next),
              label: const Text('Skip this task'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onSkip;

  const _ErrorView({
    required this.message,
    required this.onRetry,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 56, color: Colors.red),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
            const SizedBox(height: 8),
            TextButton(onPressed: onSkip, child: const Text('Skip this task')),
          ],
        ),
      ),
    );
  }
}
