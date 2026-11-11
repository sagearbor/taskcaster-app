import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/services/moderation/moderation_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';

/// Settings > Blocked players: everyone this account has blocked from the
/// Arena's "⋯" menu, each with an Unblock button.
class BlockedPlayersScreen extends StatefulWidget {
  const BlockedPlayersScreen({super.key, this.moderation, this.viewerId});

  /// Defaults to [ModerationService.fromLocator]; injectable for tests.
  final ModerationService? moderation;

  /// Defaults to the signed-in user on [AuthBloc].
  final String? viewerId;

  @override
  State<BlockedPlayersScreen> createState() => _BlockedPlayersScreenState();
}

class _BlockedPlayersScreenState extends State<BlockedPlayersScreen> {
  late final ModerationService _moderation;
  late final String _viewerId;
  StreamSubscription<void>? _sub;
  List<BlockedPlayer>? _players;

  @override
  void initState() {
    super.initState();
    _moderation = widget.moderation ?? ModerationService.fromLocator();
    _viewerId = widget.viewerId ?? _authUid();
    _sub = _moderation.changes.listen((_) => _refresh());
    _moderation.load(_viewerId).whenComplete(_refresh);
  }

  String _authUid() {
    try {
      final auth = context.read<AuthBloc>().state;
      return auth is AuthAuthenticated ? auth.user.id : '';
    } catch (_) {
      return '';
    }
  }

  Future<void> _refresh() async {
    final players = await _moderation.blockedPlayers();
    if (mounted) setState(() => _players = players);
  }

  Future<void> _unblock(BlockedPlayer player) async {
    final messenger = ScaffoldMessenger.of(context);
    final write = _moderation.unblock(player.key, uid: _viewerId);
    messenger.showSnackBar(
      SnackBar(content: Text('${player.displayName} is unblocked.')),
    );
    try {
      await write;
    } catch (e) {
      debugPrint('Unblock of ${player.key} not saved to the account: $e');
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final players = _players;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Blocked players')),
      body: players == null
          ? const Center(child: CircularProgressIndicator())
          : players.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.block_rounded,
                            size: 56, color: AppTheme.violet),
                        const SizedBox(height: 16),
                        Text(
                          'You haven\'t blocked anyone.',
                          key: const Key('blocked-players-empty'),
                          style: theme.textTheme.titleMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Use the ⋯ menu on an Arena post to block a player.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: Column(
                        children: [
                          for (final (i, player) in players.indexed) ...[
                            if (i > 0) const Divider(height: 1),
                            ListTile(
                              key: ValueKey('blocked-${player.key}'),
                              leading: const Icon(Icons.person_off_outlined,
                                  color: AppTheme.violet),
                              title: Text(player.displayName),
                              trailing: TextButton(
                                key: ValueKey('unblock-${player.key}'),
                                onPressed: () => _unblock(player),
                                child: const Text('Unblock'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}
