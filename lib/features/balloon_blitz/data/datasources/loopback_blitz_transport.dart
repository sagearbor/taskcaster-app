import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'blitz_transport.dart';

/// An in-process [BlitzTransport] pair that wires a host and a peer together
/// WITHOUT any radio — the whole shared-race protocol runs on one device.
///
/// This is what powers "Solo test: race a bot": the host repository lives on one
/// endpoint, a [BlitzBot]-driven peer repository on the other, and every JSON
/// message the two would normally exchange over Google Nearby Connections is
/// instead handed across here. It is modelled on the `LinkedTransport` used in
/// the shared-race tests, but productionised in two ways:
///
///  * **Realistic async delivery.** Messages are delivered on a short
///    [Future.delayed] with per-message jitter (~80–200 ms by default) instead
///    of landing synchronously, so ordering/timing bugs that only bite on a real
///    link (late claims, snapshot heals, out-of-order sessions) actually surface
///    in solo mode. The latency source and [Random] are injectable so tests can
///    make it deterministic under `fakeAsync`.
///  * **JSON round-tripping.** Every message is `jsonEncode`d and `jsonDecode`d
///    on the way across, exactly like the wire, so a non-serialisable payload
///    fails here the same way it would on the radio (and no two endpoints ever
///    share a mutable map reference).
///
/// The two endpoints auto-connect on link-up: as soon as the pair is created the
/// connection handshake is scheduled, and once it fires both sides report the
/// other via [onEndpointConnected] — so the host pushes its lobby and the peer
/// announces its `join` without any discovery dance.
class LoopbackBlitzTransport implements BlitzTransport {
  LoopbackBlitzTransport._(
    this.selfEndpointId, {
    required Random random,
    required Duration Function(Random) latency,
  })  : _random = random,
        _latency = latency;

  /// This endpoint's stable id (`'host-endpoint'` / `'peer-endpoint'`).
  final String selfEndpointId;

  final Random _random;
  final Duration Function(Random) _latency;

  LoopbackBlitzTransport? _peer;

  void Function(String endpointId, Map<String, dynamic> message)? _onMessage;
  void Function(String endpointId)? _onConnected;
  void Function(String endpointId)? _onDisconnected;

  final Set<String> _connected = {};
  final _devices = StreamController<List<NearbyDevice>>.broadcast();

  bool _linkScheduled = false;
  bool _linkedUp = false;
  bool _disposed = false;

  /// Default human-plausible link latency: 80–200 ms per message.
  static Duration _defaultLatency(Random r) =>
      Duration(milliseconds: 80 + r.nextInt(121));

  /// Build a linked host/peer pair. [autoConnect] (the default) schedules the
  /// handshake immediately so both sides connect on their own; pass `false` to
  /// drive the link manually via [connect]. [random]/[latency] are injectable so
  /// delivery timing is deterministic in tests.
  static (LoopbackBlitzTransport host, LoopbackBlitzTransport peer) pair({
    Random? random,
    Duration Function(Random)? latency,
    bool autoConnect = true,
  }) {
    final rand = random ?? Random();
    final lat = latency ?? _defaultLatency;
    final host =
        LoopbackBlitzTransport._('host-endpoint', random: rand, latency: lat);
    final peer =
        LoopbackBlitzTransport._('peer-endpoint', random: rand, latency: lat);
    host._peer = peer;
    peer._peer = host;
    if (autoConnect) host._scheduleLinkUp();
    return (host, peer);
  }

  /// Schedule the (idempotent) handshake. Both endpoints are marked connected
  /// and notified together after one jittered delay — like a real link, where
  /// both ends learn about the connection at roughly the same moment.
  void _scheduleLinkUp() {
    if (_linkScheduled || _disposed) return;
    _linkScheduled = true;
    final peer = _peer;
    if (peer == null) return;
    peer._linkScheduled = true;
    Future.delayed(_latency(_random), () {
      if (_disposed || peer._disposed) return;
      _linkedUp = true;
      peer._linkedUp = true;
      // Add both sides to the connected set BEFORE firing callbacks, so a
      // handler that broadcasts on connect reaches the freshly-linked endpoint.
      _connected.add(peer.selfEndpointId);
      peer._connected.add(selfEndpointId);
      _onConnected?.call(peer.selfEndpointId);
      peer._onConnected?.call(selfEndpointId);
    });
  }

  @override
  set onMessage(
          void Function(String endpointId, Map<String, dynamic> message)? cb) =>
      _onMessage = cb;

  @override
  set onEndpointConnected(void Function(String endpointId)? cb) =>
      _onConnected = cb;

  @override
  set onEndpointDisconnected(void Function(String endpointId)? cb) =>
      _onDisconnected = cb;

  @override
  Stream<List<NearbyDevice>> get discoveredDevices => _devices.stream;

  @override
  Set<String> get connectedEndpoints => _connected;

  @override
  Future<bool> startAdvertising(String advertisedName) async => true;

  @override
  Future<bool> startDiscovery(String selfName) async => true;

  @override
  Future<bool> connect(String endpointId) async {
    _scheduleLinkUp();
    return true;
  }

  @override
  Future<void> sendToEndpoint(
      String endpointId, Map<String, dynamic> message) async {
    final peer = _peer;
    if (peer == null || _disposed) return;
    // Round-trip through JSON exactly like the wire: no shared references, and a
    // non-serialisable payload fails here just as it would on the radio.
    final wire = jsonEncode(message);
    // Deliver LATER (fire-and-forget) so timing bugs surface; the send itself
    // returns immediately, matching a queued radio send.
    Future.delayed(_latency(_random), () {
      if (_disposed || peer._disposed) return;
      final decoded = jsonDecode(wire) as Map<String, dynamic>;
      peer._onMessage?.call(selfEndpointId, decoded);
    });
  }

  @override
  Future<void> broadcast(Map<String, dynamic> message) async {
    for (final id in _connected.toList()) {
      await sendToEndpoint(id, message);
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    // Tell the far end we dropped, mirroring a real disconnect.
    final peer = _peer;
    if (peer != null && !peer._disposed && _linkedUp) {
      peer._connected.remove(selfEndpointId);
      peer._onDisconnected?.call(selfEndpointId);
    }
    _connected.clear();
    if (!_devices.isClosed) await _devices.close();
  }
}
