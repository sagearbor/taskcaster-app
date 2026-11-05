import 'package:flutter/material.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/models/game.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../arena/domain/models/feed_post.dart';
import '../../../arena/domain/repositories/feed_repository.dart';
import '../../../../core/services/share/share_service.dart';
import '../../../arena/presentation/screens/arena_screen.dart';
import '../../../arena/presentation/widgets/challenge_vs_card.dart';
import '../../../arena/presentation/widgets/share_attempt_button.dart';
import '../../domain/repositories/game_repository.dart';
import '../widgets/late_badge.dart';
import '../widgets/push_opt_in_card.dart';
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

  /// WP-09: the post this attempt answered (the share link's "Your turn").
  /// When set, the challenger's entry and this one are shown side by side —
  /// the payoff — and the challenge is attributed (share_attributions).
  final String? challengeFromPostId;

  /// The task's id and the poster's uid, for the attribution record.
  final String? taskId;
  final String? userId;

  /// Injectable for tests; defaults to the locator's [ShareService].
  final ShareService? shareService;

  const PostedScreen({
    super.key,
    required this.gameId,
    required this.taskIndex,
    required this.taskTitle,
    this.feedPostId,
    this.isLate = false,
    this.challengeFromPostId,
    this.taskId,
    this.userId,
    this.shareService,
  });

  @override
  State<PostedScreen> createState() => _PostedScreenState();
}

class _PostedScreenState extends State<PostedScreen> {
  late Future<Game?> _gameFuture;
  Stream<FeedPost?>? _myPost;

  @override
  void initState() {
    super.initState();
    _gameFuture = sl<GameRepository>().getGameStream(widget.gameId).first;
    final postId = widget.feedPostId;
    if (postId != null) {
      // One listener for the sticker and the Share button (asBroadcastStream).
      _myPost = sl<FeedRepository>().watchPost(postId).asBroadcastStream();
    }
    _recordChallenge();
  }

  ShareService get _share => widget.shareService ?? ShareService.fromLocator();

  /// "X took your challenge" groundwork: best-effort, once, never blocking.
  void _recordChallenge() {
    final from = widget.challengeFromPostId;
    final mine = widget.feedPostId;
    final uid = widget.userId;
    if (from == null || mine == null || uid == null || uid.isEmpty) return;
    _share.recordChallengeAttribution(
      uid: uid,
      fromPostId: from,
      postId: mine,
      taskId: widget.taskId ?? '',
    );
  }

  void _openArena() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ArenaScreen()),
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
        // Fill the whole body so the gradient covers the screen instead of
        // stopping at the content's height (flat scaffold colour showed
        // beneath it on tall phones).
        width: double.infinity,
        height: double.infinity,
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
                if (widget.challengeFromPostId != null) ...[
                  Text(
                    'You vs. them',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppTheme.goldBright,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                  ),
                  const SizedBox(height: 12),
                  ChallengeVsCard(
                    challengerPostId: widget.challengeFromPostId!,
                    myPostId: widget.feedPostId,
                  ),
                ] else if (widget.feedPostId != null)
                  _stickerSection(),
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
                // WP-09: sharing is the primary action — the growth loop is
                // "a friend sees your 8-second disaster -> Your turn".
                if (_myPost != null) ...[
                  StreamBuilder<FeedPost?>(
                    stream: _myPost,
                    builder: (context, snapshot) => ShareAttemptButton(
                      post: snapshot.data,
                      primary: true,
                      label: widget.challengeFromPostId != null
                          ? 'Send it back'
                          : 'Share your attempt',
                      shareService: widget.shareService,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                SizedBox(
                  height: 52,
                  child: _myPost == null
                      ? FilledButton(
                          key: const Key('see-theirs-button'),
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
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        )
                      : OutlinedButton(
                          key: const Key('see-theirs-button'),
                          onPressed: _openArena,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white70),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text(
                            'See theirs',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700),
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
                // Web push opt-in, asked here and nowhere else: the browser
                // gives exactly one chance to prompt, and this is the first
                // moment the player has a reason to want the answer. Renders
                // nothing on mobile or when already answered.
                if (widget.feedPostId != null) const PushOptInCard(),
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
      stream: _myPost,
      builder: (context, snapshot) {
        final stamp = snapshot.data?.stamp;
        if (stamp == null) return const SizedBox.shrink();
        return Center(child: StampSticker(stamp: stamp, scale: 1.3));
      },
    );
  }
}
