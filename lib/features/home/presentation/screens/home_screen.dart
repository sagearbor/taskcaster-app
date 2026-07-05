import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/models/game.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/skeleton_loaders.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import '../../../games/domain/repositories/game_repository.dart';
import '../../../games/presentation/bloc/games_bloc.dart';
import '../../../games/presentation/screens/game_detail_screen.dart';
import '../../../telephone/presentation/widgets/nearby_auto_cast_banner.dart';
import '../widgets/game_card.dart';
import '../widgets/home_app_bar.dart';
import '../widgets/home_invites_section.dart';
import '../widgets/play_sheet.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
                      // Zone 1: invites from friends — the first thing an
                      // invited player sees. One widget slot (SEAM: a richer
                      // InviteInboxCard from lib/features/friends/ will swap in
                      // here later).
                      const HomeInvitesSection(),
                      const SizedBox(height: 24),
                      // Zone 2: jump back into active games, if any.
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
