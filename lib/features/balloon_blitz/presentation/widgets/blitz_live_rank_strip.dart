import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/blitz_session.dart';

/// Always-visible ranked strip shown DURING live play: top 3 + "you" if you're
/// outside the top 3. Thin, translucent, edge-hugging — it never obstructs the
/// AR camera view underneath. Rank swaps and score bumps animate so overtakes
/// feel like overtakes; getting overtaken triggers a subtle flash + haptic on
/// your own chip so you feel it without having to read the numbers.
class BlitzLiveRankStrip extends StatefulWidget {
  final BlitzSession session;

  /// This device's player id, highlighted (and tracked for overtakes).
  final String selfId;

  const BlitzLiveRankStrip({
    super.key,
    required this.session,
    required this.selfId,
  });

  @override
  State<BlitzLiveRankStrip> createState() => _BlitzLiveRankStripState();
}

class _BlitzLiveRankStripState extends State<BlitzLiveRankStrip> {
  int? _lastSelfRank;
  int _selfFlashTrigger = 0;

  @override
  void initState() {
    super.initState();
    _lastSelfRank = _selfRankOf(widget.session);
  }

  @override
  void didUpdateWidget(covariant BlitzLiveRankStrip old) {
    super.didUpdateWidget(old);
    final rank = _selfRankOf(widget.session);
    // A HIGHER rank number is a WORSE position — that's an overtake.
    if (_lastSelfRank != null && rank != null && rank > _lastSelfRank!) {
      HapticFeedback.selectionClick();
      setState(() => _selfFlashTrigger++);
    }
    _lastSelfRank = rank;
  }

  int? _selfRankOf(BlitzSession session) {
    final ranked = session.leaderboard;
    for (var i = 0; i < ranked.length; i++) {
      if (ranked[i].id == widget.selfId) return i + 1;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // Keep the tracked rank current for the NEXT comparison even when this
    // build wasn't triggered by didUpdateWidget (e.g. first frame).
    _lastSelfRank ??= _selfRankOf(widget.session);

    final ranked = widget.session.leaderboard;
    final top = ranked.take(3).toList();
    final selfRank = _selfRankOf(widget.session);
    final selfOutsideTop3 = selfRank != null && selfRank > 3;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < top.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              _RankChip(
                key: ValueKey('blitz-strip-slot-$i'),
                rank: i + 1,
                player: top[i],
                isSelf: top[i].id == widget.selfId,
                flash: top[i].id == widget.selfId ? _selfFlashTrigger : 0,
              ),
            ],
            if (selfOutsideTop3) ...[
              const SizedBox(width: 8),
              Container(width: 1, height: 18, color: Colors.white24),
              const SizedBox(width: 8),
              _RankChip(
                key: const ValueKey('blitz-strip-self'),
                rank: selfRank!,
                player: ranked[selfRank - 1],
                isSelf: true,
                flash: _selfFlashTrigger,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RankChip extends StatefulWidget {
  final int rank;
  final BlitzPlayer player;
  final bool isSelf;

  /// Increments each time this chip's occupant just got overtaken; only
  /// meaningful when [isSelf] is true.
  final int flash;

  const _RankChip({
    super.key,
    required this.rank,
    required this.player,
    required this.isSelf,
    this.flash = 0,
  });

  @override
  State<_RankChip> createState() => _RankChipState();
}

class _RankChipState extends State<_RankChip>
    with TickerProviderStateMixin {
  late final AnimationController _punch;
  late final AnimationController _flashC;

  @override
  void initState() {
    super.initState();
    _punch = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 220));
    _flashC = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 420));
  }

  @override
  void didUpdateWidget(covariant _RankChip old) {
    super.didUpdateWidget(old);
    if (widget.player.liveScore != old.player.liveScore) {
      _punch.forward(from: 0);
    }
    if (widget.isSelf && widget.flash != old.flash && widget.flash > 0) {
      _flashC.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _punch.dispose();
    _flashC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final medal = switch (widget.rank) {
      1 => '🥇',
      2 => '🥈',
      3 => '🥉',
      _ => '${widget.rank}',
    };

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.4),
            end: Offset.zero,
          ).animate(anim),
          child: child,
        ),
      ),
      child: AnimatedBuilder(
        key: ValueKey('${widget.player.id}-${widget.rank}'),
        animation: Listenable.merge([_punch, _flashC]),
        builder: (context, child) {
          final scale = 1 + 0.16 * sin(_punch.value * pi);
          final flashPulse = sin(_flashC.value * pi).clamp(0.0, 1.0);
          final baseColor = widget.isSelf
              ? AppTheme.gold.withOpacity(0.28)
              : Colors.white.withOpacity(0.06);
          final bg = Color.lerp(
              baseColor, AppTheme.coral.withOpacity(0.8), flashPulse)!;
          return Transform.scale(
            scale: scale,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 108),
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(medal, style: const TextStyle(fontSize: 12)),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      widget.player.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight:
                            widget.isSelf ? FontWeight.w800 : FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${widget.player.liveScore}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
