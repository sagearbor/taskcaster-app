import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/models/game.dart';
import '../../../../core/models/task.dart';
import '../../../../core/utils/friendly_errors.dart';
import '../../../../core/utils/link_utils.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../community/presentation/screens/community_browser_screen.dart';
import '../../domain/repositories/game_repository.dart';
import '../bloc/game_detail_bloc.dart';

class GameLobbyView extends StatelessWidget {
  final Game game;

  const GameLobbyView({
    super.key,
    required this.game,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, authState) {
        if (authState is! AuthAuthenticated) {
          return const Center(child: Text('Authentication required'));
        }

        final currentUser = authState.user;
        final isCreator = game.isUserCreator(currentUser.id);

        return Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Game Status Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.secondary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.people,
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Waiting for players',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '${game.players.length} player${game.players.length == 1 ? '' : 's'} joined',
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      InkWell(
                        onTap: () => LinkUtils.copyToClipboard(
                          context,
                          game.inviteCode,
                          label: 'Invite code copied',
                        ),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Invite Code: ',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              Text(
                                game.inviteCode,
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 2,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                Icons.copy,
                                size: 18,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Players List
              Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Players (${game.players.length})',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (game.players.isEmpty)
                          SizedBox(
                            height: 140,
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.group_add,
                                    size: 48,
                                    color: Colors.grey[400],
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No players yet',
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Share the invite code to get started!',
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: Colors.grey[500],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: game.players.length,
                              itemBuilder: (context, index) {
                                final player = game.players[index];
                                final isCurrentUser = player.userId == currentUser.id;
                                final isPlayerJudge = game.judgeId == player.userId;
                                final isPlayerCreator = game.creatorId == player.userId;

                                return ListTile(
                                  leading: UserAvatar(
                                    displayName: player.displayName,
                                    radius: 20,
                                    borderColor: isCurrentUser
                                        ? Theme.of(context).colorScheme.primary
                                        : null,
                                  ),
                                  title: Text(
                                    player.displayName,
                                    style: TextStyle(
                                      fontWeight: isCurrentUser ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                  subtitle: Row(
                                    children: [
                                      if (isPlayerCreator) ...[
                                        Icon(Icons.star, size: 16, color: Colors.amber[700]),
                                        const SizedBox(width: 4),
                                        Text('Creator', style: TextStyle(color: Colors.amber[700])),
                                      ],
                                      if (isPlayerJudge) ...[
                                        if (isPlayerCreator) const SizedBox(width: 8),
                                        Icon(Icons.gavel, size: 16, color: Colors.purple[200]),
                                        const SizedBox(width: 4),
                                        Text('Judge', style: TextStyle(color: Colors.purple[200])),
                                      ],
                                      if (isCurrentUser && !isPlayerCreator && !isPlayerJudge) ...[
                                        Icon(Icons.person, size: 16, color: Colors.blue[300]),
                                        const SizedBox(width: 4),
                                        Text('You', style: TextStyle(color: Colors.blue[300])),
                                      ],
                                    ],
                                  ),
                                  trailing: isCurrentUser 
                                      ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary)
                                      : null,
                                );
                              },
                            ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),

              // Tasks Section
              if (game.tasks.isNotEmpty) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.assignment,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Tasks (${game.tasks.length})',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ...game.tasks.asMap().entries.map((entry) {
                          final index = entry.key;
                          final task = entry.value;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${index + 1}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        task.title,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (task.description.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          task.description,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Action Buttons
              if (isCreator) ...[
                _InviteByEmailCard(game: game),
                const SizedBox(height: 8),
                Card(
                  child: SwitchListTile(
                    secondary: const Icon(Icons.public),
                    title: const Text('Make game public'),
                    subtitle: const Text(
                        'Discoverable in the gallery so others can play your tasks'),
                    value: game.isPublic,
                    onChanged: (value) {
                      sl<GameRepository>().updateGame(
                        game.id,
                        game.copyWith(isPublic: value),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () => _showCreateTaskDialog(context, game),
                  icon: const Icon(Icons.edit_note),
                  label: const Text('Create your own task'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            CommunityBrowserScreen(targetGameId: game.id),
                      ),
                    );
                  },
                  icon: const Icon(Icons.playlist_add),
                  label: const Text('Browse community tasks'),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: game.players.length >= 2 && game.tasks.isNotEmpty
                      ? () {
                          context.read<GameDetailBloc>().add(StartGame(gameId: game.id));
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(
                    'Start Game',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  game.players.length < 2
                      ? 'Need at least 2 players to start'
                      : game.tasks.isEmpty
                          ? 'Need to add tasks before starting'
                          : 'Ready to start! (${game.tasks.length} task${game.tasks.length == 1 ? '' : 's'}, ${game.players.length} player${game.players.length == 1 ? '' : 's'})',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: game.players.length >= 2 && game.tasks.isNotEmpty
                        ? Colors.green[300]
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.schedule, color: Colors.blue[200]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Waiting for the game creator to start the game...',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.blue[200],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          ),
        );
      },
    );
  }

  /// Let the creator write a custom task that goes straight into THIS game
  /// (group-specific) — no community submission required.
  void _showCreateTaskDialog(BuildContext context, Game game) {
    final titleController = TextEditingController();
    final descController = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    // Captured before the async gap so the catch below doesn't use a
    // possibly-stale context.
    final errorColor = Theme.of(context).colorScheme.error;
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Create a task'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Task title',
                    hintText: 'e.g. Best slow-motion entrance',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descController,
                  textCapitalization: TextCapitalization.sentences,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    hintText: 'What should players do?',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final title = titleController.text.trim();
                final desc = descController.text.trim();
                if (title.isEmpty) return;
                Navigator.of(dialogContext).pop();
                try {
                  await sl<GameRepository>().addTasksToGame(game.id, [
                    Task(
                      id: 'custom_${DateTime.now().microsecondsSinceEpoch}',
                      title: title,
                      description: desc.isEmpty
                          ? 'Record a video completing this task.'
                          : desc,
                      taskType: TaskType.video,
                      submissions: const [],
                    ),
                  ]);
                  messenger.showSnackBar(
                    SnackBar(content: Text('Added "$title" to your game')),
                  );
                } catch (e) {
                  debugPrint('Add custom task failed: $e');
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(FriendlyErrors.action(
                        e,
                        fallback: 'Could not add the task. Please try again.',
                      )),
                      backgroundColor: errorColor,
                    ),
                  );
                }
              },
              child: const Text('Add task'),
            ),
          ],
        );
      },
    ).then((_) {
      titleController.dispose();
      descController.dispose();
    });
  }
}

