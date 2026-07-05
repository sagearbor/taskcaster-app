import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/models/telephone_session.dart';
import '../../data/datasources/nearby_diagnostics.dart';
import '../../data/datasources/nearby_permissions.dart';
import '../../data/datasources/nearby_telephone_transport.dart';
import '../../data/repositories/nearby_telephone_repository.dart';
import '../../domain/nearby_cast_label.dart';
import '../widgets/nearby_debug_panel.dart';
import 'telephone_session_screen.dart';

/// Shared bits for the two offline entry screens.
const _uuid = Uuid();

NearbyTelephoneTransport _newTransport() {
  final t = NearbyTelephoneTransport(serviceId: kTelephoneNearbyServiceId);
  // Route every advertise/discover/connection/send event into the on-screen
  // "Connection help" panel — without this the diagnostics were lost entirely.
  t.onLog = NearbyDiagnostics.instance.log;
  return t;
}

/// A centred message with an icon, used for the "not supported" / "permission
/// denied" / loading states.
class _Status extends StatelessWidget {
  final IconData icon;
  final String message;
  final Widget? action;
  final bool spinner;
  const _Status({
    required this.icon,
    required this.message,
    this.action,
    this.spinner = false,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (spinner)
              const CircularProgressIndicator()
            else
              Icon(icon, size: 56),
            const SizedBox(height: 20),
            Text(message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge),
            if (action != null) ...[const SizedBox(height: 24), action!],
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// HOST
// ===========================================================================

/// Hosts an offline game: requests permissions, starts advertising over Nearby
/// Connections, then renders the *unchanged* [TelephoneSessionScreen] (lobby →
/// play → reveal) backed by the Nearby repository. Owns the transport lifecycle
/// so it is torn down when the user leaves.
class OfflineHostScreen extends StatefulWidget {
  final String displayName;

  /// How the game plays out (classic chain / same prompt / turn by turn),
  /// chosen on the start screen's mode picker — same as online games.
  final TelephoneGameMode gameMode;

  const OfflineHostScreen({
    super.key,
    required this.displayName,
    this.gameMode = TelephoneGameMode.classicTelephone,
  });

  @override
  State<OfflineHostScreen> createState() => _OfflineHostScreenState();
}

class _OfflineHostScreenState extends State<OfflineHostScreen> {
  NearbyTelephoneRepository? _repo;
  TelephoneSession? _session;
  String? _playerId;
  String? _error;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    NearbyDiagnostics.instance.log('— Host Drawing Telephone: start —');
    if (!NearbyPermissions.isSupportedPlatform) {
      _fail('Offline nearby play needs an Android phone or tablet.');
      return;
    }
    final granted = await NearbyPermissions.request();
    NearbyDiagnostics.instance.log('host permissions granted=$granted');
    if (!mounted) return;
    if (!granted) {
      _fail('Bluetooth, Wi-Fi and location permissions are required to host '
          'an offline game. Enable them in Settings and try again.');
      return;
    }

    final playerId = _uuid.v4();
    final session = TelephoneSession.create(
      id: _uuid.v4(),
      gameName: 'Drawing Telephone',
      inviteCode: _shortCode(),
      creatorUid: playerId,
      creatorName: widget.displayName,
      gameMode: widget.gameMode,
    );
    final repo = NearbyTelephoneRepository.host(
      transport: _newTransport(),
      session: session,
    );
    final ok = await repo.startHosting();
    if (!mounted) return;
    if (!ok) {
      await repo.dispose();
      _fail('Could not start advertising. Make sure Bluetooth and Wi-Fi are '
          'turned on, then try again.');
      return;
    }
    setState(() {
      _repo = repo;
      _session = session;
      _playerId = playerId;
      _busy = false;
    });
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _busy = false;
    });
  }

  String _shortCode() {
    const chars = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    final r = DateTime.now().microsecondsSinceEpoch;
    return List.generate(4, (i) => chars[(r >> (i * 5)) % chars.length]).join();
  }

  @override
  void dispose() {
    _repo?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Host offline game')),
        bottomNavigationBar: const NearbyDebugPanel(),
        body: _Status(
          icon: Icons.bluetooth_disabled,
          message: _error!,
          action: FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Go back'),
          ),
        ),
      );
    }
    if (_busy || _repo == null || _session == null || _playerId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Host offline game')),
        bottomNavigationBar: const NearbyDebugPanel(),
        body: const _Status(
          icon: Icons.wifi_tethering,
          message: 'Starting nearby game…\nMake sure Bluetooth & Wi-Fi are on.',
          spinner: true,
        ),
      );
    }
    // Reuse the standard session screen verbatim, backed by the Nearby repo.
    return TelephoneSessionScreen(
      sessionId: _session!.id,
      playerId: _playerId!,
      displayName: widget.displayName,
      repository: _repo,
    );
  }
}

// ===========================================================================
// JOIN / DISCOVERY
// ===========================================================================

