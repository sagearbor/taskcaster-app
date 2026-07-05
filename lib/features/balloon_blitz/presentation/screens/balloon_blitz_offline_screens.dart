import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../telephone/data/datasources/nearby_diagnostics.dart';
import '../../../telephone/data/datasources/nearby_permissions.dart';
import '../../../telephone/presentation/widgets/nearby_debug_panel.dart';
import '../../data/bots/blitz_bot.dart';
import '../../data/datasources/blitz_transport.dart';
import '../../data/datasources/loopback_blitz_transport.dart';
import '../../data/datasources/nearby_blitz_transport.dart';
import '../../data/repositories/balloon_blitz_repository.dart';
import '../../domain/entities/blitz_session.dart';
import 'balloon_blitz_session_screen.dart';

const _uuid = Uuid();

BlitzTransport _newTransport() {
  final t = NearbyBlitzTransport();
  // Route every advertise/discover/connection event into the debug panel.
  t.onLog = NearbyDiagnostics.instance.log;
  return t;
}

/// A centred status message used for loading / permission / error states,
/// mirroring the Telephone offline screens.
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

/// Hosts an offline Balloon Blitz race: requests permissions, starts advertising
/// over Nearby Connections, then renders the shared [BalloonBlitzSessionScreen]
/// backed by the host repository. Owns the repository lifecycle.
class OfflineBlitzHostScreen extends StatefulWidget {
  final String displayName;
  const OfflineBlitzHostScreen({super.key, required this.displayName});

  @override
  State<OfflineBlitzHostScreen> createState() => _OfflineBlitzHostScreenState();
}

class _OfflineBlitzHostScreenState extends State<OfflineBlitzHostScreen> {
  BalloonBlitzRepository? _repo;
  String? _selfId;
  String? _error;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    NearbyDiagnostics.instance.log('— Host Balloon Blitz: start —');
    try {
      if (!NearbyPermissions.isSupportedPlatform) {
        _fail('Offline nearby play needs an Android phone or tablet.');
        return;
      }
      final granted = await NearbyPermissions.request();
      NearbyDiagnostics.instance.log('host permissions granted=$granted');
      if (!mounted) return;
      if (!granted) {
        _fail(
            'Bluetooth, Wi-Fi and location permissions are required to host an '
            'offline race. Enable them in Settings and try again.');
        return;
      }

      final hostId = _uuid.v4();
      final session = BlitzSession.createHost(
        hostId: hostId,
        hostName: widget.displayName,
      );
      final repo = BalloonBlitzRepository.host(
        transport: _newTransport(),
        session: session,
      );
      final ok = await repo.startHosting();
      if (!mounted) return;
      if (!ok) {
        await repo.dispose();
        _fail(
            'Could not start advertising. Make sure Bluetooth and Wi-Fi are on, '
            'then try again. (Tap "Connection help" below for details.)');
        return;
      }
      setState(() {
        _repo = repo;
        _selfId = hostId;
        _busy = false;
      });
    } catch (e) {
      NearbyDiagnostics.instance.log('host start ERROR: $e');
      _fail('Something went wrong starting the race. '
          'Tap "Connection help" below for details, then try again.');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _busy = false;
    });
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
        appBar: AppBar(title: const Text('Host Balloon Blitz')),
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
    if (_busy || _repo == null || _selfId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Host Balloon Blitz')),
        bottomNavigationBar: const NearbyDebugPanel(),
        body: const _Status(
          icon: Icons.wifi_tethering,
          message: 'Starting nearby race…\nMake sure Bluetooth & Wi-Fi are on.',
          spinner: true,
        ),
      );
    }
    return BalloonBlitzSessionScreen(repository: _repo!, selfId: _selfId!);
  }
}

// ===========================================================================
// SOLO TEST — RACE A BOT (one phone, no Bluetooth)
// ===========================================================================

/// Debug the shared multiplayer race on a SINGLE phone. It stands up a real host
/// repository on one side of a [LoopbackBlitzTransport] and a [BlitzBot]-driven
/// peer repository on the other, then drops into the exact same
/// [BalloonBlitzSessionScreen] hosting uses. Everything downstream is the real
/// thing — host-authoritative spawns, pop adjudication, the live leaderboard, the
/// results ceremony — the only fake is the radio, which is replaced by an
/// in-process loopback. No permissions, no second device.
class OfflineBlitzSoloScreen extends StatefulWidget {
  final String displayName;
  const OfflineBlitzSoloScreen({super.key, required this.displayName});

  @override
  State<OfflineBlitzSoloScreen> createState() => _OfflineBlitzSoloScreenState();
}

