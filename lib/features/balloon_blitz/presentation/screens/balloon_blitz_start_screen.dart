import 'package:flutter/material.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import '../../../telephone/data/datasources/nearby_permissions.dart';
import 'balloon_blitz_offline_screens.dart';

/// Entry point for Balloon Blitz — the social, offline, competitive AR race.
/// One phone hosts and the rest join over Google Nearby Connections (Bluetooth /
/// Wi-Fi Direct), so a family can race on a plane with no internet. Android-only,
/// gated exactly like the Telephone offline flow.
class BalloonBlitzStartScreen extends StatefulWidget {
  const BalloonBlitzStartScreen({super.key});

  @override
  State<BalloonBlitzStartScreen> createState() =>
      _BalloonBlitzStartScreenState();
}

class _BalloonBlitzStartScreenState extends State<BalloonBlitzStartScreen> {
  final _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Pre-fill with the signed-in display name when we have one.
    final auth = sl<AuthRepository>();
    auth.getCurrentUser().then((user) {
      if (mounted && user != null && _nameController.text.isEmpty) {
        _nameController.text = user.displayName;
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String get _name {
    final n = _nameController.text.trim();
    return n.isEmpty ? 'Player' : n;
  }

  void _host() {
    if (!_guard()) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => OfflineBlitzHostScreen(displayName: _name),
    ));
  }

  void _join() {
    if (!_guard()) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => OfflineBlitzJoinScreen(displayName: _name),
    ));
  }

  /// Shared name + platform check for both entry points.
  bool _guard() {
    if (_nameController.text.trim().isEmpty) {
      _toast('Enter your name first');
      return false;
    }
    if (!NearbyPermissions.isSupportedPlatform) {
      _toast('Offline Balloon Blitz is only available on Android.');
      return false;
    }
    return true;
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final supported = NearbyPermissions.isSupportedPlatform;
    return Scaffold(
      appBar: AppBar(title: const Text('Balloon Blitz')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: Text('🎈', style: TextStyle(fontSize: 56))),
            const SizedBox(height: 8),
            Text('Balloon Blitz',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Race your family to pop the most balloons! Everyone plays on their '
              'own phone — scores sync live over Bluetooth. No internet needed, '
              'so it works on a plane.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 28),
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Your name',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 24),
            if (supported) ...[
              FilledButton.icon(
                onPressed: _host,
                icon: const Icon(Icons.wifi_tethering),
                label: const Text('Host Balloon Blitz'),
              ),
              const SizedBox(height: 8),
              Text(
                'One phone hosts. Everyone else taps "Join".',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              Row(children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('Or', style: theme.textTheme.bodySmall),
                ),
                const Expanded(child: Divider()),
              ]),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _join,
                icon: const Icon(Icons.travel_explore),
                label: const Text('Join nearby race'),
              ),
            ] else
              const Card(
                color: AppTheme.violetSoft,
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Offline Balloon Blitz connects Android phones directly over '
                    'Bluetooth & Wi-Fi Direct. It is only available on Android.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
