import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:nearby_connections/nearby_connections.dart';

/// App-unique Nearby service id. Must be identical on advertiser + discoverer,
/// and distinct enough that we only ever find *our* games.
const String kTelephoneNearbyServiceId = 'com.sagearbor.taskcaster.telephone';

/// A discovered nearby advertiser (a host offering an offline game).
class NearbyDevice {
  final String endpointId;
  final String name;

  const NearbyDevice(this.endpointId, this.name);
}

/// The discovery-only slice of [NearbyTelephoneTransport]. Passive auto-cast
/// (the home-screen "a nearby game is available" banner) only ever needs to
/// *listen* — it never advertises, connects or sends — so it depends on this
/// narrow interface, which is trivially faked in tests without the Nearby
/// plugin (and therefore without a real radio).
abstract class NearbyDiscovery {
  /// Live list of advertisers currently visible.
  Stream<List<NearbyDevice>> get discoveredDevices;

  /// Begin scanning for hosts. Returns false on unsupported platforms / failure.
  Future<bool> startDiscovery(String selfName);

  /// Stop scanning (keeps the instance reusable).
  Future<void> stopDiscovery();

  /// Release the instance entirely (closes the [discoveredDevices] stream).
  Future<void> dispose();
}

/// Thin wrapper around the `nearby_connections` plugin (Google Nearby
/// Connections — Bluetooth + Wi-Fi Direct, fully offline) that turns the raw
/// byte-payload API into a JSON-message bus with reliable framing.
///
/// ## Why framing
/// Nearby BYTES payloads are capped at ~32 KB. A full [TelephoneSession] at the
/// reveal step can carry several drawings and easily blow past that, so every
/// logical message (a JSON map) is UTF-8 encoded, split into ≤[_chunkSize]-byte
/// chunks, and each chunk is prefixed with a fixed 24-byte ASCII header
/// (`NCF1` + 8-hex msgId + 6-digit index + 6-digit count). The receiver
/// reassembles by (endpoint, msgId) and decodes once all chunks arrive.
///
/// ## Roles
/// One instance serves either role:
///  * HOST  → [startAdvertising] then [sendToEndpoint] / [broadcast].
///  * PEER  → [startDiscovery] (watch [discoveredDevices]) then [connect].
///
/// All transport is Android-only; on web/iOS the methods short-circuit so the
/// app still compiles and runs (offline play is simply unavailable there).
class NearbyTelephoneTransport implements NearbyDiscovery {
  NearbyTelephoneTransport({required this.serviceId});

  /// Unique per-app id so we only ever discover *our* games. Must match on both
  /// the advertiser and the discoverer.
  final String serviceId;

  static const Strategy _strategy = Strategy.P2P_CLUSTER;

  /// Header is fixed-width ASCII so the body can be sliced off by byte offset.
  static const int _headerLen = 24; // 'NCF1'(4) + msgId(8) + index(6) + count(6)
  static const int _chunkSize = 24000; // well under the ~32 KB BYTES limit

  // ---- Callbacks (set by the owning repository) ----------------------------

  /// A fully-reassembled JSON message arrived from [endpointId].
  void Function(String endpointId, Map<String, dynamic> message)? onMessage;

  /// An endpoint completed its connection handshake (CONNECTED).
  void Function(String endpointId)? onEndpointConnected;

  /// An endpoint disconnected (or its connection failed/rejected).
  void Function(String endpointId)? onEndpointDisconnected;

  /// Optional diagnostic sink — every advertise/discover/connection event and
  /// any thrown plugin error is reported here for the on-screen debug panel.
  void Function(String line)? onLog;

  void _log(String line) => onLog?.call(line);

  // ---- Discovery state -----------------------------------------------------

  final _discovered = <String, NearbyDevice>{};
  final _discoveredController =
      StreamController<List<NearbyDevice>>.broadcast();

  /// Live list of advertisers found during discovery (peer side).
  @override
  Stream<List<NearbyDevice>> get discoveredDevices =>
      _discoveredController.stream;

  List<NearbyDevice> get currentDevices =>
      List<NearbyDevice>.unmodifiable(_discovered.values);

  // ---- Connection / reassembly state ---------------------------------------