class _OfflineBlitzSoloScreenState extends State<OfflineBlitzSoloScreen> {
  BalloonBlitzRepository? _hostRepo;
  BlitzBot? _bot;
  String? _selfId;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    NearbyDiagnostics.instance.log('— Solo Blitz vs bot: start —');
    // One in-process link, host on one end, bot on the other. Auto-connects.
    final (hostTransport, botTransport) = LoopbackBlitzTransport.pair();

    final hostId = _uuid.v4();
    final hostRepo = BalloonBlitzRepository.host(
      transport: hostTransport,
      session: BlitzSession.createHost(
        hostId: hostId,
        hostName: widget.displayName,
      ),
    );

    final botRepo = BalloonBlitzRepository.peer(
      transport: botTransport,
      selfId: _uuid.v4(),
      selfName: BlitzBot.defaultName,
    );
    final bot = BlitzBot(repository: botRepo)..start();

    NearbyDiagnostics.instance
        .log('solo: host + ${BlitzBot.defaultName} linked over loopback');

    setState(() {
      _hostRepo = hostRepo;
      _bot = bot;
      _selfId = hostId;
    });
  }

  @override
  void dispose() {
    // Tear down both ends: the bot disposes its peer repo (+ its loopback
    // endpoint); the host repo disposes the host endpoint.
    _bot?.dispose();
    _hostRepo?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = _hostRepo;
    final selfId = _selfId;
    if (repo == null || selfId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Solo test: race a bot')),
        bottomNavigationBar: const NearbyDebugPanel(),
        body: const _Status(
          icon: Icons.smart_toy,
          message: 'Waking up your rival…',
          spinner: true,
        ),
      );
    }
    // Exactly like hosting: the shared session screen, backed by the host repo.
    return BalloonBlitzSessionScreen(repository: repo, selfId: selfId);
  }
}

// ===========================================================================
// JOIN / DISCOVERY
// ===========================================================================

/// Finds nearby Balloon Blitz hosts and joins one — discovery handles
/// addressing, no code needed. Once the host's first session arrives, swaps in
/// the shared [BalloonBlitzSessionScreen].
class OfflineBlitzJoinScreen extends StatefulWidget {
  final String displayName;
  const OfflineBlitzJoinScreen({super.key, required this.displayName});

  @override
  State<OfflineBlitzJoinScreen> createState() => _OfflineBlitzJoinScreenState();
}

enum _JoinPhase { starting, discovering, connecting, playing, failed }

class _OfflineBlitzJoinScreenState extends State<OfflineBlitzJoinScreen> {
  BalloonBlitzRepository? _repo;
  StreamSubscription<BlitzSession?>? _sessionSub;
  final String _selfId = _uuid.v4();
  _JoinPhase _phase = _JoinPhase.starting;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    NearbyDiagnostics.instance.log('— Find nearby Blitz: start —');
    try {
      if (!NearbyPermissions.isSupportedPlatform) {
        _fail('Offline nearby play needs an Android phone or tablet.');
        return;
      }
      final granted = await NearbyPermissions.request();
      NearbyDiagnostics.instance.log('join permissions granted=$granted');
      if (!mounted) return;
      if (!granted) {
        _fail('Bluetooth, Wi-Fi and location permissions are required to find '
            'nearby races. Enable them in Settings and try again.');
        return;
      }

      final repo = BalloonBlitzRepository.peer(
        transport: _newTransport(),
        selfId: _selfId,
        selfName: widget.displayName,
      );
      // The host's first authoritative session means we're in.
      _sessionSub = repo.watchSession().listen((session) {
        if (!mounted || session == null) return;
        setState(() => _phase = _JoinPhase.playing);
      });
      final ok = await repo.startDiscovery();
      if (!mounted) return;
      if (!ok) {
        await repo.dispose();
        _fail('Could not start scanning. Make sure Bluetooth and Wi-Fi are on. '
            '(Tap "Connection help" below for details.)');
        return;
      }
      setState(() {
        _repo = repo;
        _phase = _JoinPhase.discovering;
      });
    } catch (e) {
      NearbyDiagnostics.instance.log('join start ERROR: $e');
      _fail('Something went wrong while searching. '
          'Tap "Connection help" below for details, then try again.');
    }
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
    _repo?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_phase == _JoinPhase.playing && _repo != null) {
      return BalloonBlitzSessionScreen(repository: _repo!, selfId: _selfId);
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
      appBar: AppBar(title: const Text('Find nearby Blitz')),
      bottomNavigationBar: const NearbyDebugPanel(),
      body: body,
    );
  }
}

class _DeviceList extends StatelessWidget {
  final BalloonBlitzRepository repo;
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
            message: 'Looking for nearby races…\n'
                'Make sure the host has tapped "Host Balloon Blitz" and is close by.',
            spinner: true,
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Tap a race to join',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            ...devices.map((d) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.celebration),
                    title: Text(d.name),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => onTap(d),
                  ),
                )),
          ],
        );
      },
    );
  }
}
