import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/models/game.dart';
import '../../../../core/models/submission.dart';
import '../../../../core/services/sfx/game_sfx.dart';
import '../../../../core/services/share/share_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/ar_fx.dart' show ConfettiBurst;
import '../../../arena/domain/models/feed_post.dart';
import '../../../arena/domain/repositories/feed_repository.dart';
import '../../../arena/presentation/screens/arena_screen.dart';
import '../../../arena/presentation/widgets/challenge_vs_card.dart';
import '../../../arena/presentation/widgets/share_attempt_button.dart';
import '../../domain/house_reactions.dart';
import '../../domain/repositories/game_repository.dart';
import '../widgets/late_badge.dart';
import '../widgets/push_opt_in_card.dart';
import '../widgets/stamp_sticker.dart';
import 'game_detail_screen.dart';
import 'task_execution_screen.dart';

/// The reveal moment (tap after Snap it / Write it → Post it). Replaces the
/// task screen (`Navigator.pushReplacement`) so the back button returns to
/// Home, not to the just-submitted task.
///
/// Fun audit WP-5: this is the emotional peak ("look what I made"), so it
/// shows the player's own entry as a tilted polaroid, slams the auto-stamp
/// onto it, lets Greg's assistant react in one line ([HouseReactions]), shows
/// Starter Pack progress, and leads with "See theirs (N waiting)". Share is
/// still here (WP-09 share pages keep working) but no longer the primary
/// action. The tenth starter post routes to the game screen (the First Ten
/// recap) with a confetti burst.
class PostedScreen extends StatefulWidget {
  final String gameId;
  final int taskIndex;
  final String taskTitle;

  /// The Arena post this attempt created, when it was shared — drives the
  /// polaroid, the stamp and the reaction via `FeedRepository.watchPost`.
  /// Null when nothing was shared (e.g. shareToArena was off), in which case
  /// those are skipped.
  final String? feedPostId;

  final bool isLate;

  /// WP-09: the post this attempt answered (the share link's "Your turn").
  /// When set, the challenger's entry and this one are shown side by side —
  /// the payoff — and the challenge is attributed (share_attributions).
  final String? challengeFromPostId;

  /// The task's id and the poster's uid, for the attribution record, the
  /// "N waiting" count and the progress strip.
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

  /// Wait after the screen appears before the stamp slams down.
  static const Duration slamDelay = Duration(milliseconds: 300);

  /// The slam itself, drop to settle.
  static const Duration slamDuration = Duration(milliseconds: 520);

  @override
  State<PostedScreen> createState() => _PostedScreenState();
}

