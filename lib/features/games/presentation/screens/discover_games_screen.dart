import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/models/game.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/repositories/game_repository.dart';
import 'game_detail_screen.dart';

/// Public games gallery — discover games other people have shared and clone
/// their task list into a fresh game you own ("Play these tasks").
class DiscoverGamesScreen extends StatelessWidget {
  const DiscoverGamesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Discover Games')),
      body: StreamBuilder<List<Game>>(
        stream: sl<GameRepository>().getPublicGamesStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('Could not load public games'));
          }
          final games = snapshot.data ?? const [];
          if (games.isEmpty) {
            return _buildEmpty(context);
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: games.length,
            itemBuilder: (context, i) => _PublicGameCard(game: games[i]),
          );
        },
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.public_off, size: 56, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text('No public games yet',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Add a few ready-made games to get the community started, '
              'or make one of your own games public.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => _seedStarter(context),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Load starter games'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _seedStarter(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Sign in to add starter games')),
      );
      return;
    }
    messenger.showSnackBar(
      const SnackBar(content: Text('Adding starter games…')),
    );
    try {
      await sl<GameRepository>().seedStarterPublicGames(
        authState.user.id,
        authState.user.displayName,
      );
    } catch (e) {
      debugPrint('Seed starter games failed: $e');
      messenger.showSnackBar(
        const SnackBar(
            content: Text('Could not add the starter games. Please try again.')),
      );
    }
  }
}

class _PublicGameCard extends StatelessWidget {
  final Game game;

  const _PublicGameCard({required this.game});

  Future<void> _clone(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Sign in to play these tasks')),
      );
      return;
    }
    try {
      final newId = await sl<GameRepository>().cloneGame(
        game,
        authState.user.id,
        authState.user.displayName,
      );
      // Navigating into the fresh game is the confirmation — no snackbar
      // needed (and avoids a floating snackbar racing the route transition).
      navigator.push(
        MaterialPageRoute(builder: (_) => GameDetailScreen(gameId: newId)),
      );
    } catch (e) {
      debugPrint('Clone public game failed: $e');
      messenger.showSnackBar(
        const SnackBar(
            content: Text('Could not set up the game. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(game.gameName,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ),
                if (game.cloneCount >= 3)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('🔥 Popular',
                        style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.assignment,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text('${game.tasks.length} task${game.tasks.length == 1 ? '' : 's'}',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(width: 12),
                Icon(Icons.group,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text('${game.players.length}',
                    style: Theme.of(context).textTheme.bodySmall),
                if (game.cloneCount > 0) ...[
                  const SizedBox(width: 12),
                  Icon(Icons.copy,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text('played ${game.cloneCount}×',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _clone(context),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Play these tasks'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
