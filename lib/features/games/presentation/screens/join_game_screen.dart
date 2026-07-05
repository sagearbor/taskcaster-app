import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/models/game.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/six_char_code_field.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/repositories/game_repository.dart';
import 'game_detail_screen.dart';

class JoinGameScreen extends StatefulWidget {
  const JoinGameScreen({super.key});

  @override
  State<JoinGameScreen> createState() => _JoinGameScreenState();
}

class _JoinGameScreenState extends State<JoinGameScreen> {
  final _inviteCodeController = TextEditingController();
  bool _isLoading = false;
  // Id of the invited game currently being joined (drives a per-row spinner so
  // tapping one "Join" doesn't grey out the whole list).
  String? _joiningInviteId;

  @override
  void dispose() {
    _inviteCodeController.dispose();
    super.dispose();
  }

  Future<void> _joinGame() async {
    // The six-cell field enforces shape (uppercase letters+digits); only the
    // length can still be short here.
    if (_inviteCodeController.text.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the 6-character invite code')),
      );
      return;
    }

    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('You must be logged in to join a game'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final gameRepository = sl<GameRepository>();
      final gameId = await gameRepository.joinGame(
        _inviteCodeController.text.trim().toUpperCase(),
        authState.user.id,
        authState.user.displayName,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You\'re in! 🎉 Welcome to the game.')),
        );
        // Drop the player straight into the game lobby they just joined,
        // replacing this screen so "back" returns home rather than here.
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => GameDetailScreen(gameId: gameId),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_friendlyJoinError(e)),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Join a game the user was specifically invited to. Reuses the same
  /// [GameRepository.joinGame] flow as the manual code path (it adds the player
  /// to the roster), then drops them into that game's lobby.
  Future<void> _joinInvitedGame(Game game) async {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;

    setState(() => _joiningInviteId = game.id);
    try {
      final gameId = await sl<GameRepository>().joinGame(
        game.inviteCode,
        authState.user.id,
        authState.user.displayName,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('You\'re in! 🎉 Welcome to ${game.gameName}.')),
        );
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => GameDetailScreen(gameId: gameId),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_friendlyJoinError(e)),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _joiningInviteId = null);
    }
  }

  /// Compact recency label from the game's creation time. We don't store a
  /// per-invite timestamp, so the honest thing to show is when the game was
  /// created — never claim it's when the invite was sent.
  String _createdAgo(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  /// Turn a raw thrown error into something friendly. A wrong/expired code
  /// surfaces as an "Exception: Game not found ..." string from the data layer;
  /// players should never see that.
  String _friendlyJoinError(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('not found') || text.contains('no game')) {
      return 'We couldn\'t find a game with that code. Double-check it and try again.';
    }
    return 'Couldn\'t join the game. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    final email =
        authState is AuthAuthenticated ? authState.user.email : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Join Game'),
      ),
      body: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Join the Fun!',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Tap an invite below, or enter a code to join a game',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppTheme.inkSoft,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              _buildInvitesSection(context, email),
              const SizedBox(height: 32),
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'Or enter a code',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.inkSoft,
                          ),
                    ),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 24),
              // Six boxed cells: auto-uppercase, paste-aware (codes AND full
              // invite links), auto-submits when the 6th character lands.
              SixCharCodeField(
                controller: _inviteCodeController,
                enabled: !_isLoading,
                onCompleted: (_) => _joinGame(),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.gold.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.gold.withOpacity(0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.lightbulb_outline, color: AppTheme.gold),
                        const SizedBox(width: 8),
                        Text(
                          'Need an invite code?',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.gold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Ask the game creator for the 6-character invite code. You can find it on their game lobby screen.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        // Theme-aware so it stays readable in dark mode
                        // (was hardcoded dark AppTheme.ink → invisible on dark).
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _joinGame,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Join Game'),
              ),
            ],
          ),
      ),
    );
  }

  /// "Invites for you": a live list of lobby games the current user has been
  /// invited to (newest first), each with a one-tap Join. Falls back to a
  /// friendly empty state when there are none.
  Widget _buildInvitesSection(BuildContext context, String? email) {
    final header = Row(
      children: [
        Icon(Icons.mark_email_unread_outlined,
            color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          'Invites for you',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );

    Widget emptyState() => Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.06),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Icon(Icons.inbox_outlined,
                  size: 36, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 8),
              Text(
                'No invites yet — ask for a code.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
              ),
            ],
          ),
        );

    if (email == null || email.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [header, const SizedBox(height: 12), emptyState()],
      );
    }

    return StreamBuilder<List<Game>>(
      stream: sl<GameRepository>().getInvitedGamesStream(email),
      builder: (context, snapshot) {
        final games = snapshot.data ?? const <Game>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header,
            const SizedBox(height: 12),
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (games.isEmpty)
              emptyState()
            else
              ...games.map((game) => _buildInviteCard(context, game)),
          ],
        );
      },
    );
  }

  Widget _buildInviteCard(BuildContext context, Game game) {
    final creator = game.getPlayerById(game.creatorId)?.displayName;
    final isJoining = _joiningInviteId == game.id;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    game.gameName,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${creator != null ? 'From $creator · ' : ''}created ${_createdAgo(game.createdAt)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: isJoining ? null : () => _joinInvitedGame(game),
              child: isJoining
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Join'),
            ),
          ],
        ),
      ),
    );
  }
}