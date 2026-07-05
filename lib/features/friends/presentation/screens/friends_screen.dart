import 'package:flutter/material.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../domain/models/friend.dart';
import '../../domain/repositories/friends_repository.dart';

/// The friend list: everyone you've played with. Each row shows an avatar,
/// name and "last played" line, with swipe-to-remove and an explicit remove
/// button (both confirm first). Friends are added silently as you play; this
/// screen is where you can prune them.
///
/// Navigation entry point: the app's avatar/overflow menu. That menu currently
/// lives inside `home_screen.dart` (owned by another agent), so wire it there
/// with:  `Navigator.push(context, MaterialPageRoute(builder: (_) => const
/// FriendsScreen()));`
class FriendsScreen extends StatelessWidget {
  const FriendsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final friends = sl<FriendsRepository>();
    return Scaffold(
      appBar: AppBar(title: const Text('Friends')),
      body: StreamBuilder<List<Friend>>(
        stream: friends.watchFriends(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snapshot.data ?? const <Friend>[];
          if (list.isEmpty) return const _EmptyFriends();

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final friend = list[index];
              return Dismissible(
                key: ValueKey(friend.uid),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: Theme.of(context).colorScheme.error,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                confirmDismiss: (_) => _confirmRemove(context, friend),
                onDismissed: (_) {
                  // Already removed inside _confirmRemove; nothing extra needed.
                },
                child: _FriendTile(friend: friend),
              );
            },
          );
        },
      ),
    );
  }

  /// Shows the confirm dialog and, when confirmed, removes the friend. Returns
  /// whether the row should be dismissed.
  static Future<bool> _confirmRemove(BuildContext context, Friend friend) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove friend?'),
        content: Text(
          'Remove ${friend.displayName} from your friends? You can become '
          'friends again by playing another game together.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;

    try {
      await sl<FriendsRepository>().removeFriend(friend.uid);
      messenger.showSnackBar(
        SnackBar(content: Text('Removed ${friend.displayName}')),
      );
      return true;
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not remove friend. Try again.')),
      );
      return false;
    }
  }
}

class _FriendTile extends StatelessWidget {
  final Friend friend;

  const _FriendTile({required this.friend});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: UserAvatar(
        displayName: friend.displayName,
        avatarEmoji: friend.avatarEmoji,
      ),
      title: Text(friend.displayName),
      subtitle: Text(_lastPlayedLabel(friend.lastPlayedAt)),
      trailing: IconButton(
        tooltip: 'Remove friend',
        icon: const Icon(Icons.person_remove_outlined),
        onPressed: () => FriendsScreen._confirmRemove(context, friend),
      ),
    );
  }

  String _lastPlayedLabel(DateTime? when) {
    if (when == null) return 'Played together';
    final diff = DateTime.now().difference(when);
    if (diff.inDays >= 1) {
      final d = diff.inDays;
      return 'Last played $d day${d == 1 ? '' : 's'} ago';
    }
    if (diff.inHours >= 1) {
      final h = diff.inHours;
      return 'Last played $h hour${h == 1 ? '' : 's'} ago';
    }
    return 'Last played just now';
  }
}

class _EmptyFriends extends StatelessWidget {
  const _EmptyFriends();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.group_outlined,
                size: 64, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              'No friends yet',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Play a game with someone and they\'ll appear here automatically.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