class _PostedScreenState extends State<PostedScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slam;
  StreamSubscription<FeedPost?>? _postSub;
  StreamSubscription<List<FeedPost>>? _queueSub;
  Timer? _delay;

  FeedPost? _post;
  Game? _game;
  bool _gameLoaded = false;
  int? _waiting;

  bool _delayDone = false;
  bool _slamStarted = false;
  bool _impactDone = false;
  bool _reduceMotion = false;
  bool _finaleCelebrated = false;
  bool _showConfetti = false;

  @override
  void initState() {
    super.initState();
    _slam = AnimationController(vsync: this, duration: PostedScreen.slamDuration)
      ..addListener(_onSlamTick);
    _delay = Timer(PostedScreen.slamDelay, () {
      _delayDone = true;
      _maybeSlam();
    });

    sl<GameRepository>().getGameStream(widget.gameId).first.then(
      (game) {
        if (!mounted) return;
        setState(() {
          _game = game;
          _gameLoaded = true;
        });
        _maybeCelebrate();
      },
      onError: (_) {
        if (mounted) setState(() => _gameLoaded = true);
      },
    );

    final postId = widget.feedPostId;
    if (postId != null) {
      _postSub = sl<FeedRepository>().watchPost(postId).listen((post) {
        if (!mounted) return;
        setState(() => _post = post ?? _post);
        _maybeWatchQueue();
        _maybeSlam();
      }, onError: (_) {});
    }
    _maybeWatchQueue();
    _recordChallenge();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  }

  @override
  void dispose() {
    _delay?.cancel();
    _postSub?.cancel();
    _queueSub?.cancel();
    _slam.dispose();
    super.dispose();
  }

  ShareService get _share => widget.shareService ?? ShareService.fromLocator();

  GameSfx get _sfx =>
      sl.isRegistered<GameSfx>() ? sl<GameSfx>() : const SilentGameSfx();

  String? get _viewerId {
    final uid = widget.userId;
    if (uid != null && uid.isNotEmpty) return uid;
    return _post?.userId;
  }

  String? get _taskId {
    final id = widget.taskId;
    if (id != null && id.isNotEmpty) return id;
    return _post?.taskId;
  }

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

  /// "See theirs (N waiting)": the viewer's ungraded queue, narrowed to this
  /// task. House entries count — they are something to watch and grade.
  void _maybeWatchQueue() {
    if (_queueSub != null) return;
    final uid = _viewerId;
    final taskId = _taskId;
    if (uid == null || uid.isEmpty || taskId == null || taskId.isEmpty) {
      return;
    }
    _queueSub = sl<FeedRepository>()
        .watchQueue(viewerId: uid, unlockedTaskIds: {taskId})
        .listen((posts) {
      if (!mounted) return;
      final n =
          posts.where((p) => p.taskId == taskId && p.userId != uid).length;
      setState(() => _waiting = n);
    }, onError: (_) {});
  }

  // --- The stamp slam -------------------------------------------------------

  void _maybeSlam() {
    if (_slamStarted || _post?.stamp == null) return;
    if (!_delayDone && !_reduceMotion) return;
    _slamStarted = true;
    if (_reduceMotion) {
      _slam.value = 1;
      _impact();
    } else {
      _slam.forward();
    }
  }

  void _onSlamTick() {
    // The stamp first touches the polaroid a little past halfway through
    // the drop (the curve overshoots below 1.0 there): that is the thunk.
    if (!_impactDone && _slam.value >= 0.42) _impact();
  }

  void _impact() {
    if (_impactDone) return;
    _impactDone = true;
    HapticFeedback.heavyImpact();
    // A low, short "thunk": the pop sample pitched down. (`boom` is an
    // explosion at full volume, and GameSfx has no volume control yet.)
    _sfx.pop(pitch: 0.6);
  }

  // --- Starter progress -----------------------------------------------------

  bool get _isStarter => _game?.isStarter ?? false;

  /// Indexes of the starter tasks this player has posted, always including
  /// the one just posted (the game snapshot may predate the write).
  Set<int> get _postedIndexes {
    final game = _game;
    if (game == null) return {widget.taskIndex};
    final uid = _viewerId ?? game.creatorId;
    final done = <int>{widget.taskIndex};
    for (var i = 0; i < game.tasks.length; i++) {
      if (game.tasks[i].submissions.any((s) => s.userId == uid)) done.add(i);
    }
    return done;
  }

  bool get _allStarterDone {
    final game = _game;
    if (game == null || !game.isStarter || game.tasks.isEmpty) return false;
    return _postedIndexes.length >= game.tasks.length;
  }

  /// The task "Next task" opens: the next one in order for a normal game; for
  /// the starter, the first one not yet posted after this one (wrapping), so
  /// a skipped task is not lost.
  int? get _nextIndex {
    final game = _game;
    if (game == null) return null;
    final n = game.tasks.length;
    if (!game.isStarter) {
      final next = widget.taskIndex + 1;
      return next < n ? next : null;
    }
    final done = _postedIndexes;
    for (var step = 1; step < n; step++) {
      final i = (widget.taskIndex + step) % n;
      if (!done.contains(i)) return i;
    }
    return null;
  }

  void _maybeCelebrate() {
    if (_finaleCelebrated || !_allStarterDone) return;
    _finaleCelebrated = true;
    _sfx.fanfare();
    if (!_reduceMotion) setState(() => _showConfetti = true);
  }

  // --- Navigation -----------------------------------------------------------

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

  /// The tenth starter post: the game screen is the First Ten recap (WP-2).
  void _openFirstTen() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => GameDetailScreen(gameId: widget.gameId)),
    );
  }

  void _backHome() => Navigator.of(context).pop();

  // --- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final hasPolaroid =
        widget.feedPostId != null && widget.challengeFromPostId == null;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppTheme.violetDeep,
      body: Container(
        // Fill the whole body so the gradient covers the screen instead of
        // stopping at the content's height.
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(gradient: AppTheme.heroGradient),
        child: Stack(
          children: [
            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Posted.',
                      textAlign: TextAlign.center,
                      style: textTheme.headlineMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (widget.challengeFromPostId != null) ...[
                      Text(
                        'You vs. them',
                        textAlign: TextAlign.center,
                        style: textTheme.titleMedium?.copyWith(
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
                    ] else if (hasPolaroid)
                      _polaroidSection(),
                    if (widget.isLate) ...[
                      const SizedBox(height: 12),
                      const Center(child: LateBadge()),
                    ],
                    if (widget.feedPostId != null) ...[
                      const SizedBox(height: 20),
                      _reaction(),
                    ],
                    if (_isStarter) ...[
                      const SizedBox(height: 18),
                      _progressStrip(),
                    ],
                    const SizedBox(height: 20),
                    Text(
                      hasPolaroid
                          ? 'You\'ve unlocked everyone else\'s attempt.'
                          : 'You\'ve unlocked everyone else\'s attempt at: '
                              '${widget.taskTitle}',
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withOpacity(0.85),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _seeTheirsButton(),
                    const SizedBox(height: 12),
                    _nextButton(),
                    if (widget.feedPostId != null) ...[
                      const SizedBox(height: 12),
                      Center(
                        child: ShareAttemptButton(
                          post: _post,
                          onDark: true,
                          label: widget.challengeFromPostId != null
                              ? 'Send it back'
                              : 'Share it',
                          shareService: widget.shareService,
                        ),
                      ),
                    ],
                    // Web push opt-in, asked here and nowhere else: the
                    // browser gives exactly one chance to prompt, and this is
                    // the first moment the player has a reason to want the
                    // answer. Renders nothing on mobile or when answered.
                    if (widget.feedPostId != null) const PushOptInCard(),
                  ],
                ),
              ),
            ),
            if (_showConfetti)
              const Positioned.fill(
                child: ConfettiBurst(key: Key('posted-confetti')),
              ),
          ],
        ),
      ),
    );
  }

  Widget _polaroidSection() {
    return LayoutBuilder(builder: (context, constraints) {
      final screenH = MediaQuery.sizeOf(context).height;
      // 60 % of the width, but never so tall on a short phone that the
      // buttons fall off the first screen.
      final width = math.min(constraints.maxWidth * 0.6, screenH * 0.34);
      final stamp = _post?.stamp;
      return Center(
        child: AnimatedBuilder(
          animation: _slam,
          builder: (context, child) {
            // The polaroid flinches as the stamp lands.
            final t = _slam.value;
            final jolt = (t > 0.42 && t < 0.8)
                ? 1 - 0.035 * math.sin((t - 0.42) / 0.38 * math.pi)
                : 1.0;
            return Transform.scale(scale: jolt, child: child);
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              _Polaroid(
                key: const Key('posted-polaroid'),
                width: width,
                post: _post,
                title: widget.taskTitle,
              ),
              if (stamp != null)
                Positioned(
                  top: -14,
                  right: -22,
                  child: _SlammedStamp(animation: _slam, stamp: stamp),
                ),
            ],
          ),
        ),
      );
    });
  }

  Widget _reaction() {
    final post = _post;
    if (post == null) return const SizedBox(height: 44);
    final line = HouseReactions.pick(
      postId: post.id.isNotEmpty ? post.id : (widget.feedPostId ?? ''),
      stamp: post.stamp,
      taskId: post.taskId.isNotEmpty ? post.taskId : widget.taskId,
    );
    final content = Container(
      key: const Key('house-reaction'),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Text.rich(
        TextSpan(children: [
          const TextSpan(
            text: '${HouseReactions.speaker}: ',
            style: TextStyle(
              color: AppTheme.goldBright,
              fontWeight: FontWeight.w800,
            ),
          ),
          TextSpan(text: line),
        ]),
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          height: 1.35,
        ),
      ),
    );
    if (post.stamp == null) return content;
    // The line lands just after the stamp does.
    final fade = CurvedAnimation(
      parent: _slam,
      curve: const Interval(0.55, 1.0, curve: Curves.easeOut),
    );
    return FadeTransition(
      opacity: fade,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.25), end: Offset.zero)
            .animate(fade),
        child: content,
      ),
    );
  }

  Widget _progressStrip() {
    final game = _game!;
    final total = game.tasks.length;
    final done = _postedIndexes;
    return Column(
      key: const Key('starter-progress'),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < total; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3.5),
                child: i == widget.taskIndex
                    ? TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: _reduceMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 900),
                        curve: const Interval(0.35, 1,
                            curve: Curves.elasticOut),
                        builder: (context, v, _) => Transform.scale(
                          scale: 0.4 + 0.6 * v,
                          child: _dot(filled: true, fresh: true),
                        ),
                      )
                    : _dot(filled: done.contains(i)),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '${done.length} of $total',
          style: TextStyle(
            color: Colors.white.withOpacity(0.85),
            fontWeight: FontWeight.w700,
            fontSize: 13,
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }

  Widget _dot({required bool filled, bool fresh = false}) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled
            ? (fresh ? AppTheme.goldBright : Colors.white)
            : Colors.transparent,
        border: Border.all(
          color: filled ? Colors.transparent : Colors.white54,
          width: 1.5,
        ),
        boxShadow: fresh
            ? [
                BoxShadow(
                  color: AppTheme.goldBright.withOpacity(0.6),
                  blurRadius: 8,
                ),
              ]
            : null,
      ),
    );
  }

  Widget _seeTheirsButton() {
    final n = _waiting ?? 0;
    return SizedBox(
      height: 56,
      child: FilledButton(
        key: const Key('see-theirs-button'),
        onPressed: _openArena,
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.coral,
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: Text(
          n > 0 ? 'See theirs ($n waiting)' : 'See theirs',
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _nextButton() {
    final String label;
    final VoidCallback? onPressed;
    if (!_gameLoaded) {
      label = 'Next task';
      onPressed = null;
    } else if (_allStarterDone) {
      label = 'See your First Ten';
      onPressed = _openFirstTen;
    } else {
      final next = _nextIndex;
      if (next != null) {
        final seconds = _game!.tasks[next].teaserSeconds;
        label = 'Next task${seconds != null ? ' — $seconds s' : ''}';
        onPressed = () => _goNextTask(next);
      } else {
        label = 'Back home';
        onPressed = _backHome;
      }
    }
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        key: const Key('next-task-button'),
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white54,
          side: const BorderSide(color: Colors.white70),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

/// The auto-stamp, dropped from above: 2.4x and twisted, it slams down past
/// full size (the overshoot) and settles at its usual tilt.
class _SlammedStamp extends StatelessWidget {
  final Animation<double> animation;
  final String stamp;

  const _SlammedStamp({required this.animation, required this.stamp});

  static final Animatable<double> _scale = Tween<double>(begin: 2.4, end: 1.0)
      .chain(CurveTween(curve: Curves.easeOutBack));
  static final Animatable<double> _opacity =
      CurveTween(curve: const Interval(0, 0.18, curve: Curves.easeIn));
  static final Animatable<double> _twist = Tween<double>(begin: -0.22, end: 0)
      .chain(CurveTween(curve: Curves.easeOutCubic));

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = animation.value;
        return Opacity(
          opacity: _opacity.transform(t),
          child: Transform.rotate(
            angle: _twist.transform(t),
            child: Transform.scale(scale: _scale.transform(t), child: child),
          ),
        );
      },
      child: StampSticker(
        key: const Key('posted-stamp'),
        stamp: stamp,
        scale: 1.1,
      ),
    );
  }
}

/// The player's own entry as a polaroid: white frame, square picture, the
/// task title on the strip underneath, tilted 3 degrees.
class _Polaroid extends StatelessWidget {
  final double width;
  final FeedPost? post;
  final String title;

  const _Polaroid({
    super.key,
    required this.width,
    required this.post,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final inner = width - 20;
    return Transform.rotate(
      angle: 3 * math.pi / 180,
      child: Container(
        width: width,
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFDF8),
          borderRadius: BorderRadius.circular(4),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.35),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: inner,
              height: inner,
              child: ClipRect(child: _media()),
            ),
            SizedBox(
              height: 42,
              child: Center(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Fredoka',
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                    height: 1.15,
                    color: AppTheme.ink,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _media() {
    final p = post;
    if (p == null) {
      return const ColoredBox(
        color: AppTheme.violetSoft,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppTheme.violet),
          ),
        ),
      );
    }
    switch (p.mediaType) {
      case SubmissionMediaType.photo:
        final data = p.photoData;
        if (data != null && data.isNotEmpty) {
          try {
            return Image.memory(
              base64Decode(data),
              key: const Key('polaroid-photo'),
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => _textTile(p.caption ?? 'Photo'),
            );
          } catch (_) {
            // Fall through to the text tile.
          }
        }
        return _textTile(p.caption ?? 'Photo');
      case SubmissionMediaType.video:
        final poster = p.posterUrl;
        if (poster != null && poster.isNotEmpty) {
          return Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                poster,
                key: const Key('polaroid-poster'),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _videoTile(),
              ),
              const Center(child: _PlayBadge()),
            ],
          );
        }
        return _videoTile();
      case SubmissionMediaType.text:
        return _textTile(p.text ?? p.caption ?? '');
      case SubmissionMediaType.link:
        return Container(
          color: AppTheme.violetDeep,
          alignment: Alignment.center,
          child: const Icon(Icons.link_rounded, color: Colors.white, size: 40),
        );
    }
  }

  /// A clip whose poster frame is not ready yet (the server makes it after
  /// the transcode): a dark tile with a play badge.
  Widget _videoTile() => Container(
        key: const Key('polaroid-video'),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppTheme.ink, AppTheme.violetDeep],
          ),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _PlayBadge(),
            SizedBox(height: 8),
            Text(
              'Your clip',
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );

  Widget _textTile(String text) => Container(
        key: const Key('polaroid-text'),
        padding: const EdgeInsets.all(12),
        alignment: Alignment.center,
        decoration: const BoxDecoration(gradient: AppTheme.heroGradient),
        child: Text(
          text,
          textAlign: TextAlign.center,
          maxLines: 7,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: 'Fredoka',
            fontWeight: FontWeight.w600,
            fontSize: 16,
            height: 1.25,
            color: Colors.white,
          ),
        ),
      );
}

class _PlayBadge extends StatelessWidget {
  const _PlayBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withOpacity(0.45),
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
    );
  }
}
