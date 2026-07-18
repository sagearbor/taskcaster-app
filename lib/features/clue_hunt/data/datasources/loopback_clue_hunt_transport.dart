import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'clue_hunt_transport.dart';

/// An in-process [ClueHuntTransport] pair that wires a host and a seeker together
/// WITHOUT any radio — the whole hunt protocol runs on one machine. It powers the
/// two-phone end-to-end tests (and could back a same-device practice mode) and is
/// modelled on the Balloon Blitz loopback, productionised the same two ways:
///
///  * **Realistic async delivery.** Messages land on a short [Future.delayed]
///    with per-message jitter instead of synchronously, so ordering/timing bugs
///    that only bite on a real link (late claims, snapshot heals, throttled heat)
///    actually surface. The latency source and [Random] are injectable so tests
///    can make delivery deterministic under `fakeAsync`.
///  * **JSON round-tripping.** Every message is `jsonEncode`d/`jsonDecode`d on
///    the way across, exactly like the wire, so a non-serialisable payload fails
///    here just as it would on the radio (and no two endpoints share a mutable
///    map reference).
///
/// The two endpoints auto-connect on link-up so the host pushes its lobby and the
/// seeker announces its `join` with no discovery dance.
class LoopbackClueHuntTransport implements ClueHuntTransport {
  LoopbackClueHuntTransport._(
    this.selfEndpointId, {
    required Random random,
    required Duration Function(Random) latency,
  })  : _random = random,
        _latency = latency;

  /// This endpoint's stable id (`'host-endpoint'` / `'seeker-endpoint'`).
  final String selfEndpointId;

  final Random _random;
  final Duration Function(Random) _latency;

  LoopbackClueHuntTransport? _peer;

  void Function(String endpointId, Map<String, dynamic> message)? _onMessage;
  void Function(String endpointId)? _onConnected;
  void Function(String endpointId)? _onDisconnected;

  final Set<String> _connected = {};
  final _devices = StreamController<List<NearbyDevice>>.broadcast();

  /// Test seam: when set and it returns true for a given outbound message, the
  /// send FAILS (the returned future rejects) instead of delivering — simulating
  /// a dropped radio send so retry/self-heal paths can be exercised.
  bool Function(Map<String, dynamic> message)? failSend;

  bool _linkScheduled = false;
  bool _linkedUp = false;
  bool _disposed = false;

  /// Default human-plausible link latency: 80–200 ms per message.
  static Duration _defaultLatency(Random r) =>
      Duration(milliseconds: 80 + r.nextInt(121));

  /// Build a linked host/seeker pair. [autoConnect] (the default) schedules the
  /// handshake immediately so both sides connect on their own; pass `false` to
  /// drive the link manually via [connect]. [random]/[latency] are injectable so
  /// delivery timing is deterministic in tests.
  static (LoopbackClueHuntTransport host, LoopbackClueHuntTransport seeker)
      pair({
    Random? random,
    Duration Function(Random)? latency,
    bool autoConnect = true,
  }) {
    final rand = random ?? Random();
    final lat = latency ?? _defaultLatency;
    final host =
        LoopbackClueHuntTransport._('host-endpoint', random: rand, latency: lat);
    final seeker = LoopbackClueHuntTransport._('seeker-endpoint',
        random: rand, latency: lat);
    host._peer = seeker;
    seeker._peer = host;
    if (autoConnect) host._scheduleLinkUp();
    return (host, seeker);
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
    // A simulated dropped send: reject before anything is delivered.
    if (failSend?.call(message) ?? false) {
      throw StateError('simulated dropped send: ${message['k']}');
    }
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
