import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/six_char_code_field.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/repositories/game_repository.dart';
import 'game_detail_screen.dart';

/// Code-entry screen: type (or paste) a 6-character invite code to join a
/// game. The list of invites a player was emailed now lives at the top of the
/// home screen ([HomeInvitesSection]); this screen is the manual "I have a
/// code" path, reached from that section's empty state and from the Play
/// sheet's "Join with a code" row.
class JoinGameScreen extends StatefulWidget {
  const JoinGameScreen({super.key});

  @override
  State<JoinGameScreen> createState() => _JoinGameScreenState();
}

class _JoinGameScreenState extends State<JoinGameScreen> {
  final _inviteCodeController = TextEditingController();
  bool _isLoading = false;

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Enter a code'),
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
              'Enter the 6-character code a friend shared with you.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppTheme.inkSoft,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
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
                        style:
                            Theme.of(context).textTheme.titleSmall?.copyWith(
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
}