  final Set<String> _connectedEndpoints = {};
  Set<String> get connectedEndpoints => Set.unmodifiable(_connectedEndpoints);

  final Map<String, _Reassembly> _inbound = {};
  int _msgCounter = 0;

  bool get _supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  String _myName = 'Player';

  // ---- Host ----------------------------------------------------------------

  /// Begin advertising this device as a host. [advertisedName] is what peers
  /// see in their discovery list.
  Future<bool> startAdvertising(String advertisedName) async {
    if (!_supported) return false;
    _myName = advertisedName;
    _log('HOST advertising as "$advertisedName" (service=$serviceId)…');
    try {
      final ok = await Nearby().startAdvertising(
        advertisedName,
        _strategy,
        serviceId: serviceId,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );
      _log(ok ? 'HOST advertising started ✓' : 'HOST advertising returned FALSE');
      return ok;
    } catch (e) {
      _log('HOST advertising ERROR: $e');
      return false;
    }
  }

  Future<void> stopAdvertising() async {
    if (!_supported) return;
    await Nearby().stopAdvertising();
  }

  // ---- Peer ----------------------------------------------------------------

  /// Begin scanning for hosts. [selfName] identifies us to the host.
  @override
  Future<bool> startDiscovery(String selfName) async {
    if (!_supported) return false;
    _myName = selfName;
    _discovered.clear();
    _emitDiscovered();
    _log('PEER discovery starting as "$selfName" (service=$serviceId)…');
    try {
      final ok = await Nearby().startDiscovery(
        selfName,
        _strategy,
        serviceId: serviceId,
        onEndpointFound: (endpointId, endpointName, sid) {
          _discovered[endpointId] = NearbyDevice(endpointId, endpointName);
          _log('PEER found host "$endpointName" (id=$endpointId)');
          _emitDiscovered();
        },
        onEndpointLost: (endpointId) {
          if (endpointId != null) _discovered.remove(endpointId);
          _log('PEER lost host (id=$endpointId)');
          _emitDiscovered();
        },
      );
      _log(ok ? 'PEER discovery started ✓' : 'PEER discovery returned FALSE');
      return ok;
    } catch (e) {
      _log('PEER discovery ERROR: $e');
      return false;
    }
  }

  @override
  Future<void> stopDiscovery() async {
    if (!_supported) return;
    await Nearby().stopDiscovery();
  }

  /// Request a connection to a discovered host. The handshake completes via
  /// [onEndpointConnected] once both sides accept.
  Future<bool> connect(String endpointId) async {
    if (!_supported) return false;
    _log('PEER requesting connection to id=$endpointId…');
    try {
      final ok = await Nearby().requestConnection(
        _myName,
        endpointId,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );
      _log(ok
          ? 'PEER connection requested ✓ (awaiting handshake)'
          : 'PEER requestConnection returned FALSE');
      return ok;
    } catch (e) {
      _log('PEER requestConnection ERROR: $e');
      return false;
    }
  }

  // ---- Sending -------------------------------------------------------------

  /// Send a JSON [message] to a single endpoint, chunked + framed.
  Future<void> sendToEndpoint(
      String endpointId, Map<String, dynamic> message) async {
    if (!_supported) return;
    final body = Uint8List.fromList(utf8.encode(jsonEncode(message)));
    final msgId = (_msgCounter++ & 0xFFFFFFFF);
    final total =
        body.isEmpty ? 1 : ((body.length + _chunkSize - 1) ~/ _chunkSize);
    for (var i = 0; i < total; i++) {
      final start = i * _chunkSize;
      final end = (start + _chunkSize) > body.length
          ? body.length
          : start + _chunkSize;
      final chunk = Uint8List.sublistView(body, start, end);
      final framed = _frame(msgId, i, total, chunk);
      await Nearby().sendBytesPayload(endpointId, framed);
    }
  }

  /// Send a JSON [message] to every connected endpoint (host → all peers).
  Future<void> broadcast(Map<String, dynamic> message) async {
    for (final id in _connectedEndpoints.toList()) {
      await sendToEndpoint(id, message);
    }
  }

  // ---- Teardown ------------------------------------------------------------

