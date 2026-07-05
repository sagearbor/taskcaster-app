import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/models/game.dart';
import '../../../../core/services/invite/invite_link_parser.dart';
import '../../../../core/utils/friendly_errors.dart';
import '../../../../core/utils/link_utils.dart';
import '../../../../core/models/task.dart';
import '../../../../core/models/player_task_status.dart';
import '../../../../core/widgets/skeleton_loaders.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/repositories/game_repository.dart';
import '../bloc/game_detail_bloc.dart';
import '../widgets/game_lobby_view.dart';
import '../widgets/game_in_progress_view.dart';
import '../widgets/game_completed_view.dart';
import '../widgets/game_status_banner.dart';
import 'task_execution_screen.dart';
import 'ar_task_screen.dart';
import 'judging_screen.dart';

class GameDetailScreen extends StatelessWidget {
  final String gameId;

  /// When true, the invite/share dialog opens automatically the first time the
  /// game loads — used right after creating a game, when inviting friends is
  /// the very next thing the creator wants to do.
  final bool promptShareOnLoad;

  const GameDetailScreen({
    super.key,
    required this.gameId,
    this.promptShareOnLoad = false,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => GameDetailBloc(
        gameRepository: sl<GameRepository>(),
      )..add(LoadGameDetail(gameId: gameId)),
      child: GameDetailView(promptShareOnLoad: promptShareOnLoad),
    );
  }
}

class GameDetailView extends StatefulWidget {
  final bool promptShareOnLoad;

  const GameDetailView({super.key, this.promptShareOnLoad = false});

  @override
  State<GameDetailView> createState() => _GameDetailViewState();
}

