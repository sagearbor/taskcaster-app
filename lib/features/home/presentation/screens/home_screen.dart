import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/models/game.dart';
import '../../../../core/services/notification_prompt.dart';
import '../../../../core/widgets/skeleton_loaders.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../arena/domain/models/feed_post.dart';
import '../../../arena/domain/repositories/feed_repository.dart';
import '../../../arena/presentation/bloc/arena_bloc.dart';
import '../../../arena/presentation/screens/arena_screen.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../games/domain/repositories/game_repository.dart';
import '../../../games/presentation/bloc/games_bloc.dart';
import '../../../games/presentation/screens/game_detail_screen.dart';
import '../../../games/presentation/screens/task_execution_screen.dart';
import '../../../telephone/presentation/widgets/nearby_auto_cast_banner.dart';
import '../../domain/home_hero_plan.dart';
import '../widgets/arena_entry_button.dart';
import '../widgets/game_card.dart';
import '../widgets/home_app_bar.dart';
import '../../../friends/presentation/widgets/invite_inbox_card.dart';
import '../widgets/home_invites_section.dart';
import '../widgets/next_task_hero_card.dart';
import '../widgets/play_sheet.dart';

class HomeScreen extends StatelessWidget {
  /// "Now", injectable so tests can pin the UTC day (today's task, the
  /// streak, the countdown). Defaults to [DateTime.now].
  final DateTime Function()? clock;

  const HomeScreen({super.key, this.clock});

  @override
  Widget build(BuildContext context) {
    // Ask for push permission in context (once, after the first home frame)
    // instead of at process start — see NotificationPrompt.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => NotificationPrompt.ensureRequestedOnce(),
    );
    return BlocProvider(
      create: (context) => GamesBloc(
        gameRepository: sl<GameRepository>(),
        authRepository: sl<AuthRepository>(),
        clock: clock,
      )..add(LoadGames()),
      child: HomeView(clock: clock),
    );
  }
}

class HomeView extends StatelessWidget {
  final DateTime Function()? clock;

  const HomeView({super.key, this.clock});

