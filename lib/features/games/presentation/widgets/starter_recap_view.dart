import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/models/game.dart';
import '../../../../core/models/player_task_status.dart';
import '../../../../core/models/submission.dart';
import '../../../../core/models/task.dart';
import '../../../../core/services/sfx/game_sfx.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../arena/domain/crowd_score_policy.dart';
import '../../../arena/domain/models/feed_post.dart';
import '../../../arena/domain/repositories/feed_repository.dart';
import 'stamp_sticker.dart';

/// The game screen for a solo, crowd-judged game: the Starter Pack ("Your
/// First Ten") and the daily task. There is no crew and no judge, so instead
/// of [GameInProgressView] the player sees their own entries: a thumbnail per
/// task, its stamp, how the crowd graded it, and a running total.
///
/// Scores come from two places, on purpose:
///  - the TOTAL only counts points the [CrowdScoreApplier] has locked into
///    the game (`PlayerTaskStatus.score` on a `judged` status), so it matches
///    the scoreboard;
///  - each tile shows the LIVE crowd grade from the Arena post, so the player
///    sees movement before a score locks.
class StarterRecapView extends StatefulWidget {
  final Game game;
  final String currentUserId;

  /// The player's own Arena posts. Null resolves
  /// `FeedRepository.watchPostsByUser` from the service locator (when one is
  /// registered); tests inject a stream.
  final Stream<List<FeedPost>>? posts;

  /// Open task [index] to play it.
  final ValueChanged<int>? onPlayTask;
  final VoidCallback? onOpenArena;
  final VoidCallback? onChallengeFriends;

  /// Clock for "has this lone grade settled yet". Tests pin it.
  final DateTime Function() now;

  const StarterRecapView({
    super.key,
    required this.game,
    required this.currentUserId,
    this.posts,
    this.onPlayTask,
    this.onOpenArena,
    this.onChallengeFriends,
    this.now = DateTime.now,
  });

  /// Whether [game] gets this view instead of the regular in-progress one.
  /// The daily game is compared by its raw kind string: `Game.isDaily` is
  /// added by a separate change (WP-6).
  static bool appliesTo(Game game) =>
      game.isStarter || game.gameKind == 'daily';

  /// SharedPreferences key for "the all-done celebration already played".
  static String celebratedKey(String gameId) =>
      'starter_recap_celebrated_$gameId';

  @override
  State<StarterRecapView> createState() => _StarterRecapViewState();
}

/// Everything one tile needs, derived from the game and the player's posts.
@immutable
class RecapEntry {
  final int index;
  final Task task;
  final bool posted;
  final Submission? submission;
  final FeedPost? post;

  /// The score locked into the game, or null while the crowd is still out.
  final int? lockedScore;

  const RecapEntry({
    required this.index,
    required this.task,
    required this.posted,
    this.submission,
    this.post,
    this.lockedScore,
  });

  String? get stamp => post?.displayStamp ?? post?.stamp ?? submission?.stamp;

  int get gradeCount => post?.gradeCount ?? 0;

  /// Grades still needed before the score locks on its own.
  int get gradesToGo =>
      (CrowdScorePolicy.finalGrades - gradeCount).clamp(0, 99);

  /// Build the entries for [game], matching each submission to its Arena
  /// post by `feedPostId`, or by game and task id when the id is missing.
  static List<RecapEntry> build(
      Game game, String userId, List<FeedPost> posts) {
    final byId = {for (final p in posts) p.id: p};
    return [
      for (var i = 0; i < game.tasks.length; i++)
        _entry(game, i, userId, posts, byId),
    ];
  }

  static RecapEntry _entry(Game game, int i, String userId,
      List<FeedPost> posts, Map<String, FeedPost> byId) {
    final task = game.tasks[i];
    Submission? submission;
    for (final s in task.submissions) {
      if (s.userId == userId) submission = s;
    }
    FeedPost? post;
    final postId = submission?.feedPostId;
    if (postId != null) post = byId[postId];
    post ??= posts
        .where((p) => p.gameId == game.id && p.taskId == task.id)
        .firstOrNull;
    final status = task.playerStatuses[userId];
    final posted =
        submission != null || (status?.hasSubmitted ?? false) || post != null;
    return RecapEntry(
      index: i,
      task: task,
      posted: posted,
      submission: submission,
      post: post,
      lockedScore:
          status?.state == TaskPlayerState.judged ? status?.score ?? 0 : null,
    );
  }
}

