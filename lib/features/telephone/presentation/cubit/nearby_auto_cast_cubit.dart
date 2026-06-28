import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/datasources/nearby_permissions.dart';
import '../../data/datasources/nearby_telephone_transport.dart';
import '../../domain/nearby_cast_label.dart';

/// Why auto-cast is not currently scanning. Lets the UI stay silent for the
/// right reasons and lets tests assert the exact path taken.
enum AutoCastIdleReason {
  /// Not started yet, or explicitly stopped (left screen / app backgrounded).
  stopped,

  /// Platform can't run Nearby (web / iOS) — the plugin is a no-op there.
  unsupported,

  /// Nearby permissions aren't granted yet; we won't prompt from here.
  permissionsMissing,

  /// Discovery failed to start (radio off, plugin error, …).
  failed,
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

abstract class NearbyAutoCastState extends Equatable {
  const NearbyAutoCastState();

  @override
  List<Object?> get props => [];
}

/// Not surfacing anything — either dormant or scanning with nothing found yet.
/// The banner renders nothing for either; [reason] is for diagnostics/tests.
class AutoCastIdle extends NearbyAutoCastState {
  const AutoCastIdle(this.reason);
  final AutoCastIdleReason reason;

  @override
  List<Object?> get props => [reason];
}

/// Actively listening; no host visible yet. Banner is hidden.
class AutoCastScanning extends NearbyAutoCastState {
  const AutoCastScanning();
}

/// A nearby host is advertising a game — show the one-tap "Join" banner.
class AutoCastGameAvailable extends NearbyAutoCastState {
  const AutoCastGameAvailable({required this.host, required this.label});

  /// The raw discovered device (its [NearbyDevice.endpointId] is only valid
  /// inside the transport that found it, so the join flow re-discovers).
  final NearbyDevice host;

  /// Decoded, human-friendly description of the advertised game.
  final NearbyCastLabel label;

  /// The advertised endpoint name — a stable handle the join screen matches on
  /// to auto-connect to *this* host.
  String get endpointName => host.name;

  @override
  List<Object?> get props => [host.endpointId, host.name];
}

// ---------------------------------------------------------------------------
// Cubit
// ---------------------------------------------------------------------------

/// Drives passive, low-power "auto-cast" discovery: while the user simply sits
/// on the home screen, this quietly scans for nearby TaskCaster hosts and, the
/// moment one appears, flips to [AutoCastGameAvailable] so a banner can offer a
/// one-tap join — no "Find nearby game" tap required.
///
/// It owns the discovery transport lifecycle:
///  * [start] gates on platform + (already-granted) permissions, then spins up a
///    fresh [NearbyDiscovery] and subscribes to its stream.
///  * [stop] tears the transport down (freeing the radio) and goes idle. The
///    owning widget calls this on app-background / navigation and [start] again
///    on resume, so discovery never leaks or drains the battery off-screen.
///
/// Everything here is transport-agnostic: it depends only on the [NearbyDiscovery]
/// interface and an injected permission check, so the full state machine is unit
/// tested with a fake transport and no real radio. The radio pairing itself is
/// only verifiable on two physical Android devices.
class NearbyAutoCastCubit extends Cubit<NearbyAutoCastState> {
  NearbyAutoCastCubit({
    NearbyDiscovery Function()? transportFactory,
    Future<bool> Function()? permissionCheck,
    bool Function()? isSupported,
    String selfName = 'TaskCaster',
  })  : _transportFactory = transportFactory ?? _defaultTransportFactory,
        _permissionCheck = permissionCheck ?? NearbyPermissions.isGranted,
        _isSupported =
            isSupported ?? (() => NearbyPermissions.isSupportedPlatform),
        _selfName = selfName,
        super(const AutoCastIdle(AutoCastIdleReason.stopped));

  final NearbyDiscovery Function() _transportFactory;
  final Future<bool> Function() _permissionCheck;
  final bool Function() _isSupported;
  final String _selfName;

  NearbyDiscovery? _transport;
  StreamSubscription<List<NearbyDevice>>? _sub;

  /// Guards against overlapping [start]s (e.g. a fast resume/pause) while the
  /// async permission check is in flight.
  bool _starting = false;

  bool get isActive => _transport != null;

  static NearbyDiscovery _defaultTransportFactory() =>
      NearbyTelephoneTransport(serviceId: kTelephoneNearbyServiceId);

  /// Begin (or no-op if already) passive discovery.
  Future<void> start() async {
    if (isClosed || isActive || _starting) return;
    _starting = true;
    try {
      if (!_isSupported()) {
        _emit(const AutoCastIdle(AutoCastIdleReason.unsupported));
        return;
      }
      final granted = await _permissionCheck();
      if (isClosed) return;
      if (!granted) {
        _emit(const AutoCastIdle(AutoCastIdleReason.permissionsMissing));
        return;
      }
      // A start() may have been superseded by a stop() during the await.
      if (isClosed || isActive) return;

      final transport = _transportFactory();
      _transport = transport;
      _sub = transport.discoveredDevices.listen(_onDevices);
      final ok = await transport.startDiscovery(_selfName);
      if (isClosed || _transport != transport) {
        // Stopped/closed mid-await — clean up the orphaned transport.
        await _disposeTransport(transport);
        return;
      }
      if (!ok) {
        await _teardown();
        _emit(const AutoCastIdle(AutoCastIdleReason.failed));
        return;
      }
      _emit(const AutoCastScanning());
    } finally {
      _starting = false;
    }
  }

  /// Stop discovery and go dormant.
  Future<void> stop() async {
    if (!isActive) {
      if (!isClosed && state is! AutoCastIdle) {
        _emit(const AutoCastIdle(AutoCastIdleReason.stopped));
      }
      return;
    }
    await _teardown();
    _emit(const AutoCastIdle(AutoCastIdleReason.stopped));
  }

  void _onDevices(List<NearbyDevice> devices) {
    if (isClosed || !isActive) return;
    if (devices.isEmpty) {
      _emit(const AutoCastScanning());
      return;
    }
    // Prefer a device whose name actually decodes as a TaskCaster cast; fall
    // back to the first one (the shared serviceId already means it's ours).
    final pick = devices.firstWhere(
      (d) => NearbyCastLabel.decode(d.name).isTaskCaster,
      orElse: () => devices.first,
    );
    _emit(AutoCastGameAvailable(
      host: pick,
      label: NearbyCastLabel.decode(pick.name),
    ));
  }

  Future<void> _teardown() async {
    await _sub?.cancel();
    _sub = null;
    final t = _transport;
    _transport = null;
    if (t != null) await _disposeTransport(t);
  }

  Future<void> _disposeTransport(NearbyDiscovery t) async {
    try {
      await t.stopDiscovery();
      await t.dispose();
    } catch (_) {/* best-effort teardown */}
  }

  void _emit(NearbyAutoCastState s) {
    if (!isClosed) emit(s);
  }

  @override
  Future<void> close() async {
    await _teardown();
    return super.close();
  }
}