/// Finds nearby hosts and joins one — no invite code, discovery handles
/// addressing. Once connected and the first session arrives, swaps in the
/// standard [TelephoneSessionScreen].
///
/// When [autoJoinEndpointName] is set (the one-tap path from the home-screen
/// auto-cast banner), it re-discovers and connects to *that* host automatically
/// the moment it reappears — no second tap. Endpoint ids aren't portable across
/// transport instances, so we match on the stable advertised endpoint name.
class OfflineJoinScreen extends StatefulWidget {
  final String displayName;
  final String? autoJoinEndpointName;
  const OfflineJoinScreen({
    super.key,
    required this.displayName,
    this.autoJoinEndpointName,
  });

  @override
  State<OfflineJoinScreen> createState() => _OfflineJoinScreenState();
}

enum _JoinPhase { starting, discovering, connecting, playing, failed }

class _OfflineJoinScreenState extends State<OfflineJoinScreen> {
  NearbyTelephoneRepository? _repo;
  StreamSubscription<TelephoneSession?>? _sessionSub;
  StreamSubscription<List<NearbyDevice>>? _devicesSub;
  TelephoneSession? _session;
  final String _playerId = _uuid.v4();
  _JoinPhase _phase = _JoinPhase.starting;
  String? _error;
  bool _autoConnectTried = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    NearbyDiagnostics.instance.log('— Find nearby Drawing Telephone: start —');
    if (!NearbyPermissions.isSupportedPlatform) {
      _fail('Offline nearby play needs an Android phone or tablet.');
      return;
    }
    final granted = await NearbyPermissions.request();
    NearbyDiagnostics.instance.log('join permissions granted=$granted');
    if (!mounted) return;
    if (!granted) {
      _fail('Bluetooth, Wi-Fi and location permissions are required to find '
          'nearby games. Enable them in Settings and try again.');
      return;
    }

    final repo = NearbyTelephoneRepository.peer(
      transport: _newTransport(),
      selfUid: _playerId,
      selfName: widget.displayName,
    );
    // Watch for the host's first authoritative session → that means we're in.
    _sessionSub = repo.watchSession('').listen((session) {
      if (!mounted || session == null) return;
      setState(() {
        _session = session;
        _phase = _JoinPhase.playing;
      });
    });
    // One-tap path: auto-connect to the host the banner pointed us at, as soon
    // as discovery re-finds it (matched by its stable advertised name).
    if (widget.autoJoinEndpointName != null) {
      _devicesSub = repo.discoveredDevices.listen((devices) {
        if (!mounted || _autoConnectTried) return;
        final target = devices.where(
          (d) => d.name == widget.autoJoinEndpointName,
        );
        if (target.isNotEmpty) {
          _autoConnectTried = true;
          _connect(target.first);
        }
      });
    }
    final ok = await repo.startDiscovery();
    if (!mounted) return;
    if (!ok) {
      await repo.dispose();
      _fail('Could not start scanning. Make sure Bluetooth and Wi-Fi are on.');
      return;
    }
    setState(() {
      _repo = repo;
      _phase = _JoinPhase.discovering;
    });
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _phase = _JoinPhase.failed;
    });
  }

  Future<void> _connect(NearbyDevice device) async {
    final repo = _repo;
    if (repo == null) return;
    setState(() => _phase = _JoinPhase.connecting);
    final ok = await repo.connect(device.endpointId);
    if (!mounted) return;
    if (!ok) {
      setState(() => _phase = _JoinPhase.discovering);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not connect. Try again.')),
      );
    }
  }

  @override
  void dispose() {
    _sessionSub?.cancel();
    _devicesSub?.cancel();
    _repo?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_phase == _JoinPhase.playing && _repo != null && _session != null) {
      return TelephoneSessionScreen(
        sessionId: _session!.id,
        playerId: _playerId,
        displayName: widget.displayName,
        repository: _repo,
      );
    }

    Widget body;
    switch (_phase) {
      case _JoinPhase.failed:
        body = _Status(
          icon: Icons.bluetooth_disabled,
          message: _error ?? 'Something went wrong.',
          action: FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Go back'),
          ),
        );
        break;
      case _JoinPhase.starting:
        body = const _Status(
          icon: Icons.search,
          message: 'Getting ready…',
          spinner: true,
        );
        break;
      case _JoinPhase.connecting:
        body = const _Status(
          icon: Icons.handshake,
          message: 'Connecting…',
          spinner: true,
        );
        break;
      case _JoinPhase.discovering:
      case _JoinPhase.playing:
        body = _DeviceList(repo: _repo!, onTap: _connect);
        break;
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Find nearby game')),
      bottomNavigationBar: const NearbyDebugPanel(),
      body: body,
    );
  }
}

class _DeviceList extends StatelessWidget {
  final NearbyTelephoneRepository repo;
  final void Function(NearbyDevice) onTap;
  const _DeviceList({required this.repo, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<NearbyDevice>>(
      stream: repo.discoveredDevices,
      initialData: const [],
      builder: (context, snap) {
        final devices = snap.data ?? const [];
        if (devices.isEmpty) {
          return const _Status(
            icon: Icons.travel_explore,
            message: 'Looking for nearby games…\n'
                'Make sure the host has tapped "Play offline" and is close by.',
            spinner: true,
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Tap a game to join',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            ...devices.map((d) {
              final label = NearbyCastLabel.decode(d.name);
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.sports_esports),
                  title: Text("${label.hostName}'s game"),
                  subtitle: Text(label.gameType.label),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => onTap(d),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}
