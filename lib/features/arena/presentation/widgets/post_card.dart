import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../../core/models/submission.dart';
import '../../../../core/services/video/video_policy.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/link_utils.dart';
import '../../domain/models/feed_post.dart';
import 'arena_video.dart';
import 'post_badge.dart';
import 'stamp_sticker.dart';

/// One Arena entry: the media, its auto-stamp and badges, and a footer with
/// who posted it and their auto caption. Used by both the Arena queue and
/// Watch together.
///
/// [onTap] is the viewer's optional "funny" tap — never required, never
/// blocking. PostCard itself owns the tiny 🔥 burst feedback; the caller
/// decides what a tap means (TapCurrent in the Arena, a direct
/// `feedRepository.tapPost` in Watch together).
///
/// The `atSecond` handed to [onTap] is the second of the clip the viewer was
/// watching (`VideoPolicy.tapBucket`), and null for photo/text/link posts,
/// which have no timeline. That histogram is the raw signal automatic editing
/// will later trim on — which is why the tap carries a timestamp even though
/// nothing reads it yet.
class PostCard extends StatefulWidget {
  final FeedPost post;
  final void Function(int? atSecond)? onTap;

  /// Start the clip as soon as the card is built. Off for cards in a long
  /// list that are not the one being graded.
  final bool autoPlay;

  /// Loop the clip at its cap. Watch together turns this off so it can advance
  /// to the next entry when the clip ends instead.
  final bool loopVideo;

  /// Fired when a clip reaches its cap — or fails to load, so a broken clip
  /// never stalls a playlist.
  final VoidCallback? onVideoEnded;

  const PostCard({
    super.key,
    required this.post,
    this.onTap,
    this.autoPlay = true,
    this.loopVideo = true,
    this.onVideoEnded,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _Burst {
  final Object key;
  final Offset position;
  const _Burst(this.key, this.position);
}

class _PostCardState extends State<PostCard> {
  final List<_Burst> _bursts = [];

  /// Lets the tap handler ask the player where it is, without the card
  /// rebuilding on every frame of playback.
  final GlobalKey<ArenaVideoState> _videoKey = GlobalKey<ArenaVideoState>();

  /// The second of the clip the viewer is on, bucketed, or null for a post
  /// with no timeline.
  int? _tapSecond() {
    if (widget.post.mediaType != SubmissionMediaType.video) return null;
    final player = _videoKey.currentState;
    if (player == null) return null;
    return VideoPolicy.tapBucket(
      player.currentPositionSeconds,
      player.capSeconds.ceil(),
    );
  }

  void _handleTapUp(TapUpDetails details) {
    final key = UniqueKey();
    final atSecond = _tapSecond();
    setState(() {
      _bursts.add(_Burst(key, details.localPosition));
    });
    widget.onTap?.call(atSecond);
  }

  void _removeBurst(Object key) {
    if (!mounted) return;
    setState(() {
      _bursts.removeWhere((b) => b.key == key);
    });
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: _handleTapUp,
            child: AspectRatio(
              aspectRatio: 4 / 5,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _Media(
                    post: post,
                    videoKey: _videoKey,
                    autoPlay: widget.autoPlay,
                    loopVideo: widget.loopVideo,
                    onVideoEnded: widget.onVideoEnded,
                  ),
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Row(
                      children: [
                        if (post.isLate) ...[
                          const PostBadge('LATE', Color(0xFFE0395E)),
                          const SizedBox(width: 6),
                        ],
                        if (post.isHouse)
                          const PostBadge('HOUSE', Color(0xFF6B6478)),
                      ],
                    ),
                  ),
                  if (post.displayStamp != null)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: StampSticker(post.displayStamp!),
                    ),
                  for (final burst in _bursts)
                    Positioned(
                      left: burst.position.dx - 20,
                      top: burst.position.dy - 20,
                      child: _BurstEmoji(
                        onDone: () => _removeBurst(burst.key),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        post.displayName,
                        style: Theme.of(context).textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (post.tapCount > 0) ...[
                      const SizedBox(width: 8),
                      Text(
                        '\u{1F525} ${post.tapCount}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
                Text(
                  post.taskTitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.inkSoft,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (post.caption != null && post.caption!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    post.caption!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Media extends StatelessWidget {
  final FeedPost post;
  final GlobalKey<ArenaVideoState> videoKey;
  final bool autoPlay;
  final bool loopVideo;
  final VoidCallback? onVideoEnded;

  const _Media({
    required this.post,
    required this.videoKey,
    required this.autoPlay,
    required this.loopVideo,
    this.onVideoEnded,
  });

  @override
  Widget build(BuildContext context) {
    switch (post.mediaType) {
      case SubmissionMediaType.video:
        return ArenaVideo(
          key: videoKey,
          url: post.videoUrl,
          durationSeconds: post.videoDurationSeconds,
          timerSeconds: post.timerSeconds,
          clockOffsetSeconds: post.clockOffsetSeconds,
          isLate: post.isLate,
          // House clips ship with the countdown already in the pixels.
          burnedIn: post.isHouse,
          autoPlay: autoPlay,
          loop: loopVideo,
          onEnded: onVideoEnded,
        );
      case SubmissionMediaType.photo:
        if (post.photoData != null && post.photoData!.isNotEmpty) {
          try {
            final bytes = base64Decode(post.photoData!);
            return Image.memory(
              bytes,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            );
          } catch (_) {
            return const _TextFallback(text: 'Could not load photo');
          }
        }
        return const _TextFallback(text: 'No photo');
      case SubmissionMediaType.text:
        return _TextFallback(text: post.text ?? '');
      case SubmissionMediaType.link:
        return _LinkChip(url: post.videoUrl);
    }
  }
}

/// Text entries (and any missing/broken media) render large on the brand
/// gradient, matching the auto-frame treatment of a photo.
class _TextFallback extends StatelessWidget {
  final String text;

  const _TextFallback({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppTheme.heroGradient),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontFamily: 'Fredoka',
          fontWeight: FontWeight.w600,
          fontSize: 24,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _LinkChip extends StatelessWidget {
  final String? url;

  const _LinkChip({required this.url});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppTheme.heroGradient),
      alignment: Alignment.center,
      child: ActionChip(
        avatar: const Icon(Icons.play_circle_outline, color: AppTheme.violet),
        label: const Text('Watch video'),
        backgroundColor: Colors.white,
        onPressed: url == null ? null : () => LinkUtils.openExternal(context, url),
      ),
    );
  }
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
        curve: Curves.easeOut,
        child: AnimatedScale(
          scale: _grown ? 1.8 : 0.6,
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOut,
          child: const Text('\u{1F525}', style: TextStyle(fontSize: 32)),
        ),
      ),
    );
  }
}