class _StarterRecapViewState extends State<StarterRecapView>
    with SingleTickerProviderStateMixin {
  Stream<List<FeedPost>>? _posts;
  late final AnimationController _confetti;

  /// True for the one visit that shows the "you did all ten" banner.
  bool _celebrating = false;
  bool _celebrationChecked = false;

  @override
  void initState() {
    super.initState();
    _confetti = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2600));
    _posts = widget.posts ?? _resolvePosts();
    unawaited(_maybeCelebrate());
  }

  Stream<List<FeedPost>>? _resolvePosts() {
    if (widget.currentUserId.isEmpty || !sl.isRegistered<FeedRepository>()) {
      return null;
    }
    return sl<FeedRepository>().watchPostsByUser(widget.currentUserId);
  }

  @override
  void didUpdateWidget(StarterRecapView old) {
    super.didUpdateWidget(old);
    if (old.posts != widget.posts && widget.posts != null) {
      _posts = widget.posts;
    }
    // The tenth post can land while this screen is open.
    if (!_celebrationChecked) unawaited(_maybeCelebrate());
  }

  bool get _allPosted {
    final g = widget.game;
    if (g.tasks.isEmpty) return false;
    return g.tasks.every((t) =>
        t.submissions.any((s) => s.userId == widget.currentUserId) ||
        (t.playerStatuses[widget.currentUserId]?.hasSubmitted ?? false));
  }

  Future<void> _maybeCelebrate() async {
    if (!_allPosted) return;
    _celebrationChecked = true;
    final key = StarterRecapView.celebratedKey(widget.game.id);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(key) ?? false) return;
      await prefs.setBool(key, true);
    } catch (_) {
      // No storage (private window): celebrate anyway, it is harmless.
    }
    if (!mounted) return;
    setState(() => _celebrating = true);
    HapticFeedback.heavyImpact();
    if (sl.isRegistered<GameSfx>()) sl<GameSfx>().fanfare();
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (!reduceMotion) _confetti.forward(from: 0);
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FeedPost>>(
      stream: _posts,
      builder: (context, snapshot) {
        final entries = RecapEntry.build(widget.game, widget.currentUserId,
            snapshot.data ?? const []);
        return Stack(
          children: [
            _buildList(context, entries),
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _confetti,
                  builder: (context, _) => _confetti.isAnimating
                      ? CustomPaint(
                          key: const Key('recap-confetti'),
                          painter: ConfettiPainter(progress: _confetti.value),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildList(BuildContext context, List<RecapEntry> entries) {
    final postedCount = entries.where((e) => e.posted).length;
    final locked = entries.where((e) => e.lockedScore != null).toList();
    final total = locked.fold<int>(0, (a, e) => a + e.lockedScore!);
    final next = entries.where((e) => !e.posted).firstOrNull;
    final isStarter = widget.game.isStarter;

    return ListView(
      key: const Key('starter-recap'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        if (_celebrating) ...[
          _CelebrationBanner(
            taskCount: entries.length,
            allLocked: locked.length == entries.length,
          ),
          const SizedBox(height: 14),
        ],
        _RecapHeader(
          title: isStarter ? 'Your First Ten' : widget.game.gameName,
          posted: postedCount,
          taskCount: entries.length,
          lockedCount: locked.length,
          total: total,
          nextIndex: next?.index,
          onPlayNext: next == null || widget.onPlayTask == null
              ? null
              : () => widget.onPlayTask!(next.index),
        ),
        const SizedBox(height: 20),
        LayoutBuilder(builder: (context, c) {
          const gap = 12.0;
          final tileWidth = (c.maxWidth - gap) / 2;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final e in entries)
                SizedBox(
                  width: tileWidth,
                  child: _RecapTile(
                    key: Key('recap-tile-${e.index}'),
                    entry: e,
                    now: widget.now(),
                    onStart: widget.onPlayTask == null
                        ? null
                        : () => widget.onPlayTask!(e.index),
                  ),
                ),
            ],
          );
        }),
        const SizedBox(height: 24),
        if (widget.onOpenArena != null)
          _footerButton(
            key: const Key('recap-arena'),
            filled: next == null,
            icon: Icons.theater_comedy_rounded,
            label: 'Arena — grade more to get graded faster',
            onPressed: widget.onOpenArena!,
          ),
        if (widget.onChallengeFriends != null) ...[
          const SizedBox(height: 10),
          _footerButton(
            key: const Key('recap-challenge'),
            filled: false,
            icon: Icons.group_add_rounded,
            label: 'Challenge friends',
            onPressed: widget.onChallengeFriends!,
          ),
        ],
      ],
    );
  }

  Widget _footerButton({
    required Key key,
    required bool filled,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Flexible(child: Text(label, textAlign: TextAlign.center)),
      ],
    );
    const padding = EdgeInsets.symmetric(vertical: 14, horizontal: 12);
    return SizedBox(
      width: double.infinity,
      child: filled
          ? FilledButton(
              key: key,
              onPressed: onPressed,
              style: FilledButton.styleFrom(padding: padding),
              child: child)
          : OutlinedButton(
              key: key,
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(padding: padding),
              child: child),
    );
  }
}

