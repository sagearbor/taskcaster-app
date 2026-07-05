import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/skeleton_loaders.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../games/domain/repositories/game_repository.dart';
import '../../../games/presentation/bloc/games_bloc.dart';
import '../../../games/presentation/screens/create_game_screen.dart';
import '../../../games/presentation/screens/game_detail_screen.dart';
import '../../../games/presentation/screens/discover_games_screen.dart';
import '../../../balloon_blitz/presentation/screens/balloon_blitz_start_screen.dart';
import '../../../telephone/presentation/screens/telephone_start_screen.dart';
import '../../../telephone/presentation/widgets/nearby_auto_cast_banner.dart';
import '../../../trivia/presentation/screens/trivia_start_screen.dart';
import '../widgets/game_card.dart';
import '../widgets/game_mode_card.dart';
import '../widgets/home_app_bar.dart';

/// Gradient stops without an AppTheme token (the telephone/trivia banners'
/// secondary hues). Everything else uses AppTheme colors directly.
const _violetBright = Color(0xFF7C3AED);
const _blue = Color(0xFF2563EB);

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
            // One scroll area: game-mode entries scroll away with the games
            // list instead of pinning it into a sliver of screen.
            Expanded(
              child: BlocBuilder<GamesBloc, GamesState>(
                builder: (context, state) => RefreshIndicator(
                  onRefresh: () async {
                    context.read<GamesBloc>().add(LoadGames());
                  },
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    children: [
                      ..._buildModeCards(context),
                      const SizedBox(height: 20),
                      Text(
                        'Your games',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                      const SizedBox(height: 8),
                      ..._buildGamesContent(context, state),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        // ONE floating action — creating a game. Join lives in the app bar;
        // every game mode (AR, Discover, …) is an entry in the list above.
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'create',
          onPressed: () {
            _handleCreateGame(context);
          },
          icon: const Icon(Icons.add),
          label: const Text('Create Game'),
        ),
      ),
    );
  }

  /// All game-mode entries: Quick Play hero up top, then one compact banner
  /// per mode — including AR Games and Discover, which are game entries (not
  /// nav actions, so they don't belong in floating buttons).
  List<Widget> _buildModeCards(BuildContext context) {
    return [
      GameModeCard(
        hero: true,
        title: 'Quick Play',
        subtitle: 'Jump into a game in seconds!',
        icon: Icons.flash_on,
        gradientColors: const [AppTheme.coral, AppTheme.gold],
        onTap: () => _handleQuickPlay(context),
      ),
      const SizedBox(height: 12),
      GameModeCard(
        title: 'Drawing Telephone',
        subtitle: 'Draw → guess → laugh. Play across phones.',
        icon: Icons.brush,
        gradientColors: const [_violetBright, _blue],
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const TelephoneStartScreen(),
            ),
          );
        },
      ),
      const SizedBox(height: 8),
      GameModeCard(
        title: 'Trivia Buzzer',
        subtitle:
            'Buzz in fast — fastest correct answer wins. Plays offline.',
        icon: Icons.quiz,
        gradientColors: const [AppTheme.violet, AppTheme.gold],
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const TriviaStartScreen(),
            ),
          );
        },
      ),
      const SizedBox(height: 8),
      GameModeCard(
        title: 'Balloon Blitz',
        subtitle: 'AR balloon race — works offline',
        icon: Icons.celebration,
        gradientColors: const [AppTheme.coral, AppTheme.gold],
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const BalloonBlitzStartScreen(),
            ),
          );
        },
      ),
      const SizedBox(height: 8),
      GameModeCard(
        title: 'AR Games',
        subtitle: 'Solo AR challenges — point, pop, score.',
        icon: Icons.view_in_ar,
        gradientColors: const [AppTheme.coral, AppTheme.violet],
        onTap: () =>
            context.read<GamesBloc>().add(const QuickPlayGame(ar: true)),
      ),
      const SizedBox(height: 8),
      GameModeCard(
        title: 'Discover',
        subtitle: 'Browse community games and clone one for your crew.',
        icon: Icons.public,
        gradientColors: const [AppTheme.violet, AppTheme.coral],
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const DiscoverGamesScreen(),
            ),
          );
        },
      ),
    ];
  }

  /// The "Your games" section, embedded in the shared scroll view.
  List<Widget> _buildGamesContent(BuildContext context, GamesState state) {
    if (state is GamesError) {
      return [
        ErrorView(
          message: 'Failed to load games',
          details: state.message,
          onRetry: () {
            context.read<GamesBloc>().add(LoadGames());
          },
        ),
      ];
    }

    if (state is GamesLoaded) {
      if (state.games.isEmpty) {
        return [
          ErrorView.empty(
            entity: 'games',
            action: 'create your first game',
            onAction: () {
              _handleCreateGame(context);
            },
          ),
        ];
      }

      return [
        for (final game in state.games)
          GameCard(
            game: game,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => GameDetailScreen(gameId: game.id),
                ),
              );
            },
          ),
      ];
    }

    // Loading (and any transient state, e.g. QuickPlay in flight): skeletons.
    return [
      for (var i = 0; i < 3; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SkeletonLoaders.gameCardSkeleton(context),
        ),
    ];
  }

  // Guests are real Firebase anonymous users — a genuine uid that satisfies
  // the Firestore rules (`creatorId == request.auth.uid`) — so they get the
  // full hero CTAs, no sign-up wall. They can upgrade to a named account
  // later (Settings) without losing their games.
  void _handleQuickPlay(BuildContext context) {
    context.read<GamesBloc>().add(const QuickPlayGame());
  }

  void _handleCreateGame(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BlocProvider.value(
          value: context.read<AuthBloc>(),
          child: const CreateGameScreen(),
        ),
      ),
    );
  }
}
