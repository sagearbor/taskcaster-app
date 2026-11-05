import 'package:flutter/material.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/services/share/share_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/models/montage.dart';
import '../../domain/repositories/montage_repository.dart';
import 'arena_video.dart';
import 'share_attempt_button.dart' show showShareOutcome;

/// "Watch the finale" — the server-rendered splice of every entry's last two
/// seconds for one task.
///
/// Renders NOTHING until a montage exists and is `ready`, so the Arena looks
/// exactly as it does today for tasks that have no render behind them. The
/// countdown is burned into the montage's pixels, so no overlay is drawn.
///
/// Stateful so the montage listener is opened once (and again only when the
/// task changes) rather than on every rebuild of the Arena.
class FinaleCard extends StatefulWidget {
  final String gameId;
  final String taskId;

  /// For the share caption; optional.
  final String taskTitle;

  /// Injectable for tests; defaults to the locator's [ShareService].
  final ShareService? shareService;

  const FinaleCard({
    super.key,
    required this.gameId,
    required this.taskId,
    this.taskTitle = '',
    this.shareService,
  });

  @override
  State<FinaleCard> createState() => _FinaleCardState();
}

class _FinaleCardState extends State<FinaleCard> {
  Stream<Montage?>? _montage;

  @override
  void initState() {
    super.initState();
    _montage = _open();
  }

  @override
  void didUpdateWidget(FinaleCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gameId != widget.gameId ||
        oldWidget.taskId != widget.taskId) {
      _montage = _open();
    }
  }

  Stream<Montage?>? _open() {
    // House entries carry no game, so they can never have a finale.
    if (widget.gameId.isEmpty || widget.taskId.isEmpty) return null;
    return sl<MontageRepository>().watchMontage(widget.gameId, widget.taskId);
  }

  /// WP-09 "Share the finale": the /f/ page plays it with OG video tags. The
  /// page is public only when every clip in it is (share_page.js), so a
  /// friend-game finale with private clips simply 404s for outsiders.
  Future<void> _shareFinale() async {
    final service = widget.shareService ?? ShareService.fromLocator();
    final outcome = await service.shareFinale(
      montageId: Montage.idFor(widget.gameId, widget.taskId),
      taskTitle: widget.taskTitle,
    );
    if (mounted) showShareOutcome(context, outcome);
  }

  @override
  Widget build(BuildContext context) {
    final montageStream = _montage;
    if (montageStream == null) return const SizedBox.shrink();

    return StreamBuilder<Montage?>(
      stream: montageStream,
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
                    Expanded(
                      child: Text(
                        'Watch the finale',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    TextButton.icon(
                      key: const Key('share-finale-button'),
                      onPressed: _shareFinale,
                      icon: const Icon(Icons.ios_share_rounded, size: 18),
                      label: const Text('Share the finale'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
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
