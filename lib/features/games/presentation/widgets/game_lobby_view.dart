import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/models/game.dart';
import '../../../../core/models/task.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/friendly_errors.dart';
import '../../../../core/utils/link_utils.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../community/presentation/screens/community_browser_screen.dart';
import '../../../friends/domain/models/friend.dart';
import '../../../friends/domain/repositories/friends_repository.dart';
import '../../../friends/domain/repositories/invites_repository.dart';
import '../../domain/repositories/game_repository.dart';
import '../bloc/game_detail_bloc.dart';

class GameLobbyView extends StatelessWidget {
  final Game game;

  /// Opens the invite / share sheet. Null hides nothing — the hero then falls
  /// back to copying the invite code.
  final VoidCallback? onInvite;

  const GameLobbyView({
    super.key,
    required this.game,
    this.onInvite,
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
              _LobbyHero(
                game: game,
                isCreator: isCreator,
                onInvite: onInvite,
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
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
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
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
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
                                        Icon(Icons.star_rounded, size: 16, color: context.tokens.goldText),
                                        const SizedBox(width: 4),
                                        Text('Creator', style: TextStyle(color: context.tokens.goldText)),
                                      ],
                                      if (isPlayerJudge) ...[
                                        if (isPlayerCreator) const SizedBox(width: 8),
                                        Icon(Icons.gavel, size: 16, color: Theme.of(context).colorScheme.primary),
                                        const SizedBox(width: 4),
                                        Text('Judge', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                                      ],
                                      if (isCurrentUser && !isPlayerCreator && !isPlayerJudge) ...[
                                        Icon(Icons.person, size: 16, color: Theme.of(context).colorScheme.primary),
                                        const SizedBox(width: 4),
                                        Text('You', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
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
                _InviteFriendsCard(game: game),
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
                OutlinedButton.icon(
                  onPressed: () => _showCreateTaskDialog(context, game),
                  icon: const Icon(Icons.edit_note),
                  label: const Text('Write your own task'),
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

/// Lobby hero: the invite code front and centre and exactly one button —
/// "Start game" once the creator has a crew and tasks, otherwise "Invite
/// friends" (or "Add tasks" when the game has none yet).
class _LobbyHero extends StatelessWidget {
  final Game game;
  final bool isCreator;
  final VoidCallback? onInvite;

  const _LobbyHero({
    required this.game,
    required this.isCreator,
    this.onInvite,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final players = game.players.length;
    final needPlayers = players < 2;
    final needTasks = game.tasks.isEmpty;
    final canStart = isCreator && !needPlayers && !needTasks;

    final String kicker;
    final String title;
    final String detail;
    if (!isCreator) {
      final creator = game.players
          .where((p) => p.userId == game.creatorId)
          .map((p) => p.displayName)
          .firstOrNull;
      kicker = 'YOU\'RE IN';
      title = 'Waiting for ${creator ?? 'the host'} to start';
      detail = '$players player${players == 1 ? '' : 's'} in the lobby';
    } else if (needPlayers) {
      kicker = 'INVITE YOUR CREW';
      title = 'You need one more player';
      detail = 'Send the link or read out the code.';
    } else if (needTasks) {
      kicker = 'ALMOST THERE';
      title = 'Add a task or two';
      detail = '$players players are ready.';
    } else {
      kicker = 'READY WHEN YOU ARE';
      title = '$players players, ${game.tasks.length} tasks';
      detail = 'Late joiners can still use the code.';
    }

    final String buttonLabel;
    final IconData buttonIcon;
    final VoidCallback? onPressed;
    if (canStart) {
      buttonLabel = 'Start game';
      buttonIcon = Icons.play_arrow_rounded;
      onPressed = () =>
          context.read<GameDetailBloc>().add(StartGame(gameId: game.id));
    } else if (isCreator && !needPlayers && needTasks) {
      buttonLabel = 'Add tasks';
      buttonIcon = Icons.playlist_add;
      onPressed = () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CommunityBrowserScreen(targetGameId: game.id),
            ),
          );
    } else {
      buttonLabel = 'Invite friends';
      buttonIcon = Icons.ios_share_rounded;
      onPressed = onInvite ??
          () => LinkUtils.copyToClipboard(
                context,
                game.inviteCode,
                label: 'Invite code copied',
              );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: tokens.heroGradient,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              kicker,
              style: theme.textTheme.labelMedium?.copyWith(
                color: tokens.onHero,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(color: tokens.onHero, height: 1.15),
            ),
            const SizedBox(height: 4),
            Text(
              detail,
              style:
                  theme.textTheme.bodyMedium?.copyWith(color: tokens.onHeroMuted),
            ),
            const SizedBox(height: 16),
            // Invite code: tap to copy.
            Material(
              color: tokens.onHero.withOpacity(0.16),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => LinkUtils.copyToClipboard(
                  context,
                  game.inviteCode,
                  label: 'Invite code copied',
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      Text(
                        'CODE',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: tokens.onHeroMuted,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          game.inviteCode,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: tokens.onHero,
                            letterSpacing: 4,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      Icon(Icons.copy_rounded, size: 18, color: tokens.onHero),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('lobby-hero-button'),
                onPressed: onPressed,
                icon: Icon(buttonIcon),
                label: Text(buttonLabel),
                style: FilledButton.styleFrom(
                  backgroundColor: tokens.onHero,
                  foregroundColor: AppTheme.violetDeep,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Creator-only "Invite friends" card. Top: one-tap chips for people you've
/// played with (from [FriendsRepository.watchFriends]) — a tap fires a real
/// [InvitesRepository.sendToFriend] and flips the chip to "Invited ✓". Below:
/// an email field that writes a REAL invite via [InvitesRepository.sendToEmail]
/// AND appends to the legacy `invitedEmails` array (so "Invites for you" on the
/// Join screen keeps working), plus the existing invited-email chips.
class _InviteFriendsCard extends StatefulWidget {
  final Game game;

  const _InviteFriendsCard({required this.game});

  @override
  State<_InviteFriendsCard> createState() => _InviteFriendsCardState();
}

class _InviteFriendsCardState extends State<_InviteFriendsCard> {
  final _controller = TextEditingController();
  bool _saving = false;

  /// Friend uids we've already invited this session (drives the "Invited ✓"
  /// chip state without waiting for a round-trip).
  final Set<String> _invitedFriendUids = {};

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

  /// Uids already on the game roster — those friends can't be re-invited.
  Set<String> get _playerUids =>
      widget.game.players.map((p) => p.userId).toSet();

  Future<void> _inviteFriend(Friend friend) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _invitedFriendUids.add(friend.uid));
    try {
      await sl<InvitesRepository>().sendToFriend(friend.uid, widget.game);
      messenger.showSnackBar(
        SnackBar(content: Text('Invited ${friend.displayName}')),
      );
    } catch (e) {
      debugPrint('Invite friend failed: $e');
      if (mounted) setState(() => _invitedFriendUids.remove(friend.uid));
      messenger.showSnackBar(
        SnackBar(
          content: Text(FriendlyErrors.action(
            e,
            fallback: 'Could not invite ${friend.displayName}. Try again.',
          )),
        ),
      );
    }
  }

  Future<void> _addEmailInvite() async {
    final email = _controller.text.trim().toLowerCase();
    final messenger = ScaffoldMessenger.of(context);
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
      // Real invite record (surfaces in their inbox once they sign in)...
      await sl<InvitesRepository>().sendToEmail(email, widget.game);
      // ...plus the legacy invitedEmails array powering "Invites for you".
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

  Future<void> _removeEmailInvite(String email) async {
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
    final theme = Theme.of(context);
    final invited = widget.game.invitedEmails;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.group_add, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Invite friends',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Tap a friend to invite them instantly — no code needed.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),

            // Friend chips.
            StreamBuilder<List<Friend>>(
              stream: sl<FriendsRepository>().watchFriends(),
              builder: (context, snapshot) {
                final friends = snapshot.data ?? const <Friend>[];
                if (friends.isEmpty) {
                  return Text(
                    'No friends yet — play a game together and they\'ll show up '
                    'here. You can still invite by email below.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  );
                }
                return Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: friends.map((friend) {
                    final alreadyInGame = _playerUids.contains(friend.uid);
                    final invitedThisSession =
                        _invitedFriendUids.contains(friend.uid);
                    final done = alreadyInGame || invitedThisSession;
                    return ActionChip(
                      avatar: done
                          ? const Icon(Icons.check, size: 18)
                          : UserAvatar(
                              displayName: friend.displayName,
                              avatarEmoji: friend.avatarEmoji,
                              radius: 12,
                            ),
                      label: Text(
                        alreadyInGame
                            ? '${friend.displayName} (joined)'
                            : invitedThisSession
                                ? '${friend.displayName} ✓'
                                : friend.displayName,
                      ),
                      onPressed:
                          done ? null : () => _inviteFriend(friend),
                    );
                  }).toList(),
                );
              },
            ),

            const Divider(height: 28),

            // Email invite.
            Text(
              'Invite by email',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
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
                    onSubmitted: (_) => _addEmailInvite(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: _saving ? null : _addEmailInvite,
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
                'Invited by email (${invited.length})',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: invited
                    .map(
                      (email) => Chip(
                        label: Text(email),
                        onDeleted: () => _removeEmailInvite(email),
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