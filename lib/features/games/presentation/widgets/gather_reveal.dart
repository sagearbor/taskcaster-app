import 'package:flutter/material.dart';

import '../../../../core/models/task.dart';
import '../../../../core/services/sfx/game_sfx.dart';
import '../../../../core/theme/app_theme.dart';
import 'task_countdown.dart';

/// Stage 1 of a gather -> reveal task (the classic misdirect): the gather
/// prompt, a big countdown and "I'm back". It shows ONLY the gather stage
/// ([Task.teaserTitle] / [Task.gatherPrompt]); the real task's title,
/// description, twist and rubric are never on screen here.
///
/// [onDone] fires once, either when the clock hits zero or on "I'm back".
class GatherStageView extends StatelessWidget {
  final Task task;
  final DateTime startedAt;
  final VoidCallback onDone;
  final GameSfx? sfx;

  /// The wall clock, injectable so tests are deterministic.
  final DateTime Function() now;

  const GatherStageView({
    super.key,
    required this.task,
    required this.startedAt,
    required this.onDone,
    this.sfx,
    this.now = DateTime.now,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      key: const Key('gather-stage'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'FIRST, GATHER',
            style: theme.textTheme.labelMedium?.copyWith(
              letterSpacing: 1.5,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            task.teaserTitle,
            key: const Key('gather-title'),
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800, height: 1.15),
          ),
          const SizedBox(height: 8),
          Text(task.gatherPrompt ?? '', style: theme.textTheme.bodyLarge),
          const SizedBox(height: 20),
          Center(
            child: TaskCountdown(
              key: const Key('gather-countdown'),
              startedAt: startedAt,
              durationSeconds: task.gatherSeconds ?? 60,
              // Never LATE: the reveal takes over at zero.
              graceSeconds: 1 << 20,
              now: now,
              sfx: sfx,
              onExpired: onDone,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 60,
            child: FilledButton(
              key: const Key('gather-im-back'),
              onPressed: onDone,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.coral,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                "I'm back",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Bring it all back here. What it is for comes next.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Stage 2's entrance: a tilted "SURPRISE." stamp that slams in above the
/// real task the moment the gather stage ends. Skips the motion when the
/// platform asks for reduced motion.
class SurpriseRevealBanner extends StatefulWidget {
  const SurpriseRevealBanner({super.key});

  @override
  State<SurpriseRevealBanner> createState() => _SurpriseRevealBannerState();
}

class _SurpriseRevealBannerState extends State<SurpriseRevealBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _c.value = 1;
    } else if (!_c.isAnimating && _c.value == 0) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = Tween<double>(begin: 1.8, end: 1.0)
        .chain(CurveTween(curve: Curves.easeOutBack))
        .animate(_c);
    final fade = CurvedAnimation(
        parent: _c, curve: const Interval(0, 0.4, curve: Curves.easeOut));
    return Column(
      key: const Key('gather-reveal-banner'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        FadeTransition(
          opacity: fade,
          child: ScaleTransition(
            scale: scale,
            child: Transform.rotate(
              angle: -0.06,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.coral,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Text(
                  'SURPRISE.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        FadeTransition(
          opacity: fade,
          child: Text(
            'Here is what it was for.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
