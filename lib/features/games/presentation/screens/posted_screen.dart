import 'package:flutter/material.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/models/game.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../arena/domain/models/feed_post.dart';
import '../../../arena/domain/repositories/feed_repository.dart';
import '../../../arena/presentation/screens/arena_screen_placeholder.dart';
import '../../domain/repositories/game_repository.dart';
import '../widgets/late_badge.dart';
import '../widgets/stamp_sticker.dart';
import 'task_execution_screen.dart';

/// The reveal moment (tap after Snap it / Write it → Post it):
/// "Posted. You've unlocked everyone else's attempt at: <task>" — see
/// docs/PRODUCT_DIRECTION.md §4 step 4. Replaces the task screen
/// (`Navigator.pushReplacement`) so the back button returns to Home, not to
/// the just-submitted task.
class PostedScreen extends StatefulWidget {
  final String gameId;
  final int taskIndex;
  final String taskTitle;

  /// The Arena post this attempt created, when it was shared — drives the
  /// sticker via `FeedRepository.watchPost`. Null when nothing was shared
  /// (e.g. shareToArena was off), in which case the sticker is skipped.
  final String? feedPostId;

  final bool isLate;

  const PostedScreen({
    super.key,
    required this.gameId,
    required this.taskIndex,
    required this.taskTitle,
    this.feedPostId,
    this.isLate = false,
  });

  @override
  State<PostedScreen> createState() => _PostedScreenState();
}

class _PostedScreenState extends State<PostedScreen> {
  late Future<Game?> _gameFuture;

  @override
  void initState() {
    super.initState();
    _gameFuture = sl<GameRepository>().getGameStream(widget.gameId).first;
  }

  void _openArena() {
    // TODO(round7-merge): swap for the real ArenaScreen() once feat/arena-ui
    // lands on main — see arena_screen_placeholder.dart.
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ArenaScreenPlaceholder()),
    );
  }

  void _goNextTask(int nextIndex) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => TaskExecutionScreen(
          gameId: widget.gameId,
          taskIndex: nextIndex,
          autoStart: true,
        ),
      ),
    );
  }

  void _backHome() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.violetDeep,
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(gradient: AppTheme.heroGradient),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Posted.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 24),
                if (widget.feedPostId != null) _stickerSection(),
                if (widget.isLate) ...[
                  const SizedBox(height: 12),
                  const Center(child: LateBadge()),
                ],
                const SizedBox(height: 28),
                Text(
                  'You\'ve unlocked everyone else\'s attempt at: '
                  '${widget.taskTitle}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white.withOpacity(0.92),
                      ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  height: 58,
                  child: FilledButton(
                    onPressed: _openArena,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.coral,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'See theirs',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FutureBuilder<Game?>(
                  future: _gameFuture,
                  builder: (context, snapshot) {
                    final game = snapshot.data;
                    final nextIndex = widget.taskIndex + 1;
                    final hasNext =
                        game != null && nextIndex < game.tasks.length;
                    final nextSeconds = hasNext
                        ? game.tasks[nextIndex].durationSeconds
                        : null;

                    return SizedBox(
                      height: 52,
                      child: OutlinedButton(
                        onPressed: hasNext
                            ? () => _goNextTask(nextIndex)
                            : _backHome,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white70),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          hasNext
                              ? 'Next task${nextSeconds != null ? ' — $nextSeconds s' : ''}'
                              : 'Back home',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                      ),
                    );
                  },
                ),
                // "Add a word for the judge" — the spec wants an optional,
                // collapsed-by-default single-line field whose submit
                // appends to the post's caption via
                // `FeedRepository.appendCaption(postId, text)`. That method
                // does not exist in the merged Arena contracts
                // (tmp/round7/CONTRACTS.md's FeedRepository has no
                // `appendCaption`), so per the task brief the button stays
                // hidden here rather than wired to a non-existent method.
                // TODO(round7-merge): add FeedRepository.appendCaption and
                // reveal this button once it exists.
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stickerSection() {
    return StreamBuilder<FeedPost?>(
      stream: sl<FeedRepository>().watchPost(widget.feedPostId!),
      builder: (context, snapshot) {
        final stamp = snapshot.data?.stamp;
        if (stamp == null) return const SizedBox.shrink();
        return Center(child: StampSticker(stamp: stamp, scale: 1.3));
      },
    );
  }
}
