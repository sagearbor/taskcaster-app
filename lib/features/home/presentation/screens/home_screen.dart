import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/widgets/skeleton_loaders.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/screens/register_screen.dart';
import '../../../games/domain/repositories/game_repository.dart';
import '../../../games/presentation/bloc/games_bloc.dart';
import '../../../games/presentation/screens/create_game_screen.dart';
import '../../../games/presentation/screens/join_game_screen.dart';
import '../../../games/presentation/screens/game_detail_screen.dart';
import '../../../games/presentation/screens/discover_games_screen.dart';
import '../../../balloon_blitz/presentation/screens/balloon_blitz_start_screen.dart';
import '../../../telephone/presentation/screens/telephone_start_screen.dart';
import '../../../telephone/presentation/widgets/nearby_auto_cast_banner.dart';
import '../../../trivia/presentation/screens/trivia_start_screen.dart';
import '../widgets/game_card.dart';
import '../widgets/home_app_bar.dart';

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
            // Quick Play Hero Banner
            _buildQuickPlayBanner(context),
            // Party game: Drawing Telephone (real-time, cross-device)
            _buildDrawingTelephoneBanner(context),
            // Party game: Trivia Buzzer (offline, host-authoritative transport)
            _buildTriviaBuzzerBanner(context),
            // Party game: Balloon Blitz (offline AR race, host-authoritative scores)
            _buildBalloonBlitzBanner(context),
            // Games List
            Expanded(
              child: BlocBuilder<GamesBloc, GamesState>(
                builder: (context, state) {
                  return _buildGamesContent(context, state);
                },
              ),
            ),
          ],
        ),
        floatingActionButton: _buildFloatingButtons(context),
      ),
    );
  }

  Widget _buildQuickPlayBanner(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      child: Card(
        elevation: 4,
        child: InkWell(
          onTap: () {
            _handleQuickPlay(context);
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(
                colors: [Color(0xFFFB5779), Color(0xFFF59E0B)],
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
                  child: const Icon(
                    Icons.flash_on,
                    size: 32,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '⚡ Quick Play',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Jump into a game in seconds!',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDrawingTelephoneBanner(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Card(
        elevation: 3,
        child: InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const TelephoneStartScreen(),
              ),
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(
                colors: [Color(0xFF7C3AED), Color(0xFF2563EB)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.brush, size: 26, color: Colors.white),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '🎨 Drawing Telephone',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Draw → guess → laugh. Play across phones.',
                        style: TextStyle(fontSize: 13, color: Colors.white),
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
      ),
    );
  }

  Widget _buildTriviaBuzzerBanner(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Card(
        elevation: 3,
        child: InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const TriviaStartScreen(),
              ),
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(
                colors: [Color(0xFF6D28D9), Color(0xFFF59E0B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.quiz, size: 26, color: Colors.white),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '🧠 Trivia Buzzer',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Buzz in fast — fastest correct answer wins. Plays offline.',
                        style: TextStyle(fontSize: 13, color: Colors.white),
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
      ),
    );
  }

  Widget _buildBalloonBlitzBanner(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Card(
        elevation: 3,
        child: InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const BalloonBlitzStartScreen(),
              ),
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(
                colors: [Color(0xFFFB5779), Color(0xFFF59E0B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.celebration,
                      size: 26, color: Colors.white),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '🎈 Balloon Blitz (vs family, offline)',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Race to pop the most balloons in AR. Scores sync live — '
                        'no internet.',
                        style: TextStyle(fontSize: 13, color: Colors.white),
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
      ),
    );
  }

  Widget _buildGamesContent(BuildContext context, GamesState state) {
    if (state is GamesLoading) {
      return SkeletonLoaders.listSkeleton(
        itemCount: 3,
        itemHeight: 120,
      );
    }

    if (state is GamesError) {
      return ErrorView(
        message: 'Failed to load games',
        details: state.message,
        onRetry: () {
          context.read<GamesBloc>().add(LoadGames());
        },
      );
    }

    if (state is GamesLoaded) {
      if (state.games.isEmpty) {
        return ErrorView.empty(
          entity: 'games',
          action: 'create your first game',
          onAction: () {
            _handleCreateGame(context);
          },
        );
      }

      return RefreshIndicator(
        onRefresh: () async {
          context.read<GamesBloc>().add(LoadGames());
        },
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: state.games.length,
          itemBuilder: (context, index) {
            final game = state.games[index];
            return GameCard(
              game: game,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => GameDetailScreen(gameId: game.id),
                  ),
                );
              },
            );
          },
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildFloatingButtons(BuildContext context) {
    // Labeled extended FABs so first-time players can read what each does.
    // Quick Play remains the hero banner up top.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        FloatingActionButton.extended(
          heroTag: 'ar',
          onPressed: () =>
              context.read<GamesBloc>().add(const QuickPlayGame(ar: true)),
          backgroundColor: const Color(0xFFFB5779),
          foregroundColor: Colors.white,
          icon: const Icon(Icons.view_in_ar),
          label: const Text('AR Games'),
        ),
        const SizedBox(height: 12),
        FloatingActionButton.extended(
          heroTag: 'discover',
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const DiscoverGamesScreen(),
              ),
            );
          },
          backgroundColor: Theme.of(context).colorScheme.tertiary,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.public),
          label: const Text('Discover'),
        ),
        const SizedBox(height: 12),
        FloatingActionButton.extended(
          heroTag: 'join',
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const JoinGameScreen(),
              ),
            );
          },
          backgroundColor: Theme.of(context).colorScheme.secondary,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.group_add),
          label: const Text('Join Game'),
        ),
        const SizedBox(height: 12),
        FloatingActionButton.extended(
          heroTag: 'create',
          onPressed: () {
            _handleCreateGame(context);
          },
          icon: const Icon(Icons.add),
          label: const Text('Create Game'),
        ),
      ],
    );
  }

  void _handleQuickPlay(BuildContext context) {
    final authRepository = sl<AuthRepository>();

    if (authRepository.isCurrentUserAnonymous()) {
      _showSignUpDialog(context, 'Quick Play');
    } else {
      context.read<GamesBloc>().add(const QuickPlayGame());
    }
  }

  void _handleCreateGame(BuildContext context) {
    final authRepository = sl<AuthRepository>();

    if (authRepository.isCurrentUserAnonymous()) {
      _showSignUpDialog(context, 'Create Game');
    } else {
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

  void _showSignUpDialog(BuildContext context, String feature) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Up Required'),
        content: Text(
          'You need to create an account to use $feature. '
          'Guests can join games using invite codes, but cannot create games.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RegisterScreen()),
              );
            },
            child: const Text('Sign Up'),
          ),
        ],
      ),
    );
  }
}