import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/config/legal_links.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/theme_controller.dart';
import '../../../ar_lab/presentation/screens/ar_lab_screen.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.openLink});

  /// Opens an external URL (privacy policy / terms). Defaults to
  /// url_launcher; injectable so widget tests can assert which page a tile
  /// opens without touching the platform channel.
  final Future<void> Function(Uri uri)? openLink;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const String _notificationsPrefKey = 'notifications_enabled';

  // Reads the real installed version at runtime (was hardcoded "1.0.1", which
  // went stale and confused testers). Falls back to the bare name until loaded.
  String _appVersion = 'TaskCaster';
  bool _notificationsEnabled = true;

  // True from the moment "Delete My Account" (or a re-auth confirm) is
  // tapped until a terminal outcome (deleted / failed) arrives, so the tile
  // shows a spinner and can't be tapped twice.
  bool _deletingAccount = false;

  @override
  void initState() {
    super.initState();
    _loadNotificationsPref();
    _loadVersion();
  }

  Future<void> _openLegalPage(String url) async {
    final uri = Uri.parse(url);
    final open = widget.openLink ??
        (Uri u) => launchUrl(u, mode: LaunchMode.externalApplication);
    try {
      await open(uri);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open $url')),
      );
    }
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _appVersion = 'TaskCaster ${info.version}');
    } catch (_) {
      // Keep the fallback if package info is unavailable.
    }
  }

  Future<void> _loadNotificationsPref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _notificationsEnabled = prefs.getBool(_notificationsPrefKey) ?? true;
      });
    } catch (_) {
      // Keep the default if prefs are unavailable.
    }
  }

  Future<void> _setNotifications(bool value) async {
    setState(() => _notificationsEnabled = value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_notificationsPrefKey, value);
    } catch (_) {
      // Non-fatal.
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listenWhen: (prev, curr) =>
          curr is AuthReauthenticationRequired ||
          curr is AuthAccountDeletionFailure ||
          curr is AuthAccountDeleted,
      listener: (context, state) {
        if (state is AuthReauthenticationRequired) {
          setState(() => _deletingAccount = false);
          _showReauthDialog(context, state.providerIds);
        } else if (state is AuthAccountDeletionFailure) {
          setState(() => _deletingAccount = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
        } else if (state is AuthAccountDeleted) {
          setState(() => _deletingAccount = false);
          // The AuthWrapper above this route swaps to the sign-in screen on
          // its own; just pop any routes pushed on top of it (this Settings
          // screen included) so that screen is what's left showing.
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      },
      child: _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionHeader(context, 'Appearance'),
          Card(
            child: ListenableBuilder(
              listenable: ThemeController.instance,
              builder: (context, _) {
                final mode = ThemeController.instance.themeMode;
                return Column(
                  children: [
                    _themeTile(context, 'System default', ThemeMode.system,
                        mode, Icons.brightness_auto_outlined),
                    const Divider(height: 1),
                    _themeTile(context, 'Light', ThemeMode.light, mode,
                        Icons.light_mode_outlined),
                    const Divider(height: 1),
                    _themeTile(context, 'Dark', ThemeMode.dark, mode,
                        Icons.dark_mode_outlined),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          _sectionHeader(context, 'Notifications'),
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.notifications_outlined,
                  color: AppTheme.violet),
              title: const Text('Game notifications'),
              subtitle: const Text(
                  'Get notified about task deadlines and judging'),
              value: _notificationsEnabled,
              onChanged: _setNotifications,
            ),
          ),
          const SizedBox(height: 20),
          _sectionHeader(context, 'About'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outline, color: AppTheme.violet),
                  title: const Text('Version'),
                  subtitle: Text(_appVersion),
                ),
                const Divider(height: 1),
                ListTile(
                  leading:
                      const Icon(Icons.privacy_tip_outlined, color: AppTheme.violet),
                  title: const Text('Privacy Policy'),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => _openLegalPage(LegalLinks.privacyPolicy),
                ),
                const Divider(height: 1),
                ListTile(
                  leading:
                      const Icon(Icons.description_outlined, color: AppTheme.violet),
                  title: const Text('Terms of Service'),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => _openLegalPage(LegalLinks.termsOfService),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.delete_outline,
                      color: AppTheme.violet),
                  title: const Text('How to delete your account'),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => _openLegalPage(LegalLinks.accountDeletion),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _sectionHeader(context, 'Account'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.logout, color: AppTheme.coral),
                  title: const Text('Sign Out',
                      style: TextStyle(color: AppTheme.coral)),
                  onTap: () => _confirmSignOut(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: _deletingAccount
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_forever_outlined,
                          color: AppTheme.coral),
                  title: const Text('Delete Account',
                      style: TextStyle(color: AppTheme.coral)),
                  subtitle:
                      const Text('Permanently delete your account and data'),
                  onTap: _deletingAccount
                      ? null
                      : () => _confirmDeleteAccount(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _sectionHeader(context, 'Experimental'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.view_in_ar_outlined,
                  color: AppTheme.violet),
              title: const Text('AR Lab (experimental)'),
              subtitle: const Text(
                  'Cloud Anchor two-phone diagnostic — not a game'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ArLabScreen(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              letterSpacing: 1.1,
            ),
      ),
    );
  }

  Widget _themeTile(BuildContext context, String label, ThemeMode value,
      ThemeMode current, IconData icon) {
    final selected = value == current;
    return ListTile(
      leading: Icon(icon,
          color: selected
              ? AppTheme.violet
              : Theme.of(context).colorScheme.onSurfaceVariant),
      title: Text(label),
      trailing: selected
          ? const Icon(Icons.check_circle, color: AppTheme.violet)
          : null,
      onTap: () => ThemeController.instance.setThemeMode(value),
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
              Navigator.of(dialogContext).pop(); // close dialog
              context.read<AuthBloc>().add(SignOutRequested());
              // Return to the root; the auth wrapper will show the login screen.
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteAccount(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
          'This permanently deletes your account, profile, avatar, friends '
          'list and notification settings. Games you\'ve played stay in '
          'other players\' history, but your identity is removed from '
          'them. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.coral),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              setState(() => _deletingAccount = true);
              context.read<AuthBloc>().add(DeleteAccountRequested());
            },
            child: const Text('Delete My Account'),
          ),
        ],
      ),
    );
  }

  /// Shown when Firebase requires a fresh sign-in before it will let the
  /// account be deleted. [providerIds] (from [AuthReauthenticationRequired])
  /// says which credential type the account actually uses, so a
  /// password-account user gets a password field while a Google/Apple user
  /// gets a "Continue with ..." button instead.
  void _showReauthDialog(BuildContext context, List<String> providerIds) {
    if (providerIds.contains('password')) {
      final controller = TextEditingController();
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Confirm it\'s you'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'For your security, please re-enter your password to finish '
                'deleting your account.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Password'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.coral),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                setState(() => _deletingAccount = true);
                context.read<AuthBloc>().add(
                      AccountDeletionReauthenticated(
                          password: controller.text),
                    );
              },
              child: const Text('Confirm & Delete'),
            ),
          ],
        ),
      );
      return;
    }

    final providerLabel = providerIds.contains('google.com')
        ? 'Google'
        : providerIds.contains('apple.com')
            ? 'Apple'
            : null;
    if (providerLabel != null) {
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Confirm it\'s you'),
          content: Text(
            'For your security, please sign in with $providerLabel again '
            'to finish deleting your account.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.coral),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                setState(() => _deletingAccount = true);
                context
                    .read<AuthBloc>()
                    .add(const AccountDeletionReauthenticated());
              },
              child: Text('Continue with $providerLabel'),
            ),
          ],
        ),
      );
      return;
    }

    // No known re-auth path (e.g. a guest/anonymous session) — tell the
    // player what to do instead of retrying automatically.
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Please sign in again'),
        content: const Text(
          'For your security, please sign out and sign back in, then try '
          'deleting your account again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
