import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/services/invite/pending_invite_service.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/repositories/game_repository.dart';
import '../screens/game_detail_screen.dart';

/// Watches [PendingInviteService] and, when an invite code has arrived via
/// deep link or Play Install Referrer, pops a "join your friend's game?"
/// dialog over [child]. Mount this only where the user is authenticated so
/// joining always has a real user id (anonymous/guest users included).
class PendingInviteGate extends StatefulWidget {
  final Widget child;

  const PendingInviteGate({super.key, required this.child});

  @override
  State<PendingInviteGate> createState() => _PendingInviteGateState();
}

class _PendingInviteGateState extends State<PendingInviteGate> {
  late final PendingInviteService _invites;
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    _invites = sl<PendingInviteService>();
    _invites.addListener(_onInviteMaybeAvailable);
    // A cold-start link/referrer may already be pending before we mounted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onInviteMaybeAvailable();
    });
  }

  @override
  void dispose() {
    _invites.removeListener(_onInviteMaybeAvailable);
    super.dispose();
  }

  void _onInviteMaybeAvailable() {
    if (!mounted || _dialogOpen || _invites.pendingCode == null) return;
    // Defer to after the current frame: notifyListeners can fire mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _dialogOpen) return;
      final code = _invites.consume();
      if (code == null) return;
      _dialogOpen = true;
      showDialog<void>(
        context: context,
        builder: (_) => _JoinInviteDialog(code: code, hostContext: context),
      ).whenComplete(() {
        _dialogOpen = false;
        // Another link may have arrived while the dialog was up.
        _onInviteMaybeAvailable();
      });
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The invite popup itself: shows the code, joins on confirm, and turns any
/// failure into a friendly in-dialog error (never a raw exception).
class _JoinInviteDialog extends StatefulWidget {
  final String code;

  /// Context of the gate (survives this dialog being popped) used to navigate
  /// into the joined game.
  final BuildContext hostContext;

  const _JoinInviteDialog({required this.code, required this.hostContext});

  @override
  State<_JoinInviteDialog> createState() => _JoinInviteDialogState();
}

class _JoinInviteDialogState extends State<_JoinInviteDialog> {
  bool _joining = false;
  String? _error;

  Future<void> _join() async {
    final authState = widget.hostContext.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      // The gate is only mounted when authenticated; this is a belt-and-braces
      // guard for a sign-out racing the dialog.
      setState(() => _error = 'Please sign in, then enter code '
          '${widget.code} on the Join Game screen.');
      return;
    }
    final displayName = authState.user.displayName.trim().isEmpty
        ? 'Guest'
        : authState.user.displayName;

    setState(() {
      _joining = true;
      _error = null;
    });

    // Captured before the async gap: this navigator outlives the dialog.
    final hostNavigator = Navigator.of(widget.hostContext);

    try {
      final gameId = await sl<GameRepository>().joinGame(
        widget.code,
        authState.user.id,
        displayName,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      hostNavigator.push(
        MaterialPageRoute(
          builder: (_) => GameDetailScreen(gameId: gameId),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final text = e.toString().toLowerCase();
      setState(() {
        _joining = false;
        _error = text.contains('not found') || text.contains('no game')
            ? 'That game has ended or the code is wrong.'
            : 'Couldn\'t join right now. Check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('🎉 You\'re invited!'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Join your friend\'s game?'),
          const SizedBox(height: 16),
          Center(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.primary.withOpacity(0.4),
                ),
              ),
              child: Text(
                widget.code,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline,
                    size: 20, color: theme.colorScheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _error!,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _joining ? null : () => Navigator.of(context).pop(),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: _joining ? null : _join,
          child: _joining
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_error == null ? 'Join game' : 'Try again'),
        ),
      ],
    );
  }
}
