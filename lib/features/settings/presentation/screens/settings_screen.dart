import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/theme_controller.dart';
import '../../../ar_lab/presentation/screens/ar_lab_screen.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const String _notificationsPrefKey = 'notifications_enabled';

  // Reads the real installed version at runtime (was hardcoded "1.0.1", which
  // went stale and confused testers). Falls back to the bare name until loaded.
  String _appVersion = 'TaskCaster';
  bool _notificationsEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadNotificationsPref();
    _loadVersion();
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
                  leading: Icon(Icons.privacy_tip_outlined,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  title: const Text('Privacy Policy'),
                  trailing: Text('Coming soon',
                      style: TextStyle(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                  enabled: false,
                  onTap: null,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.description_outlined,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  title: const Text('Terms of Service'),
                  trailing: Text('Coming soon',
                      style: TextStyle(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                  enabled: false,
                  onTap: null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _sectionHeader(context, 'Account'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.logout, color: AppTheme.coral),
              title: const Text('Sign Out',
                  style: TextStyle(color: AppTheme.coral)),
              onTap: () => _confirmSignOut(context),
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
}