/// Hero: progress ring, the total, and (while tasks remain) the next one.
class _RecapHeader extends StatelessWidget {
  final String title;
  final int posted;
  final int taskCount;
  final int lockedCount;
  final int total;
  final int? nextIndex;
  final VoidCallback? onPlayNext;

  const _RecapHeader({
    required this.title,
    required this.posted,
    required this.taskCount,
    required this.lockedCount,
    required this.total,
    this.nextIndex,
    this.onPlayNext,
  });

  String get _caption {
    if (posted == 0) return 'Nothing posted yet. The crowd is bored.';
    if (lockedCount == taskCount) return 'Final. The crowd has spoken.';
    if (lockedCount == 0) return 'so far. The crowd is still grading.';
    return 'so far · $lockedCount of $taskCount graded';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: tokens.heroGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: theme.brightness == Brightness.light
            ? [
                BoxShadow(
                  color: theme.colorScheme.primary.withOpacity(0.18),
                  blurRadius: 24,
                  spreadRadius: -6,
                  offset: const Offset(0, 12),
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title.toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(
                color: tokens.onHero,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.3,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _ProgressRing(done: posted, of: taskCount),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TweenAnimationBuilder<double>(
                        tween: Tween(end: total.toDouble()),
                        duration: const Duration(milliseconds: 900),
                        curve: Curves.easeOutCubic,
                        builder: (context, v, _) => FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${v.round()} pts',
                            key: const Key('recap-total'),
                            style: theme.textTheme.displaySmall?.copyWith(
                              color: tokens.onHero,
                              fontFamily: 'Fredoka',
                              fontWeight: FontWeight.w700,
                              height: 1.0,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _caption,
                        key: const Key('recap-caption'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: tokens.onHeroMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (nextIndex != null && onPlayNext != null) ...[
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('recap-next'),
                  onPressed: onPlayNext,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppTheme.violetDeep,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  child: Text('Start task ${nextIndex! + 1}'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProgressRing extends StatelessWidget {
  final int done;
  final int of;

  const _ProgressRing({required this.done, required this.of});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final fraction = of == 0 ? 0.0 : done / of;
    return SizedBox(
      width: 84,
      height: 84,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: fraction),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => Stack(
          fit: StackFit.expand,
          children: [
            CircularProgressIndicator(
              value: v,
              strokeWidth: 8,
              strokeCap: StrokeCap.round,
              backgroundColor: Colors.white.withOpacity(0.2),
              valueColor: const AlwaysStoppedAnimation(AppTheme.goldBright),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$done/$of',
                    key: const Key('recap-progress'),
                    style: TextStyle(
                      fontFamily: 'Fredoka',
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: tokens.onHero,
                      height: 1.0,
                    ),
                  ),
                  Text(
                    'posted',
                    style: TextStyle(fontSize: 11, color: tokens.onHeroMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One task: the entry's thumbnail with its stamp, the title, and the grade.
class _RecapTile extends StatelessWidget {
  final RecapEntry entry;
  final DateTime now;
  final VoidCallback? onStart;

  const _RecapTile({
    super.key,
    required this.entry,
    required this.now,
    this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final posted = entry.posted;

    final card = Container(
      decoration: BoxDecoration(
        color: posted
            ? theme.cardTheme.color ?? scheme.surface
            : scheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(18),
        border: posted
            ? null
            : Border.all(color: scheme.outlineVariant.withOpacity(0.6)),
        boxShadow: posted && theme.brightness == Brightness.light
            ? [
                BoxShadow(
                  color: scheme.primary.withOpacity(0.08),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 1.15,
            child: Stack(
              fit: StackFit.expand,
              children: [
                posted
                    ? _Thumbnail(entry: entry)
                    : _UntouchedThumb(index: entry.index),
                Positioned(
                  left: 8,
                  top: 8,
                  child: _NumberBadge(n: entry.index + 1, active: posted),
                ),
                if (posted && entry.stamp != null)
                  Positioned(
                    right: 6,
                    bottom: 8,
                    child: StampSticker(stamp: entry.stamp!, scale: 0.55),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  // Two lines, always, so the grid rows line up.
                  height: 36,
                  child: Text(
                    entry.task.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                      color: posted ? null : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                posted
                    ? _GradeLine(entry: entry)
                    : SizedBox(
                        height: 28,
                        child: TextButton(
                          key: Key('recap-start-${entry.index}'),
                          onPressed: onStart,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            minimumSize: const Size(0, 28),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.play_arrow_rounded, size: 18),
                              SizedBox(width: 2),
                              Text('Start'),
                            ],
                          ),
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );

    return posted ? card : Opacity(opacity: 0.75, child: card);
  }
}

class _GradeLine extends StatelessWidget {
  final RecapEntry entry;

  const _GradeLine({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final muted = theme.colorScheme.onSurfaceVariant;
    final mean = entry.post?.meanGrade;
    final count = entry.gradeCount;
    final locked = entry.lockedScore;

    final String text;
    if (mean != null) {
      text = '★ ${mean.toStringAsFixed(1)} · $count '
          '${count == 1 ? 'grade' : 'grades'}';
    } else if (entry.post == null && locked == null) {
      text = 'With the crowd';
    } else {
      final n = entry.gradesToGo;
      text = '$n more ${n == 1 ? 'grade' : 'grades'} to go';
    }

    return SizedBox(
      height: 28,
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              key: Key('recap-grade-${entry.index}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: mean != null ? tokens.goldText : muted,
                fontWeight: mean != null ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          if (locked != null)
            Container(
              key: Key('recap-locked-${entry.index}'),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$locked pts',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NumberBadge extends StatelessWidget {
  final int n;
  final bool active;

  const _NumberBadge({required this.n, required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? Colors.black.withOpacity(0.55) : Colors.black12,
        shape: BoxShape.circle,
      ),
      child: Text(
        '$n',
        style: TextStyle(
          color: active ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// The player's entry: photo bytes, the video's poster frame, or the text
/// on the brand gradient. Falls back to a media icon on the gradient.
class _Thumbnail extends StatelessWidget {
  final RecapEntry entry;

  const _Thumbnail({required this.entry});

  @override
  Widget build(BuildContext context) {
    final post = entry.post;
    final mediaType = post?.mediaType ?? entry.submission?.mediaType;

    if (post?.photoData != null && post!.photoData!.isNotEmpty) {
      try {
        return Image.memory(
          base64Decode(post.photoData!),
          key: Key('recap-photo-${entry.index}'),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _fallback(context, mediaType),
        );
      } catch (_) {
        return _fallback(context, mediaType);
      }
    }
    if (post?.posterUrl != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            post!.posterUrl!,
            key: Key('recap-poster-${entry.index}'),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _fallback(context, mediaType),
          ),
          const Center(
            child: Icon(Icons.play_circle_fill_rounded,
                color: Colors.white70, size: 36),
          ),
        ],
      );
    }
    final text = post?.text ?? entry.submission?.text;
    if (text != null && text.trim().isNotEmpty) {
      return _GradientBox(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 34, 14, 14),
          child: Text(
            '“${text.trim()}”',
            key: Key('recap-text-${entry.index}'),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.tokens.onHero,
              fontFamily: 'Fredoka',
              fontSize: 15,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ),
      );
    }
    return _fallback(context, mediaType);
  }

  Widget _fallback(BuildContext context, SubmissionMediaType? type) {
    final icon = switch (type) {
      SubmissionMediaType.video => Icons.videocam_rounded,
      SubmissionMediaType.photo => Icons.photo_camera_rounded,
      SubmissionMediaType.text => Icons.short_text_rounded,
      _ => Icons.link_rounded,
    };
    return _GradientBox(
      child: Center(
        child: Icon(icon, size: 34, color: context.tokens.onHeroMuted),
      ),
    );
  }
}

class _GradientBox extends StatelessWidget {
  final Widget child;

  const _GradientBox({required this.child});

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(gradient: context.tokens.heroGradient),
        child: child,
      );
}

class _UntouchedThumb extends StatelessWidget {
  final int index;

  const _UntouchedThumb({required this.index});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.onSurface.withOpacity(0.05),
      child: Center(
        child: Icon(Icons.hourglass_empty_rounded,
            size: 30, color: scheme.onSurfaceVariant.withOpacity(0.6)),
      ),
    );
  }
}

/// Shown once, on the first visit after the last task is posted.
class _CelebrationBanner extends StatelessWidget {
  final int taskCount;
  final bool allLocked;

  const _CelebrationBanner({required this.taskCount, required this.allLocked});

  static const _words = {
    1: 'one',
    5: 'five',
    10: 'ten',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final n = _words[taskCount] ?? '$taskCount';
    final line = taskCount == 1
        ? 'You did it. The crowd is still grading.'
        : 'You did all $n. The crowd is still grading.';
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.6, end: 1),
      duration: const Duration(milliseconds: 650),
      curve: Curves.elasticOut,
      builder: (context, s, child) => Transform.scale(scale: s, child: child),
      child: Container(
        key: const Key('recap-celebration'),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        decoration: BoxDecoration(
          color: tokens.gold.withOpacity(0.16),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: tokens.gold, width: 1.5),
        ),
        child: Row(
          children: [
            const StampSticker(stamp: 'ALL DONE!', scale: 0.8),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                allLocked ? 'You did all $n. The crowd has spoken.' : line,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: tokens.goldText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A one-shot confetti burst from the top centre: ~90 paper bits that fan
/// out, fall with gravity, flutter and fade. Deterministic (seeded) so
/// goldens are stable.
class ConfettiPainter extends CustomPainter {
  final double progress;

  ConfettiPainter({required this.progress});

  static const _colors = [
    AppTheme.goldBright,
    AppTheme.coral,
    AppTheme.violet,
    Color(0xFF16A34A),
    Color(0xFF0EA5E9),
    Colors.white,
  ];

  static final List<_Bit> _bits = () {
    final r = math.Random(10);
    return List.generate(90, (i) {
      final angle = -math.pi / 2 + (r.nextDouble() - 0.5) * math.pi * 1.1;
      return _Bit(
        angle: angle,
        speed: 0.55 + r.nextDouble() * 0.75,
        spin: (r.nextDouble() - 0.5) * 18,
        wobble: r.nextDouble() * math.pi * 2,
        size: 5 + r.nextDouble() * 6,
        color: _colors[i % _colors.length],
        delay: r.nextDouble() * 0.12,
        round: i % 4 == 0,
      );
    });
  }();

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final origin = Offset(size.width / 2, size.height * 0.12);
    final reach = size.shortestSide * 0.9;
    final paint = Paint();
    for (final b in _bits) {
      final t = ((progress - b.delay) / (1 - b.delay)).clamp(0.0, 1.0);
      if (t <= 0) continue;
      // Burst outward, then gravity takes over.
      final dx = math.cos(b.angle) * b.speed * reach * t +
          math.sin(b.wobble + t * 10) * 8;
      final dy = math.sin(b.angle) * b.speed * reach * t +
          size.height * 0.9 * t * t;
      final opacity = t < 0.75 ? 1.0 : (1 - (t - 0.75) / 0.25);
      paint.color = b.color.withOpacity(opacity.clamp(0.0, 1.0));
      canvas.save();
      canvas.translate(origin.dx + dx, origin.dy + dy);
      canvas.rotate(b.spin * t);
      if (b.round) {
        canvas.drawCircle(Offset.zero, b.size / 2.4, paint);
      } else {
        // Flutter: the strip's visible height breathes as it turns.
        final h = b.size * (0.35 + 0.65 * math.cos(b.wobble + t * 14).abs());
        canvas.drawRect(
            Rect.fromCenter(center: Offset.zero, width: b.size, height: h),
            paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _Bit {
  final double angle;
  final double speed;
  final double spin;
  final double wobble;
  final double size;
  final Color color;
  final double delay;
  final bool round;

  const _Bit({
    required this.angle,
    required this.speed,
    required this.spin,
    required this.wobble,
    required this.size,
    required this.color,
    required this.delay,
    required this.round,
  });
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
