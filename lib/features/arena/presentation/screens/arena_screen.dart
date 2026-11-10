import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shimmer/shimmer.dart';

import '../../../../core/config/environment.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/services/sfx/game_sfx.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../games/domain/repositories/game_repository.dart';
import '../../../games/presentation/bloc/games_bloc.dart';
import '../../../games/presentation/screens/game_detail_screen.dart';
import '../../../games/presentation/screens/task_execution_screen.dart';
import '../../../tasks/data/datasources/daily_task_data.dart';
import '../../../tasks/data/datasources/starter_pack_data.dart';
import '../../domain/models/feed_post.dart';
import '../../domain/models/montage.dart';
import '../../domain/repositories/feed_repository.dart';
import '../bloc/arena_bloc.dart';
import '../bloc/arena_event.dart';
import '../bloc/arena_state.dart';
import '../widgets/ad_slot_card.dart';
import '../widgets/finale_card.dart';
import '../widgets/grade_bar.dart';
import '../widgets/grade_reveal.dart';
import '../widgets/post_card.dart';

/// The Arena: a watch-and-grade queue, one post at a time, gated to tasks the
/// viewer has already submitted (see docs/PRODUCT_DIRECTION.md §2.3).
///
/// Takes no parameters — it reads the signed-in viewer off [AuthBloc] and
/// builds its own [ArenaBloc] from [FeedRepository].
class ArenaScreen extends StatelessWidget {
  const ArenaScreen({super.key});

  /// What the route pops with when a zero-post viewer taps the tease's
  /// "Your turn" bar. Home answers it by opening Starter Pack task 1; any
  /// other caller just gets the Arena closed, which lands them back on the
  /// task they came from.
  static const String yourTurnResult = 'your-turn';

  /// How long the grade reveal holds before the next post slides in. Any tap
  /// skips it.
  static const Duration revealHold = Duration(milliseconds: 1200);

  /// Test hooks for the "nothing left to grade" buttons. Null in the app,
  /// which opens the real task / lobby screens.
  @visibleForTesting
  static Future<void> Function(BuildContext context)? debugOpenNextTask;
  @visibleForTesting
  static Future<void> Function(BuildContext context)? debugChallengeFriends;
  @visibleForTesting
  static Future<void> Function(BuildContext context)? debugOpenDailyTask;

  /// Test hook for "now" on the next-up panel (which UTC day's task, and how
  /// long until the next). Null in the app: [DateTime.now].
  @visibleForTesting
  static DateTime Function()? debugClock;

  @override
  Widget build(BuildContext context) {
    final authState = context.read<AuthBloc>().state;
    final viewerId = authState is AuthAuthenticated ? authState.user.id : '';

    return BlocProvider(
      create: (_) => ArenaBloc(feedRepository: sl<FeedRepository>())
        ..add(LoadArena(viewerId: viewerId)),
      child: const _ArenaView(),
    );
  }
}