class _GameDetailViewState extends State<GameDetailView> {
  /// Ensures the auto-opened share dialog appears only once per visit.
  bool _sharePrompted = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: BlocBuilder<GameDetailBloc, GameDetailState>(
          builder: (context, state) {
            if (state is GameDetailLoaded) {
              return Text(state.game.gameName);
            }
            return const Text('Game Details');
          },
        ),
        actions: [
          BlocBuilder<GameDetailBloc, GameDetailState>(
            builder: (context, state) {
              if (state is! GameDetailLoaded) {
                return const SizedBox.shrink();
              }

              final authState = context.read<AuthBloc>().state;
              final currentUserId =
                  authState is AuthAuthenticated ? authState.user.id : '';
              final isCreator = state.game.creatorId == currentUserId;
              final isPlayer =
                  state.game.players.any((p) => p.userId == currentUserId);

              final items = <PopupMenuEntry<String>>[
                if (state.game.isInLobby)
                  const PopupMenuItem(
                    value: 'share',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.share),
                      title: Text('Share Invite'),
                    ),
                  ),
                // Non-creators who are in the game can leave it.
                if (!isCreator && isPlayer)
                  const PopupMenuItem(
                    value: 'leave',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.exit_to_app),
                      title: Text('Leave game'),
                    ),
                  ),
                // The creator can delete the whole game.
                if (isCreator)
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_outline,
                          color: Theme.of(context).colorScheme.error),
                      title: Text('Delete game',
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    ),
                  ),
              ];

              // Hide the overflow button entirely when there's nothing to show
              // (previously it opened an empty menu).
              if (items.isEmpty) return const SizedBox.shrink();

              return PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'share':
                      _showShareDialog(context, state.game);
                      break;
                    case 'leave':
                      _confirmLeave(context, state.game.id, currentUserId);
                      break;
                    case 'delete':
                      _confirmDelete(context, state.game.id);
                      break;
                  }
                },
                itemBuilder: (context) => items,
              );
            },
          ),
        ],
      ),
      body: BlocConsumer<GameDetailBloc, GameDetailState>(
        listener: (context, state) {
          if (state is GameDetailError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.red,
              ),
            );
          }
          if (state is GameDetailRematchReady) {
            // The rematch lobby exists — drop the creator straight into it,
            // replacing this (completed) game's screen.
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                // The whole crew is already on the new roster, so no share
                // prompt is needed — straight into the fresh lobby.
                builder: (_) => GameDetailScreen(gameId: state.gameId),
              ),
            );
          }
          if (state is GameDetailLoaded &&
              widget.promptShareOnLoad &&
              !_sharePrompted) {
            _sharePrompted = true;
            // Open after this frame so the lobby is visible behind the dialog.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _showShareDialog(context, state.game);
            });
          }
        },
        builder: (context, state) {
          if (state is GameDetailLoading ||
              state is GameDetailRematchInProgress ||
              state is GameDetailRematchReady) {
            // Rematch states show the same skeleton while the fresh lobby is
            // created and navigated into.
            return SkeletonLoaders.gameDetailSkeleton(context);
          }

          if (state is GameDetailError) {
            return ErrorView(
              message: 'Failed to load game',
              details: state.message,
              onRetry: () {
                final gameId = context.read<GameDetailBloc>().gameId;
                if (gameId != null) {
                  context.read<GameDetailBloc>().add(LoadGameDetail(gameId: gameId));
                }
              },
            );
          }

          if (state is GameDetailLoaded) {
            final authState = context.read<AuthBloc>().state;
            final currentUserId = authState is AuthAuthenticated ? authState.user.id : '';
            final isJudge = state.game.judgeId == currentUserId;

            return Column(
              children: [
                // Add status banner at the top
                GameStatusBanner(
                  game: state.game,
                  currentUserId: currentUserId,
                  isJudge: isJudge,
                  onAction: () {
                    // Handle banner action based on game state
                    _handleBannerAction(context, state.game, currentUserId);
                  },
                ),
                Expanded(
                  child: switch (state.game.status) {
                    GameStatus.lobby => GameLobbyView(game: state.game),
                    GameStatus.inProgress => GameInProgressView(game: state.game),
                    GameStatus.completed => GameCompletedView(
                        game: state.game,
                        currentUserId: currentUserId,
                        onRematch: () => context
                            .read<GameDetailBloc>()
                            .add(RematchGame(game: state.game)),
                      ),
                  },
                ),
              ],
            );
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }

  void _handleBannerAction(BuildContext context, Game game, String currentUserId) {
    // Handle different banner actions based on game state
    if (game.status == GameStatus.lobby && game.creatorId == currentUserId && game.players.length >= 2) {
      // Start game action
      context.read<GameDetailBloc>().add(StartGame(gameId: game.id));
    } else if (game.status == GameStatus.inProgress && game.currentTask != null) {
      // Use the safe getter rather than tasks[currentTaskIndex], which could
      // throw a RangeError if the index ever drifts past the task list.
      final currentTask = game.currentTask!;
      final playerStatus = currentTask.playerStatuses[currentUserId];

      if (playerStatus == null ||
          playerStatus.state == TaskPlayerState.not_started ||
          playerStatus.state == TaskPlayerState.in_progress) {
        // Navigate to task execution (mirrors the working push in
        // game_in_progress_view.dart). TaskExecutionScreen builds its own
        // bloc and reads the app-wide AuthBloc, so no provider forwarding
        // is required here.
        // AR tasks launch the AR flow (capability check + scaffold); all other
        // task types use the standard task-execution screen.
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => currentTask.isArTask
                ? ARTaskScreen(
                    gameId: game.id,
                    taskIndex: game.currentTaskIndex,
                    arGameId: currentTask.arGameId,
                  )
                : TaskExecutionScreen(
                    gameId: game.id,
                    taskIndex: game.currentTaskIndex,
                  ),
          ),
        );
      } else if (game.judgeId == currentUserId && currentTask.status == TaskStatus.ready_to_judge) {
        // Navigate to judging. JudgingScreen and its downstream screens read
        // GameDetailBloc, which is only provided inside this screen, so we
        // forward it down the route via BlocProvider.value.
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BlocProvider.value(
              value: context.read<GameDetailBloc>(),
              child: JudgingScreen(
                gameId: game.id,
                taskIndex: game.currentTaskIndex,
              ),
            ),
          ),
        );
      } else if (currentTask.status == TaskStatus.completed) {
        // Navigate to scoreboard
        context.read<GameDetailBloc>().add(
          ViewTaskResultsEvent(
            gameId: game.id,
            taskIndex: game.currentTaskIndex,
          ),
        );
      }
    } else if (game.status == GameStatus.lobby && game.players.length < 2) {
      // Share invite code
      _showShareDialog(context, game);
    }
  }

  Future<void> _confirmLeave(
      BuildContext context, String gameId, String userId) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave game?'),
        content: const Text(
            'You will be removed from this game. You can re-join later with '
            'the invite code.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await sl<GameRepository>().leaveGame(gameId, userId);
      messenger.showSnackBar(
        const SnackBar(content: Text('You left the game')),
      );
      navigator.pop(); // back to home
    } catch (e) {
      debugPrint('Leave game failed: $e');
      messenger.showSnackBar(
        SnackBar(
          content: Text(FriendlyErrors.action(
            e,
            fallback: 'Could not leave the game. Please try again.',
          )),
        ),
      );
    }
  }

  Future<void> _confirmDelete(BuildContext context, String gameId) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete game?'),
        content: const Text(
            'This permanently deletes the game for everyone. This cannot be '
            'undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await sl<GameRepository>().deleteGame(gameId);
      messenger.showSnackBar(
        const SnackBar(content: Text('Game deleted')),
      );
      navigator.pop(); // back to home
    } catch (e) {
      debugPrint('Delete game failed: $e');
      messenger.showSnackBar(
        SnackBar(
          content: Text(FriendlyErrors.action(
            e,
            fallback: 'Could not delete the game. Please try again.',
          )),
        ),
      );
    }
  }

  void _showShareDialog(BuildContext context, Game game) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Share Game Invite'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Share this invite code with your friends:'),
            const SizedBox(height: 16),
            Center(
              child: Container(
                padding: const EdgeInsets.all(8),
                color: Colors.white,
                child: QrImageView(
                  // The join URL (not the bare code) so scanning routes the
                  // friend into the app or the Play Store install flow.
                  data: InviteLinks.joinUrl(game.inviteCode),
                  version: QrVersions.auto,
                  size: 160,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    game.inviteCode,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Game: ${game.gameName}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          TextButton.icon(
            onPressed: () => LinkUtils.copyToClipboard(
              context,
              game.inviteCode,
              label: 'Invite code copied',
            ),
            icon: const Icon(Icons.copy),
            label: const Text('Copy Code'),
          ),
          ElevatedButton.icon(
            onPressed: () => _shareInvite(game),
            icon: const Icon(Icons.share),
            label: const Text('Share'),
          ),
        ],
      ),
    );
  }

  void _shareInvite(Game game) {
    final link = InviteLinks.joinUrl(game.inviteCode);
    final text = '🎈 Join my TaskCaster game "${game.gameName}"!\n\n'
        'Tap to join: $link\n\n'
        'No app yet? Same link installs it and brings you straight into my game.\n'
        '(Or enter code ${game.inviteCode} in the app.)';
    Share.share(text, subject: 'TaskCaster game invite');
  }
}