  @override
  Widget build(BuildContext context) {
    return BlocListener<GamesBloc, GamesState>(
      listener: (context, state) {
        if (state is QuickPlaySuccess) {
          // Navigate directly to game detail. When the player returns, the
          // bloc is still parked in QuickPlaySuccess (the games builder would
          // otherwise fall through to a blank list), so re-load the games
          // stream to restore the list + pull-to-refresh.
          final gamesBloc = context.read<GamesBloc>();
          Navigator.of(context)
              .push(
                MaterialPageRoute(
                  builder: (context) => GameDetailScreen(gameId: state.gameId),
                ),
              )
              .then((_) => gamesBloc.add(LoadGames()));
        }

        if (state is ChallengeFriendsReady) {
          // Play sheet / all-done hero -> "Challenge friends": land in the
          // new game's lobby with the invite dialog already open.
          final gamesBloc = context.read<GamesBloc>();
          Navigator.of(context)
              .push(
                MaterialPageRoute(
                  builder: (context) => GameDetailScreen(
                    gameId: state.gameId,
                    promptShareOnLoad: true,
                  ),
                ),
              )
              .then((_) => gamesBloc.add(LoadGames()));
        }

        if (state is StarterPackReady) {
          // A returning user with no starter game yet tapped Start on the
          // "Your first ten tasks are waiting" hero, or a zero-post viewer
          // tapped the Arena tease's "Your turn": open their next task
          // (straight past the reveal; the clock waits for the camera).
          final gamesBloc = context.read<GamesBloc>();
          Navigator.of(context)
              .push(
                MaterialPageRoute(
                  builder: (context) => TaskExecutionScreen(
                    gameId: state.gameId,
                    taskIndex: state.taskIndex,
                    autoStart: true,
                  ),
                ),
              )
              .then((_) => gamesBloc.add(LoadGames()));
        }

        if (state is DailyTaskReady) {
          // WP-6: today's task, straight past the reveal like the starter.
          final gamesBloc = context.read<GamesBloc>();
          Navigator.of(context)
              .push(
                MaterialPageRoute(
                  builder: (context) => TaskExecutionScreen(
                    gameId: state.gameId,
                    taskIndex: 0,
                    autoStart: true,
                  ),
                ),
              )
              .then((_) => gamesBloc.add(LoadGames()));
        }
      },
      child: Builder(
        builder: (context) => Scaffold(
          // WP-05: Play moved off the page into the app bar's "+", so Home
          // has exactly one primary (filled) button: the hero's.
          appBar: HomeAppBar(onPlay: () => showPlaySheet(context)),
          body: Column(
            children: [
              // Auto-cast: passively surfaces a one-tap "Join" when a nearby
              // phone starts an offline game (Android only; silent otherwise).
              const NearbyAutoCastBanner(),
              Expanded(
                child: BlocBuilder<GamesBloc, GamesState>(
                  builder: (context, state) => RefreshIndicator(
                    onRefresh: () async {
                      context.read<GamesBloc>().add(LoadGames());
                    },
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                      children: [
                        // Invites from friends — the first thing an invited
                        // player sees, above the starter-pack hero. Two
                        // sources, both one-tap join: friend-graph invites
                        // (invites collection) and legacy email-matched
                        // invites. Each self-hides when empty — no empty
                        // shame box (see docs/PRODUCT_DIRECTION.md §1 #3).
                        const InviteInboxCard(),
                        const HomeInvitesSection(),
                        // 1. The one hero: the next task, or "Waiting for
                        //    the crowd: N" once all ten are done.
                        _buildNextTaskHero(context, state),
                        const SizedBox(height: 16),
                        // 2. The Arena row, with an unread count.
                        HomeArenaRow(onTap: () => _openArena(context)),
                        const SizedBox(height: 24),
                        // 3. Your games.
                        ..._buildYourGames(context, state),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The player's starter game and the index of their next unsubmitted task
  /// in it (-1 when all ten are done). Null game = no starter game yet.
  static ({Game? game, int nextIndex}) _starterProgress(
    BuildContext context,
    GamesLoaded state,
  ) {
    final authState = context.read<AuthBloc>().state;
    final userId = authState is AuthAuthenticated ? authState.user.id : '';
    final plan = HomeHeroPlan.resolve(
      games: state.games,
      myPosts: const [],
      userId: userId,
      now: DateTime.now(),
    );
    return (game: plan.starterGame, nextIndex: plan.starterNextIndex);
  }

  /// Zone 1 — the hero (see docs/PRODUCT_DIRECTION.md §4 step 5, and WP-6):
  /// the next starter task, today's task, or "Done for today". Which one is
  /// decided by [HomeHeroPlan]; [HomeHero] renders it.
  Widget _buildNextTaskHero(BuildContext context, GamesState state) {
    if (state is! GamesLoaded) return const SizedBox.shrink();

    return HomeHero(
      games: state.games,
      clock: clock ?? DateTime.now,
      onOpenArena: () => _openArena(context),
      onOpenTask: (gameId, taskIndex) => Navigator.of(context)
          .push(
            MaterialPageRoute(
              builder: (_) => TaskExecutionScreen(
                gameId: gameId,
                taskIndex: taskIndex,
                autoStart: true,
              ),
            ),
          )
          .then((_) => context.read<GamesBloc>().add(LoadGames())),
    );
  }

  /// Zone 3 — "Your games": a plain list, newest first. The starter game is
  /// left out while it still has a task to do (the hero already IS that
  /// game); once all ten are done it joins the list like any other. Daily
  /// Task games never show here (WP-6): one a day would bury the friend
  /// games, and the hero already covers today's.
  List<Widget> _buildYourGames(BuildContext context, GamesState state) {
    if (state is GamesError) {
      return [
        ErrorView(
          message: 'Failed to load games',
          details: state.message,
          onRetry: () => context.read<GamesBloc>().add(LoadGames()),
        ),
        const SizedBox(height: 24),
      ];
    }

    if (state is GamesLoaded) {
      final progress = _starterProgress(context, state);
      final hideId = progress.nextIndex == -1 ? null : progress.game?.id;
      final games = state.games
          .where((g) => g.id != hideId && !g.isDaily)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      final theme = Theme.of(context);
      return [
        Text(
          'Your games',
          style:
              theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (games.isEmpty)
          Text(
            'No friend games yet. Tap + to challenge your friends.',
            key: const Key('home-your-games-empty'),
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        for (final game in games)
          GameCard(
            game: game,
            onTap: () => _openGame(context, game.id),
          ),
        const SizedBox(height: 24),
      ];
    }

    // Loading (and any transient state, e.g. QuickPlay in flight): skeletons.
    return [
      for (var i = 0; i < 2; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SkeletonLoaders.gameCardSkeleton(context),
        ),
      const SizedBox(height: 12),
    ];
  }

  Future<void> _openArena(BuildContext context) async {
    final gamesBloc = context.read<GamesBloc>();
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute(builder: (_) => const ArenaScreen()),
    );
    // The zero-post tease's "Your turn" bar: open task 1 (idempotent — finds
    // the existing starter game, or creates it). Otherwise just refresh, which
    // also refreshes the Arena row's unread count.
    gamesBloc.add(result == ArenaScreen.yourTurnResult
        ? const StartStarterPack()
        : LoadGames());
  }

  void _openGame(BuildContext context, String gameId) {
    final gamesBloc = context.read<GamesBloc>();
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => GameDetailScreen(gameId: gameId),
          ),
        )
        .then((_) => gamesBloc.add(LoadGames()));
  }
}

/// Home's hero (WP-6). Watches the player's own posts (for the 🔥 streak and
/// "posted today") and ticks once a minute (for "New task in 5 h 12 m" and
/// the UTC-midnight switch to tomorrow's task), then renders whatever
/// [HomeHeroPlan.resolve] decides through [NextTaskHeroCard].
class HomeHero extends StatefulWidget {
  final List<Game> games;
  final DateTime Function() clock;
  final VoidCallback onOpenArena;
  final void Function(String gameId, int taskIndex) onOpenTask;

  const HomeHero({
    super.key,
    required this.games,
    required this.clock,
    required this.onOpenArena,
    required this.onOpenTask,
  });

  @override
  State<HomeHero> createState() => _HomeHeroState();
}

class _HomeHeroState extends State<HomeHero> {
  StreamSubscription<List<FeedPost>>? _postsSub;
  List<FeedPost> _posts = const [];
  Timer? _ticker;
  String _userId = '';

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  /// (Re)subscribe to [userId]'s posts when the signed-in user changes.
  void _watchPostsOf(String userId) {
    if (userId == _userId) return;
    _userId = userId;
    _postsSub?.cancel();
    _postsSub = null;
    _posts = const [];
    if (userId.isEmpty || !sl.isRegistered<FeedRepository>()) return;
    _postsSub = sl<FeedRepository>().watchPostsByUser(userId).listen(
      (posts) {
        if (mounted) setState(() => _posts = posts);
      },
      // The streak is a nicety: never an error on Home.
      onError: (Object e) => debugPrint('HomeHero posts stream: $e'),
    );
  }

  @override
  void dispose() {
    _postsSub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _watchPostsOf(context.select((AuthBloc b) {
      final s = b.state;
      return s is AuthAuthenticated ? s.user.id : '';
    }));
    final plan = HomeHeroPlan.resolve(
      games: widget.games,
      myPosts: _posts,
      userId: _userId,
      now: widget.clock(),
    );
    final bloc = context.read<GamesBloc>();
    final streak = plan.streak;
    final atRiskLine = plan.streakAtRisk
        ? 'Post something today or the 🔥 $streak goes out.'
        : null;
    final waiting =
        _posts.where((p) => p.gradeCount < ArenaBloc.boostThreshold).length;
    final waitingLine = waiting > 0 ? 'Waiting for the crowd: $waiting' : null;

    switch (plan.kind) {
      case HomeHeroKind.noStarter:
        return NextTaskHeroCard(
          mode: NextTaskHeroMode.noStarterGame,
          streak: streak,
          onPrimary: () => bloc.add(const StartStarterPack()),
        );

      case HomeHeroKind.starterTask:
        final task = plan.starterTask!;
        final game = plan.starterGame!;
        return NextTaskHeroCard(
          mode: NextTaskHeroMode.hasTask,
          taskTitle: task.title,
          timerSeconds: task.durationSeconds,
          streak: streak,
          subline: plan.dailyDone ? "Today's task: done." : atRiskLine,
          onPrimary: () => widget.onOpenTask(game.id, plan.starterNextIndex),
        );

      case HomeHeroKind.dailyTask:
        final starter = plan.starterGame;
        final starterLeft = plan.starterHasTasksLeft;
        return NextTaskHeroCard(
          key: const Key('home-hero-daily'),
          mode: NextTaskHeroMode.dailyTask,
          taskTitle: plan.dailyTask.title,
          timerSeconds: plan.dailyTask.durationSeconds,
          streak: streak,
          subline: atRiskLine ?? (starterLeft ? null : waitingLine),
          onPrimary: () => bloc.add(const StartDailyTask()),
          secondaryLabel: starterLeft
              ? 'Or carry on with your first ten '
                  '(${plan.starterNextIndex + 1} of ${starter!.tasks.length})'
              : 'Challenge friends',
          onSecondary: starterLeft
              ? () => widget.onOpenTask(starter!.id, plan.starterNextIndex)
              : () => bloc.add(const ChallengeFriends()),
        );

      case HomeHeroKind.dailyDone:
        return NextTaskHeroCard(
          key: const Key('home-hero-daily-done'),
          mode: NextTaskHeroMode.dailyDone,
          streak: streak,
          nextTaskIn: plan.untilNextTask,
          subline: waitingLine,
          onPrimary: widget.onOpenArena,
          secondaryLabel: 'Challenge friends',
          onSecondary: () => bloc.add(const ChallengeFriends()),
        );
    }
  }
}

/// Home's Arena row with its unread count: how many entries are waiting in
/// the viewer's grading queue, or a "see how others did" tease for a viewer
/// who has posted nothing. Re-reads after every games reload (i.e. whenever
/// the player comes back to Home), with one-shot reads rather than live
/// listeners so an idle Home costs nothing.
class HomeArenaRow extends StatefulWidget {
  final VoidCallback onTap;

  /// Queue page read for the count; a full page shows as "N+ new".
  static const int countCap = 10;

  const HomeArenaRow({super.key, required this.onTap});

  @override
  State<HomeArenaRow> createState() => _HomeArenaRowState();
}

class _HomeArenaRowState extends State<HomeArenaRow> {
  int? _unread;
  bool _tease = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final generation = ++_generation;
    final authState = context.read<AuthBloc>().state;
    final userId = authState is AuthAuthenticated ? authState.user.id : '';
    if (userId.isEmpty || !sl.isRegistered<FeedRepository>()) return;
    final feed = sl<FeedRepository>();
    const timeout = Duration(seconds: 10);
    try {
      final ids =
          await feed.watchUnlockedTaskIds(userId).first.timeout(timeout);
      if (ids.isEmpty) {
        if (!mounted || generation != _generation) return;
        setState(() {
          _tease = true;
          _unread = null;
        });
        return;
      }
      final queue = await feed
          .watchQueue(
            viewerId: userId,
            unlockedTaskIds: ids,
            limit: HomeArenaRow.countCap,
          )
          .first
          .timeout(timeout);
      if (!mounted || generation != _generation) return;
      setState(() {
        _tease = false;
        _unread = queue.length;
      });
    } catch (e) {
      // A count is a nicety: never an error on Home.
      debugPrint('HomeArenaRow could not count the queue: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<GamesBloc, GamesState>(
      // A fresh games snapshot after a reload = the player is back on Home.
      listenWhen: (previous, current) =>
          current is GamesLoaded && previous is! GamesLoaded,
      listener: (_, __) => _refresh(),
      child: ArenaEntryButton(
        onTap: widget.onTap,
        unreadCount: _unread,
        tease: _tease,
        countCap: HomeArenaRow.countCap,
      ),
    );
  }
}
