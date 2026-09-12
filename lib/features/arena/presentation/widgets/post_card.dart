import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../../core/models/submission.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/link_utils.dart';
import '../../domain/models/feed_post.dart';
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
class PostCard extends StatefulWidget {
  final FeedPost post;
  final VoidCallback? onTap;

  const PostCard({super.key, required this.post, this.onTap});

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

  void _handleTapUp(TapUpDetails details) {
    final key = UniqueKey();
    setState(() {
      _bursts.add(_Burst(key, details.localPosition));
    });
    widget.onTap?.call();
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
                  _Media(post: post),
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

  const _Media({required this.post});

  @override
  Widget build(BuildContext context) {
    switch (post.mediaType) {
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
