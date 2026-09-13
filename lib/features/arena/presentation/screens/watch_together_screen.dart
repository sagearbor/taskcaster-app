import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/models/submission.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/models/feed_post.dart';
import '../../domain/models/montage.dart';
import '../../domain/repositories/feed_repository.dart';
import '../../domain/repositories/montage_repository.dart';
import '../widgets/arena_video.dart';
import '../widgets/post_card.dart';

/// Same-room playback: every entry for one task, back to back, from one
/// phone. Self-contained — no bloc, just a stream subscription and a timer.
/// See docs/PRODUCT_DIRECTION.md §2.4.
class WatchTogetherScreen extends StatefulWidget {
  final String gameId;
  final String taskId;
  final String taskTitle;

  const WatchTogetherScreen({
    super.key,
    required this.gameId,
    required this.taskId,
    required this.taskTitle,
  });

  @override
  State<WatchTogetherScreen> createState() => _WatchTogetherScreenState();
}

class _WatchTogetherScreenState extends State<WatchTogetherScreen>
    with SingleTickerProviderStateMixin {
  static const _slideDuration = Duration(seconds: 6);

  late final AnimationController _progress;
  StreamSubscription<List<FeedPost>>? _subscription;
  StreamSubscription<Montage?>? _montageSubscription;
  List<FeedPost>? _posts;
  Montage? _montage;
  int _index = 0;
  final List<_ScreenBurst> _bursts = [];

  /// Keyed so a tap anywhere on a finale slide can still ask the player where
  /// it is (the finale is not a PostCard).
  final GlobalKey<ArenaVideoState> _finaleKey = GlobalKey<ArenaVideoState>();

  @override
  void initState() {
    super.initState();
    _progress = AnimationController(vsync: this, duration: _slideDuration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _advance();
        }
      });
    _subscription = sl<FeedRepository>()
        .watchPostsForTask(gameId: widget.gameId, taskId: widget.taskId)
        .listen(_onPosts);
    // The automatic finale, when the server has rendered one. Never blocks:
    // an absent or still-rendering montage simply means the run ends on the
    // results card exactly as it did before.
    _montageSubscription = sl<MontageRepository>()
        .watchMontage(widget.gameId, widget.taskId)
        .listen(
          (montage) {
            if (mounted) setState(() => _montage = montage);
          },
          onError: (Object e) => debugPrint('Watch together montage: $e'),
        );
  }

  /// Video entries run on the clip's own length, not the slideshow timer:
  /// `_advance` is driven by `onVideoEnded`.
  bool _isVideo(FeedPost post) => post.mediaType == SubmissionMediaType.video;

  /// True when the run should show the finale after the last entry.
  bool get _hasFinale => _montage?.isReady ?? false;

  void _onPosts(List<FeedPost> posts) {
    final wasNull = _posts == null;
    setState(() {
      _posts = posts;
      if (_index > posts.length) _index = posts.length;
    });
    if (wasNull && posts.isNotEmpty) _restartSlideTimer(posts[0]);
  }

  /// Photo and text entries get the fixed slideshow beat; a clip gets as long
  /// as the clip is (capped by VideoPolicy), so the timer stays stopped and
  /// ArenaVideo's `onEnded` advances instead.
  void _restartSlideTimer(FeedPost post) {
    if (_isVideo(post)) {
      _progress.stop();
      _progress.value = 0;
      return;
    }
    _progress
      ..reset()
      ..forward();
  }

  void _advance() {
    final posts = _posts;
    if (posts == null) return;
    final lastIndex = _hasFinale ? posts.length : posts.length - 1;
    if (_index <= lastIndex) {
      setState(() => _index += 1);
    }
    if (_index < posts.length) {
      _restartSlideTimer(posts[_index]);
    } else {
      // The finale (when there is one) runs on its own length, like a clip.
      _progress.stop();
    }
  }

  void _tapPost(FeedPost post, {int? atSecond}) {
    // Fire-and-forget viewer "funny" tap — never required, never blocking.
    unawaited(sl<FeedRepository>().tapPost(post.id, atSecond: atSecond));
  }

  void _handleScreenTapUp(TapUpDetails details, FeedPost post) {
    final key = UniqueKey();
    setState(() => _bursts.add(_ScreenBurst(key, details.localPosition)));
    _tapPost(post, atSecond: null);
  }

  void _removeBurst(Object key) {
    if (!mounted) return;
    setState(() => _bursts.removeWhere((b) => b.key == key));
  }

  @override
  void dispose() {
    _progress.dispose();
    _subscription?.cancel();
    _montageSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final posts = _posts;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: posts == null
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            : posts.isEmpty
                ? _EmptyState(onDone: () => Navigator.of(context).pop())
                : _index < posts.length
                    ? _buildSlide(context, posts[_index], posts.length)
                    : (_index == posts.length && _hasFinale)
                        ? _buildFinaleSlide(context)
                        : _ResultsList(
                            posts: posts,
                            onDone: () => Navigator.of(context).pop(),
                          ),
      ),
    );
  }

  Widget _buildSlide(BuildContext context, FeedPost post, int total) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (details) => _handleScreenTapUp(details, post),
      onHorizontalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) < 0) _advance();
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: AnimatedBuilder(
                  animation: _progress,
                  builder: (context, _) => ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      // A clip has no fixed beat to count down, so the bar
                      // runs indeterminate until it ends.
                      value: _isVideo(post) ? null : _progress.value,
                      minHeight: 3,
                      backgroundColor: Colors.white24,
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  '${_index + 1} / $total',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: PostCard(
                      post: post,
                      // In a playlist a clip plays once and hands over; it
                      // does not loop. A clip that fails to load also fires
                      // onEnded, so a broken entry can never stall the run.
                      loopVideo: false,
                      onVideoEnded: _isVideo(post) ? _advance : null,
                      onTap: (atSecond) => _tapPost(post, atSecond: atSecond),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: TextButton.icon(
                  onPressed: _advance,
                  icon: const Icon(Icons.arrow_forward, color: Colors.white),
                  label: const Text('Next', style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
          for (final burst in _bursts)
            Positioned(
              left: burst.position.dx - 20,
              top: burst.position.dy - 20,
              child: _BurstEmoji(onDone: () => _removeBurst(burst.key)),
            ),
        ],
      ),
    );
  }

  /// The automatic finale: every entry's last two seconds, spliced server-side.
  /// The countdown is already burned into those pixels, so ArenaVideo does not
  /// draw another one.
  Widget _buildFinaleSlide(BuildContext context) {
    final montage = _montage;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) < 0) _advance();
      },
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'The finale',
              key: Key('watch-together-finale'),
              style: TextStyle(
                color: Colors.white,
                fontFamily: 'Fredoka',
                fontWeight: FontWeight.w600,
                fontSize: 24,
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: AspectRatio(
                aspectRatio: 4 / 5,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: ArenaVideo(
                    key: _finaleKey,
                    url: montage?.finaleUrl,
                    burnedIn: true,
                    loop: false,
                    onEnded: _advance,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: TextButton.icon(
              onPressed: _advance,
              icon: const Icon(Icons.arrow_forward, color: Colors.white),
              label:
                  const Text('Results', style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScreenBurst {
  final Object key;
  final Offset position;

  const _ScreenBurst(this.key, this.position);
}

class _BurstEmoji extends StatefulWidget {
  final VoidCallback onDone;

  const _BurstEmoji({required this.onDone});

  @override
  State<_BurstEmoji> createState() => _BurstEmojiState();
}

class _BurstEmojiState extends State<_BurstEmoji> {
  bool _grown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _grown = true);
    });
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) widget.onDone();
    });
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _grown ? 0 : 1,
        duration: const Duration(milliseconds: 380),
        child: AnimatedScale(
          scale: _grown ? 1.8 : 0.6,
          duration: const Duration(milliseconds: 380),
          child: const Text('\u{1F525}', style: TextStyle(fontSize: 32)),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onDone;

  const _EmptyState({required this.onDone});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Nothing posted for this task yet.',
              style: TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: onDone,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white54),
              ),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultsList extends StatelessWidget {
  final List<FeedPost> posts;
  final VoidCallback onDone;

  const _ResultsList({required this.posts, required this.onDone});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Results',
              style: TextStyle(
                color: Colors.white,
                fontFamily: 'Fredoka',
                fontWeight: FontWeight.w600,
                fontSize: 24,
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: posts.length,
            separatorBuilder: (_, __) =>
                const Divider(color: Colors.white24, height: 1),
            itemBuilder: (context, index) {
              final post = posts[index];
              final points = post.crowdPoints;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  post.displayName,
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  points != null ? '$points pts' : 'unscored',
                  style: const TextStyle(color: Colors.white60),
                ),
                trailing: Text(
                  '\u{1F525} ${post.tapCount}',
                  style: const TextStyle(color: AppTheme.goldBright),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onDone,
              child: const Text('Done'),
            ),
          ),
        ),
      ],
    );
  }
}
