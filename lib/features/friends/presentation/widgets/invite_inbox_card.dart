import 'package:flutter/material.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/utils/friendly_errors.dart';
import '../../../games/presentation/screens/game_detail_screen.dart';
import '../../domain/models/invite.dart';
import '../../domain/repositories/invites_repository.dart';

/// Self-contained, home-ready card that streams the current user's pending
/// invites and renders a "🎈 {inviter} invited you to {game}" row for each,
/// with a [Join] button (accept → open the game) and a subtle dismiss
/// (decline). Renders nothing when there are no pending invites, so it is safe
/// to drop into any list/column.
///
/// Home integration: `const InviteInboxCard()` — no constructor arguments.
class InviteInboxCard extends StatelessWidget {
  const InviteInboxCard({super.key});

  @override
  Widget build(BuildContext context) {
    final invites = sl<InvitesRepository>();
    return StreamBuilder<List<Invite>>(
      stream: invites.watchMyInvites(),
      builder: (context, snapshot) {
        final pending = snapshot.data ?? const <Invite>[];
        if (pending.isEmpty) return const SizedBox.shrink();

        final theme = Theme.of(context);
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 4),
                  child: Text(
                    pending.length == 1
                        ? 'You have an invite'
                        : 'You have ${pending.length} invites',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                ...pending.map((invite) => _InviteRow(invite: invite)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _InviteRow extends StatefulWidget {
  final Invite invite;

  const _InviteRow({required this.invite});

  @override
  State<_InviteRow> createState() => _InviteRowState();
}

class _InviteRowState extends State<_InviteRow> {
  bool _busy = false;

  Future<void> _join() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      final gameId = await sl<InvitesRepository>().accept(widget.invite);
      if (!mounted) return;
      navigator.push(
        MaterialPageRoute(
          builder: (_) => GameDetailScreen(gameId: gameId),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(FriendlyErrors.action(
            e,
            fallback: 'Could not join that game. It may have ended.',
          )),
        ),
      );
    }
  }

  Future<void> _decline() async {
    setState(() => _busy = true);
    try {
      await sl<InvitesRepository>().decline(widget.invite);
      // The stream drops this row on success; nothing else to do.
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final invite = widget.invite;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: const Text('🎈', style: TextStyle(fontSize: 26)),
      title: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: invite.inviterName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const TextSpan(text: ' invited you to '),
            TextSpan(
              text: invite.gameName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        style: theme.textTheme.bodyMedium,
      ),
      trailing: _busy
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Dismiss',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close),
                  color: theme.colorScheme.onSurfaceVariant,
                  onPressed: _decline,
                ),
                FilledButton(
                  onPressed: _join,
                  child: const Text('Join'),
                ),
              ],
            ),
    );
  }
}