  @override
  Future<void> dispose() async {
    if (_supported) {
      try {
        await Nearby().stopAdvertising();
        await Nearby().stopDiscovery();
        await Nearby().stopAllEndpoints();
      } catch (_) {/* best-effort */}
    }
    _connectedEndpoints.clear();
    _inbound.clear();
    if (!_discoveredController.isClosed) await _discoveredController.close();
  }

  // ---- Plugin callbacks ----------------------------------------------------

  void _onConnectionInitiated(String endpointId, ConnectionInfo info) {
    // Auto-accept: this is a private family game with no untrusted peers, and
    // both sides must accept for the channel to open.
    _log('handshake initiated with "${info.endpointName}" (id=$endpointId) — accepting');
    try {
      Nearby().acceptConnection(
        endpointId,
        onPayLoadRecieved: _onPayloadReceived,
      );
    } catch (e) {
      _log('acceptConnection ERROR (id=$endpointId): $e');
    }
  }

  void _onConnectionResult(String endpointId, Status status) {
    _log('connection result id=$endpointId → $status');
    if (status == Status.CONNECTED) {
      _connectedEndpoints.add(endpointId);
      onEndpointConnected?.call(endpointId);
    } else {
      _connectedEndpoints.remove(endpointId);
      onEndpointDisconnected?.call(endpointId);
    }
  }

  void _onDisconnected(String endpointId) {
    _log('disconnected id=$endpointId');
    _connectedEndpoints.remove(endpointId);
    onEndpointDisconnected?.call(endpointId);
  }

  void _onPayloadReceived(String endpointId, Payload payload) {
    if (payload.type != PayloadType.BYTES) return;
    final bytes = payload.bytes;
    if (bytes == null || bytes.length < _headerLen) return;

    final header = ascii.decode(bytes.sublist(0, _headerLen));
    if (!header.startsWith('NCF1')) return;
    final msgId = int.tryParse(header.substring(4, 12), radix: 16);
    final index = int.tryParse(header.substring(12, 18));
    final count = int.tryParse(header.substring(18, 24));
    if (msgId == null || index == null || count == null || count < 1) return;

    final body = Uint8List.sublistView(bytes, _headerLen);
    final key = '$endpointId:$msgId';
    final asm = _inbound.putIfAbsent(key, () => _Reassembly(count));
    asm.add(index, body);
    if (!asm.complete) return;
    _inbound.remove(key);

    try {
      final decoded = jsonDecode(utf8.decode(asm.assemble()));
      if (decoded is Map<String, dynamic>) {
        onMessage?.call(endpointId, decoded);
      } else if (decoded is Map) {
        onMessage?.call(endpointId, Map<String, dynamic>.from(decoded));
      }
    } catch (_) {/* drop malformed frame */}
  }

  // ---- Helpers -------------------------------------------------------------

  Uint8List _frame(int msgId, int index, int count, Uint8List chunk) {
    final header = 'NCF1'
        '${msgId.toRadixString(16).padLeft(8, '0').substring(0, 8)}'
        '${index.toString().padLeft(6, '0')}'
        '${count.toString().padLeft(6, '0')}';
    final headerBytes = ascii.encode(header);
    final out = Uint8List(headerBytes.length + chunk.length);
    out.setRange(0, headerBytes.length, headerBytes);
    out.setRange(headerBytes.length, out.length, chunk);
    return out;
  }

  void _emitDiscovered() {
    if (!_discoveredController.isClosed) {
      _discoveredController.add(currentDevices);
    }
  }
}

/// Buffers the chunks of one logical message until all [count] have arrived.
class _Reassembly {
  _Reassembly(this.count) : _chunks = List<Uint8List?>.filled(count, null);
  final int count;
  final List<Uint8List?> _chunks;
  int _have = 0;

  void add(int index, Uint8List bytes) {
    if (index < 0 || index >= count) return;
    if (_chunks[index] != null) return;
    _chunks[index] = bytes;
    _have++;
  }

  bool get complete => _have == count;

  Uint8List assemble() {
    final builder = BytesBuilder(copy: false);
    for (final c in _chunks) {
      if (c != null) builder.add(c);
    }
    return builder.toBytes();
  }
}