class _ArenaView extends StatelessWidget {
  const _ArenaView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('The Arena'),
        actions: [
          BlocBuilder<ArenaBloc, ArenaState>(
            builder: (context, state) {
              final graded = state is ArenaLoaded ? state.totalGradedByMe : 0;
              // App-bar action: drawn in the app bar's foreground colour
              // (white on violet), never body ink.
              final onBar = Theme.of(context).appBarTheme.foregroundColor ??
                  Theme.of(context).colorScheme.onPrimary;
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: onBar.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '✓ $graded graded',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: onBar,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: BlocConsumer<ArenaBloc, ArenaState>(
        listenWhen: (previous, current) =>
            current is ArenaLoaded &&
            current.justEarnedBoost &&
            !(previous is ArenaLoaded && previous.justEarnedBoost),
        listener: (context, state) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Your posts jumped the queue'),
            ),
          );
        },
        builder: (context, state) {
          if (state is ArenaLoading || state is ArenaInitial) {
            return const _ArenaSkeleton();
          }
          if (state is ArenaError) {
            return ErrorView(
              message: 'Something went wrong',
              details: state.message,
              onRetry: () {
                final authState = context.read<AuthBloc>().state;
                final viewerId =
                    authState is AuthAuthenticated ? authState.user.id : '';
                context.read<ArenaBloc>().add(LoadArena(viewerId: viewerId));
              },
            );
          }
          if (state is ArenaTeaser) {
            return _ArenaTeaserView(state: state);
          }
          if (state is ArenaEmpty) {
            return _ArenaEmptyView(nothingUnlocked: state.nothingUnlocked);
          }
          if (state is ArenaLoaded) {
            return _ArenaLoadedBody(state: state);
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

class _ArenaEmptyView extends StatelessWidget {
  final bool nothingUnlocked;

  const _ArenaEmptyView({required this.nothingUnlocked});

  @override
  Widget build(BuildContext context) {
    if (!nothingUnlocked) {
      return const _NextUpPanel(
        title: 'Nothing new to grade right now — check back soon.',
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.theater_comedy, size: 72, color: AppTheme.violet),
            const SizedBox(height: 24),
            Text(
              'Post yours to unlock everyone else\'s',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Do a task'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The end of the queue is never a dead end: the primary button is the next
/// Starter Pack task (which is also what unlocks more to grade). With all ten
/// done it is today's daily task; once that is posted too, "Done for today"
/// with the countdown, and Challenge friends. Back stays as a quiet text link.
class _NextUpPanel extends StatefulWidget {
  final String title;

  const _NextUpPanel({required this.title});

  @override
  State<_NextUpPanel> createState() => _NextUpPanelState();
}

class _NextUpPanelState extends State<_NextUpPanel> {
  bool _busy = false;
  StreamSubscription<List<FeedPost>>? _postsSub;
  List<FeedPost> _myPosts = const [];

  DateTime _now() => (ArenaScreen.debugClock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    // The viewer's own posts answer "is today's task posted". A read failure
    // just means the daily task is offered again, which is harmless.
    final auth = context.read<AuthBloc>().state;
    final uid = auth is AuthAuthenticated ? auth.user.id : '';
    if (uid.isEmpty || !sl.isRegistered<FeedRepository>()) return;
    try {
      _postsSub = sl<FeedRepository>().watchPostsByUser(uid).listen(
        (posts) {
          if (mounted) setState(() => _myPosts = posts);
        },
        onError: (Object e) => debugPrint('Arena next-up posts: $e'),
      );
    } catch (e) {
      debugPrint('Arena next-up posts: $e');
    }
  }

  @override
  void dispose() {
    _postsSub?.cancel();
    super.dispose();
  }

  /// Today's daily task is posted: an entry on today's task id made today
  /// (UTC). The task id alone is not enough; ids come round every 30 days.
  bool _dailyDoneToday(Set<String> unlocked, DateTime now) {
    final task = DailyTaskData.taskFor(now);
    if (!unlocked.contains(task.id)) return false;
    final today = DailyTaskData.dayKey(now);
    return _myPosts.any((p) =>
        !p.isHouse &&
        p.taskId == task.id &&
        // A post whose server timestamp has not landed yet was just made.
        (p.createdAt.isAtSameMomentAs(FeedPost.unknownCreatedAt) ||
            DailyTaskData.dayKey(p.createdAt) == today));
  }

  /// The first Starter Pack task the viewer has not posted to, or null once
  /// all ten are done. Posts are the record of what was submitted, so the
  /// Arena's unlocked set answers this without a game read.
  static int? _nextStarterSeconds(Set<String> unlocked) {
    for (final t in StarterPackData.tasks()) {
      // The first thing the button starts is the gather stage, if any.
      if (!unlocked.contains(t.id)) return t.teaserSeconds;
    }
    return null;
  }

  Future<void> _run(Future<void> Function(BuildContext) action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unlocked = context.read<ArenaBloc>().unlockedTaskIds;
    final seconds = _nextStarterSeconds(unlocked);
    final allDone = seconds == null;
    final now = _now();
    final daily = DailyTaskData.taskFor(now);
    final dailyDone = allDone && _dailyDoneToday(unlocked, now);

    final String primaryLabel;
    final String subline;
    final Future<void> Function(BuildContext) primaryAction;
    if (!allDone) {
      primaryLabel = 'Next task — $seconds s';
      subline = 'Do the next task to unlock more.';
      primaryAction = ArenaScreen.debugOpenNextTask ?? _openNextTask;
    } else if (!dailyDone) {
      primaryLabel = "Today's task — ${daily.teaserSeconds} s";
      subline = "Today's task is waiting. Same one for everyone.";
      primaryAction = ArenaScreen.debugOpenDailyTask ?? _openDailyTask;
    } else {
      primaryLabel = 'Challenge friends';
      subline = 'Done for today · new task in '
          '${DailyTaskData.formatUntil(DailyTaskData.untilNextTask(now))}';
      primaryAction = ArenaScreen.debugChallengeFriends ?? _challengeFriends;
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.theater_comedy, size: 64, color: AppTheme.violet),
            const SizedBox(height: 20),
            Text(
              widget.title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subline,
              key: const Key('arena-next-up-subline'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton(
                key: const Key('arena-next-up'),
                onPressed: _busy ? null : () => _run(primaryAction),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.coral,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        primaryLabel,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }

  /// Opens the player's next unsubmitted Starter Pack task with the clock
  /// armed, replacing everything above Home so the back stack stays short.
  static Future<void> _openNextTask(BuildContext context) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final bloc = GamesBloc(
      gameRepository: sl<GameRepository>(),
      authRepository: sl<AuthRepository>(),
    )..add(const StartStarterPack());
    try {
      await for (final state in bloc.stream) {
        if (state is StarterPackReady) {
          navigator.pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => TaskExecutionScreen(
                gameId: state.gameId,
                taskIndex: state.taskIndex,
                autoStart: true,
              ),
            ),
            (route) => route.isFirst,
          );
          break;
        }
        if (state is GamesError) {
          messenger.showSnackBar(
            const SnackBar(content: Text("Couldn't open your next task.")),
          );
          break;
        }
      }
    } finally {
      await bloc.close();
    }
  }

  /// Opens today's daily task with the clock armed, the same way Home's
  /// hero does (GamesBloc StartDailyTask -> TaskExecutionScreen autoStart).
  static Future<void> _openDailyTask(BuildContext context) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final bloc = GamesBloc(
      gameRepository: sl<GameRepository>(),
      authRepository: sl<AuthRepository>(),
    )..add(const StartDailyTask());
    try {
      await for (final state in bloc.stream) {
        if (state is DailyTaskReady) {
          navigator.pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => TaskExecutionScreen(
                gameId: state.gameId,
                taskIndex: 0,
                autoStart: true,
              ),
            ),
            (route) => route.isFirst,
          );
          break;
        }
        if (state is GamesError) {
          messenger.showSnackBar(
            const SnackBar(content: Text("Couldn't open today's task.")),
          );
          break;
        }
      }
    } finally {
      await bloc.close();
    }
  }

  /// Creates a "Challenge friends" game and lands in its lobby with the
  /// invite sheet already up — same as Home's all-done hero.
  static Future<void> _challengeFriends(BuildContext context) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final bloc = GamesBloc(
      gameRepository: sl<GameRepository>(),
      authRepository: sl<AuthRepository>(),
    )..add(const ChallengeFriends());
    try {
      await for (final state in bloc.stream) {
        if (state is ChallengeFriendsReady) {
          navigator.pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => GameDetailScreen(
                gameId: state.gameId,
                promptShareOnLoad: true,
              ),
            ),
            (route) => route.isFirst,
          );
          break;
        }
        if (state is GamesError) {
          messenger.showSnackBar(
            const SnackBar(content: Text("Couldn't set up the challenge.")),
          );
          break;
        }
      }
    } finally {
      await bloc.close();
    }
  }
}

/// WP-05: the Arena for a viewer with zero posts. The funniest content the
/// app has, visible exactly when a newcomer decides whether to stay — the
/// finale and the top few entries for task 1, one at a time, watch-only —
/// with a sticky "Your turn" bar. No grade bar: grading stays gated.
class _ArenaTeaserView extends StatefulWidget {
  final ArenaTeaser state;

  const _ArenaTeaserView({required this.state});

  @override
  State<_ArenaTeaserView> createState() => _ArenaTeaserViewState();
}

class _ArenaTeaserViewState extends State<_ArenaTeaserView> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final posts = widget.state.posts;
    final index = posts.isEmpty ? 0 : _index.clamp(0, posts.length - 1);
    final seconds = _durationFor(widget.state.taskId);

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text(
                    posts.isEmpty
                        ? 'Post yours to unlock everyone else\'s'
                        : teaserHeader(posts),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                // THE FINALE for task 1 (starter montages are shared, so the
                // scope id is all it needs). Renders nothing until one exists.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: FinaleCard(
                    gameId: Montage.starterScope,
                    taskId: widget.state.taskId,
                  ),
                ),
                if (posts.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: PostCard(
                      key: ValueKey('tease-${posts[index].id}'),
                      post: posts[index],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Icon(Icons.lock_outline,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Grading unlocks when you post yours.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (posts.length > 1)
                          TextButton(
                            onPressed: () => setState(
                                () => _index = (index + 1) % posts.length),
                            child: Text('Next (${index + 1}/${posts.length})'),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        Material(
          elevation: 8,
          color: theme.colorScheme.surface,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  key: const Key('arena-your-turn'),
                  onPressed: () =>
                      Navigator.of(context).pop(ArenaScreen.yourTurnResult),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.coral,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    seconds == null ? 'Your turn' : 'Your turn: $seconds s',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Only claim "everyone else" when there is a crowd: two or more real
  /// players. One robot is "Greg's assistant", not everyone.
  static String teaserHeader(List<FeedPost> posts) {
    final players = posts.where((p) => !p.isHouse).toList();
    if (players.length >= 2) return 'How everyone else did on task 1';
    final hasHouse = players.length < posts.length;
    final names = [
      if (players.isNotEmpty)
        players.single.displayName.trim().isEmpty
            ? 'a stranger'
            : players.single.displayName.trim(),
      if (hasHouse) StarterPackData.housePosterName,
    ];
    return 'How ${names.join(' and ')} did on task 1';
  }

  static int? _durationFor(String taskId) =>
      StarterPackData.byId(taskId)?.teaserSeconds;
}

class _ArenaLoadedBody extends StatefulWidget {
  final ArenaLoaded state;

  const _ArenaLoadedBody({required this.state});

  @override
  State<_ArenaLoadedBody> createState() => _ArenaLoadedBodyState();
}

class _ArenaLoadedBodyState extends State<_ArenaLoadedBody> {
  // Tracks the queue index for which the ad slot has already been shown and
  // continued past, so it renders exactly once per cadence hit rather than
  // reappearing on every rebuild of the same index.
  int? _adConsumedForIndex;

  bool get _adsVisible => AppConfig.adsEnabled || AdSlotCard.debugAlwaysShow;

  bool _shouldShowAdFor(int index) {
    if (!_adsVisible) return false;
    final isCadenceHit = (index + 1) % ArenaLoaded.adEvery == 0;
    return isCadenceHit && _adConsumedForIndex != index;
  }

  /// The post just graded, held on screen with the crowd's verdict over it.
  /// The bloc has already moved on (the grade is saved and counted the moment
  /// it is tapped); this only delays what the viewer SEES next.
  GradeReveal? _reveal;
  Timer? _revealTimer;

  GameSfx? get _sfx => sl.isRegistered<GameSfx>() ? sl<GameSfx>() : null;

  void _grade(FeedPost post, int score) {
    final reveal = GradeReveal.of(post, score);
    _sfx?.pop();
    if (reveal.isCrowdFive) _sfx?.fanfare();
    context.read<ArenaBloc>().add(GradeCurrent(score: score));
    _revealTimer?.cancel();
    _revealTimer = Timer(ArenaScreen.revealHold, _endReveal);
    setState(() => _reveal = reveal);
  }

  void _endReveal() {
    _revealTimer?.cancel();
    _revealTimer = null;
    if (mounted && _reveal != null) setState(() => _reveal = null);
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final reveal = _reveal;

    if (reveal == null) {
      if (state.isDone) {
        return const _NextUpPanel(
          title: "You've graded everything you've unlocked.",
        );
      }

      final index = state.index;
      if (_shouldShowAdFor(index)) {
        return SingleChildScrollView(
          child: AdSlotCard(
            onContinue: () => setState(() => _adConsumedForIndex = index),
          ),
        );
      }
    }

    final post = reveal?.post ?? state.current!;
    final body = SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        key: ValueKey(post.id),
        children: [
          // The automatic finale for this task, when the server has rendered
          // one. Silent no-op otherwise.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: FinaleCard(
              gameId: post.gameId,
              taskId: post.taskId,
              taskTitle: post.taskTitle,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: PostCard(
              post: post,
              onTap: (atSecond) =>
                  context.read<ArenaBloc>().add(TapCurrent(atSecond: atSecond)),
              // Over the media only, so the name and caption stay readable.
              overlay:
                  reveal == null ? null : GradeRevealOverlay(reveal: reveal),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Grade for: ${post.rubric ?? 'how it landed'}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 12),
                GradeBar(
                  selected: reveal?.you,
                  onGrade: (score) => _grade(post, score),
                ),
                Center(
                  child: TextButton(
                    onPressed: () =>
                        context.read<ArenaBloc>().add(const SkipCurrent()),
                    child: const Text('Skip'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    // While the reveal holds, the whole screen is one big "skip" button: a
    // fast grader taps once and is on the next post. The wrapper is always
    // there (just inert without a reveal) so the card and grade bar keep
    // their state — the clip does not restart and the chip still bounces.
    return GestureDetector(
      key: const Key('arena-reveal-skip'),
      behavior: HitTestBehavior.translucent,
      onTap: reveal == null ? null : _endReveal,
      child: AbsorbPointer(absorbing: reveal != null, child: body),
    );
  }
}

class _ArenaSkeleton extends StatelessWidget {
  const _ArenaSkeleton();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Shimmer.fromColors(
        baseColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        highlightColor: Theme.of(context).colorScheme.surface,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 4 / 5,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(height: 16, width: 180, color: Colors.white),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(
                5,
                (_) => Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
