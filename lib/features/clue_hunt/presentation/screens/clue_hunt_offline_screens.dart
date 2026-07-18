import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../telephone/data/datasources/nearby_diagnostics.dart';
import '../../../telephone/data/datasources/nearby_permissions.dart';
import '../../../telephone/presentation/widgets/nearby_debug_panel.dart';
import '../../data/datasources/clue_hunt_transport.dart';
import '../../data/datasources/nearby_clue_hunt_transport.dart';
import '../../data/repositories/clue_hunt_repository.dart';
import '../../domain/entities/clue_hunt_session.dart';
import 'clue_hunt_session_screen.dart';

const _uuid = Uuid();

ClueHuntTransport _newTransport() {
  final t = NearbyClueHuntTransport();
  t.onLog = NearbyDiagnostics.instance.log;
  return t;
}

/// A centred status message for loading / permission / error states, mirroring
/// the Telephone and Blitz offline screens.
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

/// Hosts an offline Clue Hunt: requests permissions, starts advertising over
/// Nearby Connections, then renders the shared [ClueHuntSessionScreen] backed by
/// the host repository. Owns the repository lifecycle.
class OfflineClueHuntHostScreen extends StatefulWidget {
  final String displayName;
  final int totalRounds;
  const OfflineClueHuntHostScreen({
    super.key,
    required this.displayName,
    this.totalRounds = 3,
  });

  @override
  State<OfflineClueHuntHostScreen> createState() =>
      _OfflineClueHuntHostScreenState();
}

class _OfflineClueHuntHostScreenState extends State<OfflineClueHuntHostScreen> {
  ClueHuntRepository? _repo;
  String? _selfId;
  String? _error;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    NearbyDiagnostics.instance.log('— Host Clue Hunt: start —');
    try {
      if (!NearbyPermissions.isSupportedPlatform) {
        _fail('Offline nearby play needs an Android phone or tablet.');
        return;
      }
      final granted = await NearbyPermissions.request();
      NearbyDiagnostics.instance.log('host permissions granted=$granted');
      if (!mounted) return;
      if (!granted) {
        _fail('Bluetooth, Wi-Fi and location permissions are required to host a '
            'hunt. Enable them in Settings and try again.');
        return;
      }

      final hostId = _uuid.v4();
      final session = ClueHuntSession.createHost(
        hostId: hostId,
        hostName: widget.displayName,
        totalRounds: widget.totalRounds,
      );
      final repo = ClueHuntRepository.host(
        transport: _newTransport(),
        session: session,
      );
      // Capture the repo for disposal BEFORE the await: startHosting() spins up a
      // live advertising session, so if we back out mid-await, State.dispose (and
      // the unmounted check below) must be able to tear it down — otherwise the
      // radio keeps advertising (battery drain + STATUS_ALREADY_ADVERTISING on
      // every retry until the app is killed).
      _repo = repo;
      final ok = await repo.startHosting();
      if (!mounted) {
        await repo.dispose();
        return;
      }
      if (!ok) {
        await repo.dispose();
        _fail('Could not start advertising. Make sure Bluetooth and Wi-Fi are '
            'on, then try again. (Tap "Connection help" below for details.)');
        return;
      }
      setState(() {
        _selfId = hostId;
        _busy = false;
      });
    } catch (e) {
      NearbyDiagnostics.instance.log('host start ERROR: $e');
      _fail('Something went wrong starting the hunt. '
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
        appBar: AppBar(title: const Text('Host Clue Hunt')),
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
        appBar: AppBar(title: const Text('Host Clue Hunt')),
        bottomNavigationBar: const NearbyDebugPanel(),
        body: const _Status(
          icon: Icons.wifi_tethering,
          message: 'Starting nearby hunt…\nMake sure Bluetooth & Wi-Fi are on.',
          spinner: true,
        ),
      );
    }
    return ClueHuntSessionScreen(repository: _repo!, selfId: _selfId!);
  }
}

// ===========================================================================
// JOIN / DISCOVERY
// ===========================================================================

/// Finds nearby Clue Hunt hosts and joins one — discovery handles addressing, no
/// code needed. Once the host's first session arrives, swaps in the shared
/// [ClueHuntSessionScreen].
class OfflineClueHuntJoinScreen extends StatefulWidget {
  final String displayName;
  const OfflineClueHuntJoinScreen({super.key, required this.displayName});

