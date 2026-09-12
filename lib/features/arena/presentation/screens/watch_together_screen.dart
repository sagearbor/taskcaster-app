import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/models/feed_post.dart';
import '../../domain/repositories/feed_repository.dart';
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
  List<FeedPost>? _posts;
  int _index = 0;
  final List<_ScreenBurst> _bursts = [];

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
  }

  void _onPosts(List<FeedPost> posts) {
    final wasNull = _posts == null;
    setState(() {
      _posts = posts;
      if (_index > posts.length) _index = posts.length;
    });
    if (wasNull && posts.isNotEmpty) {
      _progress
        ..reset()
        ..forward();
    }
  }

  void _advance() {
    final posts = _posts;
    if (posts == null) return;
    if (_index < posts.length) {
      setState(() => _index += 1);
    }
    if (_index < posts.length) {
      _progress
        ..reset()
        ..forward();
    } else {
      _progress.stop();
    }
  }

  void _tapPost(FeedPost post) {
    // Fire-and-forget viewer "funny" tap — never required, never blocking.
    unawaited(sl<FeedRepository>().tapPost(post.id));
  }

  void _handleScreenTapUp(TapUpDetails details, FeedPost post) {
    final key = UniqueKey();
    setState(() => _bursts.add(_ScreenBurst(key, details.localPosition)));
    _tapPost(post);
  }

  void _removeBurst(Object key) {
    if (!mounted) return;
    setState(() => _bursts.removeWhere((b) => b.key == key));
  }

  @override
  void dispose() {
    _progress.dispose();
    _subscription?.cancel();
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
                : _index >= posts.length
                    ? _ResultsList(
                        posts: posts,
                        onDone: () => Navigator.of(context).pop(),
                      )
                    : _buildSlide(context, posts[_index], posts.length),
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
                      value: _progress.value,
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
                    child: PostCard(post: post),
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
