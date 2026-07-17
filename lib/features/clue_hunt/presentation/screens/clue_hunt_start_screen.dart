import 'package:flutter/material.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import '../../../telephone/data/datasources/nearby_permissions.dart';
import 'clue_hunt_offline_screens.dart';

/// Entry point for Clue Hunt — the co-located, offline, physical treasure hunt
/// where phones are the game layer. One phone hosts and hides a real object; the
/// rest join over Google Nearby Connections and hunt while the hider drives a
/// warmer/colder meter. Android-only, gated exactly like Balloon Blitz.
class ClueHuntStartScreen extends StatefulWidget {
  const ClueHuntStartScreen({super.key});

  @override
  State<ClueHuntStartScreen> createState() => _ClueHuntStartScreenState();
}

class _ClueHuntStartScreenState extends State<ClueHuntStartScreen> {
  final _nameController = TextEditingController();
  int _rounds = 3;

  @override
  void initState() {
    super.initState();
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
      builder: (_) =>
          OfflineClueHuntHostScreen(displayName: _name, totalRounds: _rounds),
    ));
  }

  void _join() {
    if (!_guard()) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => OfflineClueHuntJoinScreen(displayName: _name),
    ));
  }

  bool _guard() {
    if (_nameController.text.trim().isEmpty) {
      _toast('Enter your name first');
      return false;
    }
    if (!NearbyPermissions.isSupportedPlatform) {
      _toast('Offline Clue Hunt is only available on Android.');
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
      appBar: AppBar(title: const Text('Clue Hunt')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: Text('🔍', style: TextStyle(fontSize: 56))),
            const SizedBox(height: 8),
            Text('Clue Hunt',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Hide a REAL object — a spoon, a toy — anywhere: a house or an open '
              'field. Everyone else hunts on their phone while you, the hider, '
              'watch and drive a warmer/colder meter. First to grab it scores; '
              'faster is worth more. Then the role rotates. No internet needed.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
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
              SizedBox(
                height: 56,
                child: FilledButton.icon(
                  onPressed: _host,
                  icon: const Icon(Icons.wifi_tethering),
                  label: const Text('Host a hunt',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'You hide first. Everyone else taps "Join".',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ] else
              const Card(
                color: AppTheme.violetSoft,
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Offline Clue Hunt connects Android phones directly over '
                    'Bluetooth & Wi-Fi Direct. It is only available on Android.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Card(
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                leading: const Icon(Icons.more_horiz),
                title: const Text('Options',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Join a nearby hunt or set rounds'),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  if (supported) ...[
                    OutlinedButton.icon(
                      onPressed: _join,
                      icon: const Icon(Icons.travel_explore),
                      label: const Text('Join nearby hunt'),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'No code needed — joins a host in the same place.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    children: [
                      const Text('Rounds'),
                      Expanded(
                        child: Slider(
                          value: _rounds.toDouble(),
                          min: 1,
                          max: 10,
                          divisions: 9,
                          label: '$_rounds',
                          onChanged: (v) =>
                              setState(() => _rounds = v.round()),
                        ),
                      ),
                      SizedBox(
                        width: 24,
                        child: Text('$_rounds',
                            textAlign: TextAlign.end,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  Text(
                    'How many times the hider role rotates (host sets this).',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