  @override
  State<OfflineClueHuntJoinScreen> createState() =>
      _OfflineClueHuntJoinScreenState();
}

enum _JoinPhase { starting, discovering, connecting, playing, failed }

class _OfflineClueHuntJoinScreenState extends State<OfflineClueHuntJoinScreen> {
  /// How long to wait after tapping a host before giving up and returning to the
  /// device list — `connect()` returning true only means the request was sent,
  /// so without this a failed handshake would hang on "Connecting…" forever.
  static const Duration _connectTimeout = Duration(seconds: 15);

  ClueHuntRepository? _repo;
  StreamSubscription<ClueHuntSession?>? _sessionSub;
  StreamSubscription<String>? _disconnectSub;
  Timer? _connectTimer;
  final String _selfId = _uuid.v4();
  _JoinPhase _phase = _JoinPhase.starting;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    NearbyDiagnostics.instance.log('— Find nearby Clue Hunt: start —');
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
            'nearby hunts. Enable them in Settings and try again.');
        return;
      }

      final repo = ClueHuntRepository.seeker(
        transport: _newTransport(),
        selfId: _selfId,
        selfName: widget.displayName,
      );
      // Capture the repo for disposal BEFORE the await so backing out mid-await
      // can't leak a live discovery session (finding 5).
      _repo = repo;
      // The host's first authoritative session means we're in.
      _sessionSub = repo.watchSession().listen((session) {
        if (!mounted || session == null) return;
        _connectTimer?.cancel();
        setState(() => _phase = _JoinPhase.playing);
      });
      // A dropped link while we're mid-handshake must not leave us stuck on
      // "Connecting…" (finding 7).
      _disconnectSub = repo.disconnections.listen((_) => _onLinkLost());
      final ok = await repo.startDiscovery();
      if (!mounted) {
        await repo.dispose();
        return;
      }
      if (!ok) {
        await repo.dispose();
        _fail('Could not start scanning. Make sure Bluetooth and Wi-Fi are on. '
            '(Tap "Connection help" below for details.)');
        return;
      }
      setState(() => _phase = _JoinPhase.discovering);
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
    // `connect()` only initiates the request; the first session (via the stream
    // listener) is the real "we're in" signal. Guard the wait with a timeout so
    // a handshake that never completes falls back to the device list instead of
    // hanging on "Connecting…" indefinitely.
    _connectTimer?.cancel();
    _connectTimer = Timer(_connectTimeout, () {
      _connectFailed("Couldn't connect — try again");
    });
    final ok = await repo.connect(device.endpointId);
    if (!mounted) return;
    if (!ok) {
      _connectFailed('Could not connect. Try again.');
    }
  }

  /// A dropped link — if it lands while we're still handshaking, treat it like a
  /// failed connect (finding 7).
  void _onLinkLost() {
    if (_phase == _JoinPhase.connecting) {
      _connectFailed("Couldn't connect — try again");
    }
  }

  /// Return to the device list with a friendly message. Only acts while we're
  /// still in the connecting state, so a late timeout/disconnect after we've
  /// already started playing is ignored.
  void _connectFailed(String message) {
    _connectTimer?.cancel();
    if (!mounted || _phase != _JoinPhase.connecting) return;
    setState(() => _phase = _JoinPhase.discovering);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  void dispose() {
    _connectTimer?.cancel();
    _sessionSub?.cancel();
    _disconnectSub?.cancel();
    _repo?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_phase == _JoinPhase.playing && _repo != null) {
      return ClueHuntSessionScreen(repository: _repo!, selfId: _selfId);
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
      appBar: AppBar(title: const Text('Find nearby Clue Hunt')),
      bottomNavigationBar: const NearbyDebugPanel(),
      body: body,
    );
  }
}

class _DeviceList extends StatelessWidget {
  final ClueHuntRepository repo;
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
            message: 'Looking for nearby hunts…\n'
                'Make sure the host has tapped "Host a hunt" and is close by.',
            spinner: true,
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Tap a hunt to join',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            ...devices.map((d) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.search),
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
