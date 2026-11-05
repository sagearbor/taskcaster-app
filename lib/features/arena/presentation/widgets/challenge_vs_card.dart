import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/models/submission.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/models/feed_post.dart';
import '../../domain/repositories/feed_repository.dart';
import 'arena_video.dart';
import 'stamp_sticker.dart';

/// The payoff of a share link (audit WP-09): THEIR attempt and YOURS, side by
/// side, the moment you post. Both clips loop muted; each tile carries the
/// first name, the stamp and the time taken.
class ChallengeVsCard extends StatefulWidget {
  final String challengerPostId;
  final String? myPostId;

  /// Injectable for tests; defaults to the locator's [FeedRepository].
  final FeedRepository? feedRepository;

  const ChallengeVsCard({
    super.key,
    required this.challengerPostId,
    required this.myPostId,
    this.feedRepository,
  });

  @override
  State<ChallengeVsCard> createState() => _ChallengeVsCardState();
}

class _ChallengeVsCardState extends State<ChallengeVsCard> {
  late final Stream<FeedPost?> _theirs;
  Stream<FeedPost?>? _mine;

  @override
  void initState() {
    super.initState();
    final feed = widget.feedRepository ?? sl<FeedRepository>();
    _theirs = feed.watchPost(widget.challengerPostId);
    final mine = widget.myPostId;
    if (mine != null) _mine = feed.watchPost(mine);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('challenge-vs-card'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _tile(_theirs, fallbackLabel: 'Them')),
            const SizedBox(width: 10),
            Expanded(child: _tile(_mine, fallbackLabel: 'You', isMine: true)),
          ],
        ),
      ],
    );
  }

  Widget _tile(Stream<FeedPost?>? stream,
      {required String fallbackLabel, bool isMine = false}) {
    if (stream == null) return _VsTile(post: null, label: fallbackLabel);
    return StreamBuilder<FeedPost?>(
      stream: stream,
      builder: (context, snapshot) => _VsTile(
        post: snapshot.data,
        label: isMine ? 'You' : _firstName(snapshot.data?.displayName),
        highlight: isMine,
      ),
    );
  }

  static String _firstName(String? name) {
    final first = (name ?? '').trim().split(RegExp(r'\s+')).first;
    return first.isEmpty ? 'Them' : first;
  }
}

class _VsTile extends StatelessWidget {
  final FeedPost? post;
  final String label;
  final bool highlight;

  const _VsTile({required this.post, required this.label, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    final p = post;
    final elapsed = p?.elapsedSeconds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: highlight ? AppTheme.goldBright : Colors.white24,
                width: highlight ? 2.5 : 1,
              ),
              borderRadius: BorderRadius.circular(16),
              color: const Color(0xFF0D0818),
            ),
            child: AspectRatio(
              aspectRatio: 4 / 5,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _media(p),
                  if (p?.displayStamp != null)
                    Positioned(
                      top: 8,
                      right: 6,
                      child: Transform.scale(
                        scale: 0.72,
                        alignment: Alignment.topRight,
                        child: StampSticker(p!.displayStamp!),
                      ),
                    ),
                  if (elapsed != null)
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '⏱ $elapsed s',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: highlight ? AppTheme.goldBright : Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _media(FeedPost? p) {
    if (p == null) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
        ),
      );
    }
    switch (p.mediaType) {
      case SubmissionMediaType.video:
        return ArenaVideo(
          url: p.playableVideoUrl,
          posterUrl: p.posterUrl,
          durationSeconds: p.videoDurationSeconds,
          timerSeconds: p.timerSeconds,
          clockOffsetSeconds: p.clockOffsetSeconds,
          isLate: p.isLate,
          burnedIn: p.isHouse,
        );
      case SubmissionMediaType.photo:
        final data = p.photoData;
        if (data != null && data.isNotEmpty) {
          try {
            return Image.memory(base64Decode(data), fit: BoxFit.cover);
          } catch (_) {
            // fall through to the text tile
          }
        }
        return _text(p.caption ?? '');
      default:
        return _text(p.text ?? p.caption ?? '');
    }
  }

  Widget _text(String text) => Container(
        padding: const EdgeInsets.all(12),
        alignment: Alignment.center,
        decoration: const BoxDecoration(gradient: AppTheme.heroGradient),
        child: Text(
          text,
          textAlign: TextAlign.center,
          maxLines: 8,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.3),
        ),
      );
}
