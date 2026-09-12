import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/models/game.dart';
import '../../../../core/services/notification_prompt.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/skeleton_loaders.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../arena/presentation/screens/arena_screen.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../games/domain/repositories/game_repository.dart';
import '../../../games/presentation/bloc/games_bloc.dart';
import '../../../games/presentation/screens/game_detail_screen.dart';
import '../../../games/presentation/screens/task_execution_screen.dart';
import '../../../telephone/presentation/widgets/nearby_auto_cast_banner.dart';
import '../widgets/arena_entry_button.dart';
import '../widgets/game_card.dart';
import '../widgets/home_app_bar.dart';
import '../../../friends/presentation/widgets/invite_inbox_card.dart';
import '../widgets/home_invites_section.dart';
import '../widgets/next_task_hero_card.dart';
import '../widgets/play_sheet.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

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
      )..add(LoadGames()),
      child: const HomeView(),
    );
  }
}

class HomeView extends StatelessWidget {
  const HomeView({super.key});

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

        if (state is StarterPackReady) {
          // A returning user with no starter game yet tapped Start on the
          // "Your first ten tasks are waiting" hero — open the first task
          // with its timer already running, same as the cold open.
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
      },
      child: Scaffold(
        appBar: const HomeAppBar(),
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
                      // invites. Each self-hides when empty — no empty shame
                      // box (see docs/PRODUCT_DIRECTION.md §1 #3).
                      const InviteInboxCard(),
                      const HomeInvitesSection(),
                      // Zone 1: "Your next task" — the starter-pack hero.
                      _buildNextTaskHero(context, state),
                      const SizedBox(height: 16),
                      // Zone 2: the Arena — grade the crowd.
                      ArenaEntryButton(onTap: () => _openArena(context)),
                      const SizedBox(height: 24),
                      // Jump back into active friend games, if any.
                      ..._buildJumpBackIn(context, state),
                      // Zone 3: the one big Play button.
                      _buildPlayButton(context, state),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Zone 1 — "Your next task": the starter-pack hero (see
  /// docs/PRODUCT_DIRECTION.md §4 step 5). Three shapes, all driven by plain
  /// values through [NextTaskHeroCard]:
  ///  - no starter game yet (an account from before this round) -> offer to
  ///    start one;
  ///  - a starter game with a task left -> that task, timer and Start;
  ///  - all ten done -> offer to play with friends.
  Widget _buildNextTaskHero(BuildContext context, GamesState state) {
    if (state is! GamesLoaded) return const SizedBox.shrink();

    Game? starterGame;
    for (final g in state.games) {
      if (g.isStarter) {
        starterGame = g;
        break;
      }
    }

    if (starterGame == null) {
      return NextTaskHeroCard(
        mode: NextTaskHeroMode.noStarterGame,
        onPrimary: () =>
            context.read<GamesBloc>().add(const StartStarterPack()),
      );
    }

    final authState = context.read<AuthBloc>().state;
    final userId = authState is AuthAuthenticated ? authState.user.id : '';

    var nextIndex = -1;
    for (var i = 0; i < starterGame.tasks.length; i++) {
      if (!starterGame.tasks[i].hasUserSubmitted(userId)) {
        nextIndex = i;
        break;
      }
    }

    if (nextIndex == -1) {
      return NextTaskHeroCard(
        mode: NextTaskHeroMode.allDone,
        onPrimary: () => showPlaySheet(context),
      );
    }

    final gameId = starterGame.id;
    final task = starterGame.tasks[nextIndex];
    return NextTaskHeroCard(
      mode: NextTaskHeroMode.hasTask,
      taskTitle: task.title,
      timerSeconds: task.durationSeconds,
      onPrimary: () => Navigator.of(context)
          .push(
            MaterialPageRoute(
              builder: (_) => TaskExecutionScreen(
                gameId: gameId,
                taskIndex: nextIndex,
                autoStart: true,
              ),
            ),
          )
          .then((_) => context.read<GamesBloc>().add(LoadGames())),
    );
  }

  /// Zone 2 — "Jump back in": hero the most recent active (lobby / in-progress)
  /// game as a one-tap resume card, with any remaining games in a compact list
  /// below. Completed games stay reachable in that list. Empty games list ->
  /// nothing here, so the Play button (Zone 3) floats up and takes centre stage.
  List<Widget> _buildJumpBackIn(BuildContext context, GamesState state) {
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
      final games = state.games;
      if (games.isEmpty) return const [];

      final active = games
          .where((g) => g.isInLobby || g.isInProgress)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final Game? hero = active.isNotEmpty ? active.first : null;
      final remaining = games.where((g) => g.id != hero?.id).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      return [
        Text(
          hero != null ? 'Jump back in' : 'Your games',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (hero != null) ...[
          _ResumeHeroCard(
            game: hero,
            onTap: () => _openGame(context, hero.id),
          ),
          const SizedBox(height: 12),
        ],
        for (final game in remaining)
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

  /// Zone 3 — the single, prominent "▶ Play" button. It's the primary action;
  /// when there are no invites and no games it's the only thing on screen, so it
  /// naturally takes centre stage.
  Widget _buildPlayButton(BuildContext context, GamesState state) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SizedBox(
        height: 64,
        child: FilledButton.icon(
          onPressed: () => showPlaySheet(context),
          icon: const Icon(Icons.play_arrow_rounded, size: 32),
          label: const Text(
            'Play',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.coral,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ),
      ),
    );
  }

  void _openArena(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ArenaScreen()),
    );
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

/// The "Jump back in" hero: a prominent one-tap card resuming the most recent
/// active game.
class _ResumeHeroCard extends StatelessWidget {
  const _ResumeHeroCard({required this.game, required this.onTap});

  final Game game;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = game.isInProgress ? 'In progress' : 'In the lobby';
    return Card(
      elevation: 3,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppTheme.violet, AppTheme.coral],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.play_circle_fill,
                    size: 32, color: Colors.white),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      game.gameName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$label · ${game.players.length} player'
                      '${game.players.length == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios,
                  color: Colors.white, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
