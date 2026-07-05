import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../friends/presentation/screens/friends_screen.dart';
import '../../../auth/presentation/screens/profile_screen.dart';
import '../../../auth/presentation/screens/create_account_screen.dart';
import '../../../settings/presentation/screens/settings_screen.dart';

class HomeAppBar extends StatelessWidget implements PreferredSizeWidget {
  const HomeAppBar({super.key});

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: const Text('TaskCaster'),
      actions: [
        // Code entry now lives in Zone 1's empty state and behind the Play
        // sheet ("Join with a code"), so the app bar keeps only the avatar menu.
        BlocBuilder<AuthBloc, AuthState>(
          builder: (context, state) {
            if (state is! AuthAuthenticated) {
              return const SizedBox.shrink();
            }
            final user = state.user;
            final isGuest = user.email == null;

            return PopupMenuButton<String>(
              icon: UserAvatar(
                displayName: user.displayName,
                avatarEmoji: user.avatarEmoji,
                radius: 18,
                borderColor: Colors.white,
              ),
              onSelected: (value) {
                switch (value) {
                  case 'profile':
                    _push(context, ProfileScreen(user: user));
                    break;
                  case 'friends':
                    _push(context, const FriendsScreen());
                    break;
                  case 'settings':
                    _push(context, const SettingsScreen());
                    break;
                  case 'create_account':
                    _push(context, const CreateAccountScreen());
                    break;
                  case 'logout':
                    _confirmSignOut(context);
                    break;
                }
              },
              itemBuilder: (BuildContext context) => [
                PopupMenuItem<String>(
                  enabled: false,
                  child: Row(
                    children: [
                      UserAvatar(
                        displayName: user.displayName,
                        avatarEmoji: user.avatarEmoji,
                        radius: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user.displayName,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              user.email ?? 'Guest',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem<String>(
                  value: 'profile',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.person_outline),
                    title: Text('Edit Profile'),
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'friends',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.group_outlined),
                    title: Text('Friends'),
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'settings',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.settings_outlined),
                    title: Text('Settings'),
                  ),
                ),
                if (isGuest)
                  const PopupMenuItem<String>(
                    value: 'create_account',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.person_add_alt_1, color: AppTheme.gold),
                      title: Text('Create Account'),
                    ),
                  ),
                const PopupMenuDivider(),
                const PopupMenuItem<String>(
                  value: 'logout',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.logout, color: AppTheme.coral),
                    title: Text('Sign Out',
                        style: TextStyle(color: AppTheme.coral)),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BlocProvider.value(
          value: context.read<AuthBloc>(),
          child: screen,
        ),
      ),
    );
  }

  void _confirmSignOut(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.coral),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              context.read<AuthBloc>().add(SignOutRequested());
            },
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
