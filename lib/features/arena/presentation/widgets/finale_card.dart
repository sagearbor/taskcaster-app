import 'package:flutter/material.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/models/montage.dart';
import '../../domain/repositories/montage_repository.dart';
import 'arena_video.dart';

/// "Watch the finale" — the server-rendered splice of every entry's last two
/// seconds for one task.
///
/// Renders NOTHING until a montage exists and is `ready`, so the Arena looks
/// exactly as it does today for tasks that have no render behind them. The
/// countdown is burned into the montage's pixels, so no overlay is drawn.
class FinaleCard extends StatelessWidget {
  final String gameId;
  final String taskId;

  const FinaleCard({super.key, required this.gameId, required this.taskId});

  @override
  Widget build(BuildContext context) {
    // House entries carry no game, so they can never have a finale.
    if (gameId.isEmpty || taskId.isEmpty) return const SizedBox.shrink();

    return StreamBuilder<Montage?>(
      stream: sl<MontageRepository>().watchMontage(gameId, taskId),
      builder: (context, snapshot) {
        final montage = snapshot.data;
        if (montage == null || !montage.isReady) {
          return const SizedBox.shrink();
        }
        return Card(
          key: const Key('arena-finale-card'),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: Row(
                  children: [
                    const Icon(Icons.movie_filter_outlined,
                        size: 18, color: AppTheme.violet),
                    const SizedBox(width: 8),
                    Text(
                      'Watch the finale',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              // Slim on purpose: the finale sits above the queue, it does not
              // replace the entry the viewer is here to grade.
              AspectRatio(
                aspectRatio: 16 / 9,
                child: ArenaVideo(
                  url: montage.finaleUrl,
                  burnedIn: true,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