/// Creator-only card for inviting specific people by email. The lowercased
/// email is appended to the game's `invitedEmails` (deduped) and saved via
/// [GameRepository.updateGame]. Invited people then see this game under
/// "Invites for you" on the Join screen — no invite code needed.
class _InviteByEmailCard extends StatefulWidget {
  final Game game;

  const _InviteByEmailCard({required this.game});

  @override
  State<_InviteByEmailCard> createState() => _InviteByEmailCardState();
}

class _InviteByEmailCardState extends State<_InviteByEmailCard> {
  final _controller = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _looksLikeEmail(String value) {
    // Deliberately lenient: "x@y" passes. We only store the address, so we just
    // guard against obvious non-emails rather than enforce RFC-perfect syntax.
    return RegExp(r'^[^@\s]+@[^@\s]+\.?[^@\s]*$').hasMatch(value);
  }

  Future<void> _addInvite() async {
    final email = _controller.text.trim().toLowerCase();
    final messenger = ScaffoldMessenger.of(context);
    // Captured before the async gap so the catch below doesn't use a
    // possibly-stale context.
    final errorColor = Theme.of(context).colorScheme.error;
    if (email.isEmpty) return;
    if (!_looksLikeEmail(email)) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Please enter a valid email address')),
      );
      return;
    }
    if (widget.game.invitedEmails.contains(email)) {
      messenger.showSnackBar(
        SnackBar(content: Text('$email is already invited')),
      );
      _controller.clear();
      return;
    }

    setState(() => _saving = true);
    try {
      await sl<GameRepository>().updateGame(
        widget.game.id,
        widget.game.copyWith(
          invitedEmails: [...widget.game.invitedEmails, email],
        ),
      );
      if (mounted) {
        _controller.clear();
        messenger.showSnackBar(
          SnackBar(content: Text('Invited $email')),
        );
      }
    } catch (e) {
      debugPrint('Invite by email failed: $e');
      messenger.showSnackBar(
        SnackBar(
          content: Text(FriendlyErrors.action(
            e,
            fallback: 'Could not send the invite. Please try again.',
          )),
          backgroundColor: errorColor,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removeInvite(String email) async {
    try {
      await sl<GameRepository>().updateGame(
        widget.game.id,
        widget.game.copyWith(
          invitedEmails:
              widget.game.invitedEmails.where((e) => e != email).toList(),
        ),
      );
    } catch (_) {
      // Best-effort; the live game stream will reconcile the displayed list.
    }
  }

  @override
  Widget build(BuildContext context) {
    final invited = widget.game.invitedEmails;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.mail_outline,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Invite by email',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'They\'ll see this game under "Invites for you" — no code needed.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    enabled: !_saving,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Email address',
                      hintText: 'friend@example.com',
                      prefixIcon: Icon(Icons.alternate_email),
                    ),
                    onSubmitted: (_) => _addInvite(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _saving ? null : _addInvite,
                  child: _saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Add'),
                ),
              ],
            ),
            if (invited.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Invited (${invited.length})',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: invited
                    .map(
                      (email) => Chip(
                        label: Text(email),
                        onDeleted: () => _removeInvite(email),
                        deleteIcon: const Icon(Icons.close, size: 16),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}