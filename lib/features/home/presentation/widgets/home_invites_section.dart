import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/models/game.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../games/domain/repositories/game_repository.dart';
import '../../../games/presentation/screens/game_detail_screen.dart';
import '../../../games/presentation/screens/join_game_screen.dart';

/// Zone 1 of the home screen: "Invites from friends".
///
/// A self-contained, one-widget slot that surfaces the games the current user
/// has been invited to (by email) with a one-tap Join on each. Relocated out of
/// [JoinGameScreen] so the very first thing an invited kid/grandparent sees on
/// opening the app is the invite they were sent.
///
/// SEAM: this whole section is intentionally one drop-in widget. A follow-up
/// will swap or augment it with the richer `InviteInboxCard` from
/// `lib/features/friends/` without touching the rest of home.
class HomeInvitesSection extends StatefulWidget {
  const HomeInvitesSection({super.key});

  @override
  State<HomeInvitesSection> createState() => _HomeInvitesSectionState();
}

class _HomeInvitesSectionState extends State<HomeInvitesSection> {
  // Id of the invited game currently being joined (drives a per-row spinner so
  // tapping one "Join" doesn't grey out the whole list).
  String? _joiningInviteId;

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
        Navigator.of(context).push(
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

  String _friendlyJoinError(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('not found') || text.contains('no game')) {
      return 'We couldn\'t find that game. Ask your friend to invite you again.';
    }
    return 'Couldn\'t join the game. Please try again.';
  }

  void _openCodeEntry() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BlocProvider.value(
          value: context.read<AuthBloc>(),
          child: const JoinGameScreen(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    final email =
        authState is AuthAuthenticated ? authState.user.email : null;

    final header = Row(
      children: [
        Icon(Icons.mark_email_unread_outlined,
            color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          'Invites from friends',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );

    // Guests (no email) can't receive email invites — show the calm empty
    // state with the "Enter a code" escape hatch.
    if (email == null || email.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [header, const SizedBox(height: 12), _emptyState(context)],
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
              _emptyState(context)
            else
              ...games.map((game) => _buildInviteCard(context, game)),
          ],
        );
      },
    );
  }

  /// Calm empty state: no red-flag messaging, just a gentle nudge and a
  /// low-key "Enter a code" path for kids who were handed a code verbally.
  Widget _emptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.inbox_outlined,
              size: 36, color: theme.colorScheme.primary),
          const SizedBox(height: 8),
          Text(
            'No invites yet — ask a friend to invite you.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: _openCodeEntry,
            icon: const Icon(Icons.keyboard, size: 18),
            label: const Text('Enter a code'),
          ),
        ],
      ),
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
