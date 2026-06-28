import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/services/ar/ar_engine.dart';
import '../../../../core/services/ar/ar_games.dart';
import '../../../../core/services/ar/ar_minigame_controller.dart';

/// Hosts a live AR mini-game: the platform AR camera view + a score/timer HUD,
/// driven entirely by [ArMinigameController] over the [ArEngine] abstraction.
/// When the round ends it surfaces a results card; pressing "Submit Score"
/// invokes [onFinished] with the final score and the raw hit count so the
/// caller (the bloc) can write it to the scoreboard.
///
/// DEVICE-ONLY: the actual camera + 3D rendering needs a physical ARCore/ARKit
/// device. The widget builds and the HUD/score flow is testable, but the AR
/// surface itself cannot be verified off-device.
class ArMinigameView extends StatefulWidget {
  final ArGameConfig config;
  final void Function(int score, int rawResult) onFinished;
  final VoidCallback onSkip;

  const ArMinigameView({
    super.key,
    required this.config,
    required this.onFinished,
    required this.onSkip,
  });

  @override
  State<ArMinigameView> createState() => _ArMinigameViewState();
}

class _ArMinigameViewState extends State<ArMinigameView> {
  late final ArEngine _engine;
  late final ArMinigameController _controller;
  bool _submitted = false;
  // If we're still scanning (nothing placed) after this long, it's probably too
  // dark or there's no good surface — escalate the on-screen hint.
  Timer? _scanTimer;
  bool _scanTimedOut = false;

  @override
  void initState() {
    super.initState();
    _engine = sl<ArEngine>();
    _controller = ArMinigameController(engine: _engine, config: widget.config);
    // Kick off the session; spawning waits on plane detection internally.
    _controller.start();
    _scanTimer = Timer(const Duration(seconds: 8), () {
      if (mounted && !_controller.objectsSpawned) {
        setState(() => _scanTimedOut = true);
      }
    });
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_submitted) return;
    _submitted = true;
    widget.onFinished(_controller.finalScore, _controller.hits);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // The platform AR camera view fills the screen.
        _engine.buildView(),

        // HUD + overlays react to controller changes.
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            if (_controller.error != null && !_controller.hasLiveObjects) {
              return _ErrorOverlay(
                message: _controller.error!,
                onSkip: widget.onSkip,
              );
            }
            if (_controller.finished) {
              return _ResultsOverlay(
                config: widget.config,
                hits: _controller.hits,
                score: _controller.finalScore,
                onSubmit: _submit,
              );
            }
            return _Hud(
              config: widget.config,
              controller: _controller,
              onSkip: widget.onSkip,
              scanTimedOut: _scanTimedOut,
            );
          },
        ),

        // Brief red "oops" flash when a bomb is tapped.
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => IgnorePointer(
            child: AnimatedOpacity(
              opacity: _controller.bombFlash ? 1 : 0,
              duration: const Duration(milliseconds: 120),
              child: Container(color: Colors.red.withOpacity(0.35)),
            ),
          ),
        ),
      ],
    );
  }
}

class _Hud extends StatelessWidget {
  final ArGameConfig config;
  final ArMinigameController controller;
  final VoidCallback onSkip;
  final bool scanTimedOut;

  const _Hud({
    required this.config,
    required this.controller,
    required this.onSkip,
    this.scanTimedOut = false,
  });

  @override
  Widget build(BuildContext context) {
    final scanning = !controller.objectsSpawned;
    return SafeArea(
      child: Stack(
        children: [
          // Top bar: timer + score.
          Positioned(
            top: 8,
            left: 12,
            right: 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _Pill(
                  icon: Icons.timer,
                  label: '${controller.secondsRemaining}s',
                ),
                _Pill(
                  icon: config.speedBonus ? Icons.diamond : Icons.celebration,
                  label: config.respawnOnHit
                      ? 'Score ${controller.liveScore}'
                      : '${controller.hits}/${config.objectCount}',
                ),
              ],
            ),
          ),

          if (scanning)
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 32),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      scanTimedOut
                          ? Icons.lightbulb_outline
                          : Icons.center_focus_strong,
                      color: Colors.white,
                      size: 28,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      scanTimedOut
                          ? "Still can't find a surface — it may be too dark.\n"
                              'AR needs light: move somewhere brighter and point '
                              'at a textured floor or table.'
                          : 'Point at a well-lit floor or table and move your '
                              'phone slowly to scan.\nAR needs light to find a '
                              'surface.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, height: 1.3),
                    ),
                  ],
                ),
              ),
            ),

          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Center(
              child: TextButton.icon(
                onPressed: onSkip,
                style: TextButton.styleFrom(
                  backgroundColor: Colors.black54,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.skip_next),
                label: const Text('Skip this task'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _Pill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultsOverlay extends StatelessWidget {
  final ArGameConfig config;
  final int hits;
  final int score;
  final VoidCallback onSubmit;

  const _ResultsOverlay({
    required this.config,
    required this.hits,
    required this.score,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = config.speedBonus ? 'gems found' : 'balloons popped';
    return Container(
      color: Colors.black.withOpacity(0.7),
      child: Center(
        child: Card(
          margin: const EdgeInsets.all(32),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  config.speedBonus ? Icons.diamond : Icons.celebration,
                  size: 56,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 12),
                Text('Time! ${config.title}',
                    style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text('$hits $unit', style: theme.textTheme.bodyMedium),
                const SizedBox(height: 4),
                Text(
                  'Score: $score',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: onSubmit,
                  icon: const Icon(Icons.leaderboard),
                  label: const Text('Submit Score'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorOverlay extends StatelessWidget {
  final String message;
  final VoidCallback onSkip;

  const _ErrorOverlay({required this.message, required this.onSkip});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(0.7),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.white),
              const SizedBox(height: 12),
              Text(
                "Couldn't start the AR game.\n$message",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 20),
              FilledButton(onPressed: onSkip, child: const Text('Skip task')),
            ],
          ),
        ),
      ),
    );
  }
}
