import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/blitz_session.dart';

/// The 1st/2nd/3rd podium moment at the top of the Balloon Blitz results
/// screen. Purely presentational — driven by an external [reveal] animation
/// (0..1) so the ceremony's overall timing/lifecycle stays owned by the
/// caller. Gracefully omits empty stands for 1- or 2-player races.
class BlitzPodium extends StatelessWidget {
  /// Full ranking (highest score first) — only the top 3 are shown as stands.
  final List<BlitzPlayer> ranked;

  final String selfId;

  /// 0..1 across the whole podium moment; internally staggered per stand.
  final Animation<double> reveal;

  const BlitzPodium({
    super.key,
    required this.ranked,
    required this.selfId,
    required this.reveal,
  });

  static const _silver = Color(0xFFC7CCD6);
  static const _bronze = Color(0xFFCC8A5C);

  @override
  Widget build(BuildContext context) {
    final first = ranked.isNotEmpty ? ranked[0] : null;
    final second = ranked.length > 1 ? ranked[1] : null;
    final third = ranked.length > 2 ? ranked[2] : null;

    // Staggered: 3rd rises first to build a little suspense, then 2nd, then
    // 1st lands last with an elastic bounce — the actual "moment".
    final thirdIn = CurvedAnimation(
      parent: reveal,
      curve: const Interval(0.0, 0.55, curve: Curves.easeOutCubic),
    );
    final secondIn = CurvedAnimation(
      parent: reveal,
      curve: const Interval(0.18, 0.75, curve: Curves.easeOutCubic),
    );
    final firstIn = CurvedAnimation(
      parent: reveal,
      curve: const Interval(0.4, 1.0, curve: Curves.elasticOut),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (second != null)
          Expanded(
            child: _Stand(
              key: const ValueKey('podium-stand-2'),
              player: second,
              rank: 2,
              blockHeight: 62,
              avatarRadius: 18,
              blockColor: _silver,
              isSelf: second.id == selfId,
              reveal: secondIn,
            ),
          ),
        if (first != null)
          Expanded(
            child: _Stand(
              key: const ValueKey('podium-stand-1'),
              player: first,
              rank: 1,
              blockHeight: 88,
              avatarRadius: 22,
              blockColor: AppTheme.gold,
              isSelf: first.id == selfId,
              reveal: firstIn,
              crownWinner: true,
            ),
          ),
        if (third != null)
          Expanded(
            child: _Stand(
              key: const ValueKey('podium-stand-3'),
              player: third,
              rank: 3,
              blockHeight: 48,
              avatarRadius: 18,
              blockColor: _bronze,
              isSelf: third.id == selfId,
              reveal: thirdIn,
            ),
          ),
      ],
    );
  }
}

class _Stand extends StatelessWidget {
  final BlitzPlayer player;
  final int rank;
  final double blockHeight;
  final double avatarRadius;
  final Color blockColor;
  final bool isSelf;
  final Animation<double> reveal;
  final bool crownWinner;

  const _Stand({
    super.key,
    required this.player,
    required this.rank,
    required this.blockHeight,
    required this.avatarRadius,
    required this.blockColor,
    required this.isSelf,
    required this.reveal,
    this.crownWinner = false,
  });

  @override
  Widget build(BuildContext context) {
    final medal = switch (rank) {
      1 => '🥇',
      2 => '🥈',
      _ => '🥉',
    };
    return AnimatedBuilder(
      animation: reveal,
      builder: (context, child) {
        final t = reveal.value.clamp(0.0, 1.0);
        return Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, (1 - t) * 36), child: child),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (crownWinner) const Text('👑', style: TextStyle(fontSize: 20)),
            CircleAvatar(
              radius: avatarRadius,
              backgroundColor: isSelf ? AppTheme.violet : AppTheme.violetSoft,
              child: Text(
                player.name.isNotEmpty ? player.name[0].toUpperCase() : '?',
                style: TextStyle(
                  color: isSelf ? Colors.white : AppTheme.violetDeep,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              player.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: isSelf ? FontWeight.w800 : FontWeight.w600,
                fontSize: 13,
              ),
            ),
            Text(
              '${player.liveScore}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
            const SizedBox(height: 6),
            Container(
              key: ValueKey('podium-block-$rank'),
              height: blockHeight,
              decoration: BoxDecoration(
                color: blockColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
              ),
              alignment: Alignment.topCenter,
              padding: const EdgeInsets.only(top: 6),
              child: Text(medal, style: const TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}
