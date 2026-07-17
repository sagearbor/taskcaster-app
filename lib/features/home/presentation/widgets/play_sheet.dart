import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/services/ar/ar_games.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../games/presentation/bloc/games_bloc.dart';
import '../../../games/presentation/screens/create_game_screen.dart';
import '../../../games/presentation/screens/discover_games_screen.dart';
import '../../../games/presentation/screens/join_game_screen.dart';
import '../../../balloon_blitz/presentation/screens/balloon_blitz_start_screen.dart';
import '../../../telephone/presentation/screens/telephone_start_screen.dart';
import '../../../trivia/presentation/screens/trivia_start_screen.dart';
import '../../../treasure_hunt/treasure_hunt_screen.dart';
import '../../../house_hunt/presentation/screens/house_hunt_start_screen.dart';
import '../../../clue_hunt/presentation/screens/clue_hunt_start_screen.dart';

/// The single "▶ Play" entry point (Zone 3). Opens a bottom-sheet picker that
/// lists every way to start playing — one calm menu instead of nine competing
/// banners on the home screen.
///
/// [homeContext] must sit below the home [GamesBloc] and [AuthBloc] providers;
/// Quick Play / Balloon Pop (Solo) / Gem Rush dispatch to that bloc, and
/// Create / Join forward the auth bloc into the pushed route.
Future<void> showPlaySheet(BuildContext homeContext) {
  final gamesBloc = homeContext.read<GamesBloc>();
  final authBloc = homeContext.read<AuthBloc>();

  return showModalBottomSheet<void>(
    context: homeContext,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: _PlaySheetBody(
        gamesBloc: gamesBloc,
        authBloc: authBloc,
      ),
    ),
  );
}

class _PlaySheetBody extends StatelessWidget {
  const _PlaySheetBody({required this.gamesBloc, required this.authBloc});

  final GamesBloc gamesBloc;
  final AuthBloc authBloc;

  void _push(BuildContext context, Widget screen, {bool withAuth = false}) {
    Navigator.of(context).pop(); // close the sheet first
    final navigator = Navigator.of(context, rootNavigator: true);
    navigator.push(
      MaterialPageRoute(
        builder: (_) => withAuth
            ? BlocProvider.value(value: authBloc, child: screen)
            : screen,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Text(
            'Play',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        _PlayRow(
          icon: Icons.flash_on,
          color: AppTheme.coral,
          name: 'Quick Play',
          description: 'Jump into a game in seconds.',
          onTap: () {
            Navigator.of(context).pop();
            gamesBloc.add(const QuickPlayGame());
          },
        ),
        _PlayRow(
          icon: Icons.brush,
          color: AppTheme.violet,
          name: 'Drawing Telephone',
          description: 'Draw → guess → laugh across phones.',
          onTap: () => _push(context, const TelephoneStartScreen()),
        ),
        _PlayRow(
          icon: Icons.quiz,
          color: AppTheme.violet,
          name: 'Trivia Buzzer',
          description: 'Buzz in fast — fastest correct wins. Plays offline.',
          onTap: () => _push(context, const TriviaStartScreen()),
        ),
        _PlayRow(
          icon: Icons.celebration,
          color: AppTheme.gold,
          name: 'Balloon Pop',
          description: 'Pop balloons in AR — solo or race a room.',
          onTap: () => _openBalloonChooser(context),
        ),
        _PlayRow(
          icon: Icons.map,
          color: AppTheme.gold,
          name: '🗺️ Treasure Hunt',
          description: 'Hide treasures, pass the phone, hunt!',
          onTap: () => _push(context, const TreasureHuntScreen()),
        ),
        _PlayRow(
          icon: Icons.diamond,
          color: AppTheme.violet,
          name: '💎 Gem Rush',
          description: 'Tap gems fast — beat the clock, solo.',
          onTap: () {
            Navigator.of(context).pop();
            gamesBloc.add(
              const QuickPlayGame(arGameId: ArGameIds.treasureHunt),
            );
          },
        ),
        _PlayRow(
          icon: Icons.home_work_outlined,
          color: AppTheme.coral,
          name: '🏠 House Hunt',
          description: 'Send a treasure hunt to a faraway friend.',
          onTap: () => _push(context, const HouseHuntStartScreen()),
        ),
        _PlayRow(
          icon: Icons.search,
          color: AppTheme.gold,
          name: '🔍 Clue Hunt',
          description: 'Hide a real thing, drive the warmer-colder meter.',
          onTap: () => _push(context, const ClueHuntStartScreen()),
        ),
        _PlayRow(
          icon: Icons.add_circle_outline,
          color: AppTheme.coral,
          name: 'Create custom game',
          description: 'Build your own set of tasks for your crew.',
          onTap: () =>
              _push(context, const CreateGameScreen(), withAuth: true),
        ),
        _PlayRow(
          icon: Icons.public,
          color: AppTheme.violet,
          name: 'Discover',
          description: 'Browse community games and clone one.',
          onTap: () => _push(context, const DiscoverGamesScreen()),
        ),
        const Divider(height: 24),
        _PlayRow(
          icon: Icons.keyboard,
          color: AppTheme.inkSoft,
          name: 'Join with a code',
          description: 'Got a 6-character code? Enter it here.',
          onTap: () => _push(context, const JoinGameScreen(), withAuth: true),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  /// Balloon Pop merges the old "AR Games" (solo) and "Balloon Blitz"
  /// (multiplayer) entries. A tiny chooser routes to the right one, preserving
  /// each path's existing platform gating (Solo → AR quick-play, which shows
  /// the AR-unsupported view where needed; Multiplayer → the Blitz start
  /// screen, which gates on nearby/Android support).
  void _openBalloonChooser(BuildContext context) {
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    Navigator.of(context).pop(); // close the Play sheet
    showModalBottomSheet<void>(
      context: rootNavigator.context,
      showDragHandle: true,
      builder: (chooserContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
              child: Text('🎈 Balloon Pop',
                  style: Theme.of(chooserContext)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ),
            _PlayRow(
              icon: Icons.person_outline,
              color: AppTheme.coral,
              name: 'Solo',
              description: 'Pop at your pace.',
              onTap: () {
                Navigator.of(chooserContext).pop();
                gamesBloc.add(
                  const QuickPlayGame(arGameId: ArGameIds.balloonPop),
                );
              },
            ),
            _PlayRow(
              icon: Icons.groups,
              color: AppTheme.gold,
              name: 'Multiplayer race',
              description: 'Same room — race your family.',
              onTap: () {
                Navigator.of(chooserContext).pop();
                rootNavigator.push(
                  MaterialPageRoute(
                    builder: (_) => const BalloonBlitzStartScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// One row in the Play sheet: leading icon chip, name, one-line description.
class _PlayRow extends StatelessWidget {
  const _PlayRow({
    required this.icon,
    required this.color,
    required this.name,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String name;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(name,
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold)),
      subtitle: Text(description),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}
