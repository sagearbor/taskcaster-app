import 'dart:async';

import 'package:collection/collection.dart';

import '../../../../core/services/ar/ar_race.dart';
import '../../../telephone/data/datasources/nearby_diagnostics.dart';
import '../../domain/entities/blitz_session.dart';
import '../datasources/blitz_transport.dart';

enum BlitzRole { host, peer }

/// The host-authoritative engine for an offline Balloon Blitz race.
///
/// Exactly like the Telephone Nearby repository, the HOST holds the one true
/// [BlitzSession]: it applies the pure model mutations ([BlitzSession.started],
/// [BlitzSession.withScore], [BlitzSession.ended] …) and broadcasts
/// `session.toMap()` to every peer. PEERS never mutate locally — they rebuild
/// the session from each broadcast and send their actions to the host as tiny
/// JSON messages, which the host applies and re-broadcasts.
///
/// It also implements [ArRaceSync]: since v1.2.21 everyone races ONE shared
/// balloon set. The host's game controller owns spawns/escapes/adjudication
/// and scores every pop into the session (so the leaderboard is always the pop
/// ledger — no separate score messages that can be lost).
///
/// Wire protocol (all maps carry a `k` kind):
///  * peer → host  `{'k':'join','id':..,'name':..}`  — announce in the lobby
///  * peer → host  `{'k':'pop','id':..,'by':..}`     — claim a tap on object id
///  * host → peers `{'k':'session','session':{…}}`    — full authoritative state
///  * host → peers `{'k':'go'}`                       — run the 3-2-1-GO now
///  * host → peers `{'k':'spawn','o':{…}}`            — shared object spawned
///  * host → peers `{'k':'popped','id','by','v','b'}` — object gone, points paid
///  * host → peers `{'k':'escaped','id':..}`          — object floated away
///  * host → peers `{'k':'objects','list':[…]}`       — periodic set snapshot
class BalloonBlitzRepository implements ArRaceSync {
  BalloonBlitzRepository._({
    required this.role,
    required this.transport,
    required this.selfId,
    required this.selfName,
    BlitzSession? initialSession,
    int Function()? now,
  })  : _current = initialSession,
        _now = now ?? (() => DateTime.now().millisecondsSinceEpoch) {
    transport.onMessage = _onMessage;
    transport.onEndpointConnected = _onEndpointConnected;
    transport.onEndpointDisconnected = _onEndpointDisconnected;
  }

  /// Create a host that owns [session] (already built with the host in the
  /// lobby). [now] is injectable so round timing is deterministic in tests.
  factory BalloonBlitzRepository.host({
    required BlitzTransport transport,
    required BlitzSession session,
    int Function()? now,
  }) {
    return BalloonBlitzRepository._(
      role: BlitzRole.host,
      transport: transport,
      selfId: session.hostId,
      selfName: session.host?.name ?? 'Host',
      initialSession: session,
      now: now,
    );
  }

  /// Create a peer. [selfId] is this device's per-session player id.
  factory BalloonBlitzRepository.peer({
    required BlitzTransport transport,
    required String selfId,
    required String selfName,
    int Function()? now,
  }) {
    return BalloonBlitzRepository._(
      role: BlitzRole.peer,
      transport: transport,
      selfId: selfId,
      selfName: selfName,
      now: now,
    );
  }

  final BlitzRole role;
  final BlitzTransport transport;
  final String selfId;
  final String selfName;
  final int Function() _now;

  BlitzSession? _current;
  final _controller = StreamController<BlitzSession?>.broadcast();
  final _raceEvents = StreamController<ArRaceEvent>.broadcast();
  Timer? _roundTimer;
  String? _hostEndpointId; // peer: remembered at connect time, not send time

  bool get isHost => role == BlitzRole.host;
  BlitzSession? get current => _current;

  // ---- ArRaceSync (the shared balloon set) ----------------------------------

  @override
  bool get isAuthority => isHost;

  @override
  String get selfPlayerId => selfId;

  @override
  Stream<ArRaceEvent> get events => _raceEvents.stream;

  @override
  String playerName(String playerId) {
    final players = _current?.players ?? const [];
    for (final p in players) {
      if (p.id == playerId) return p.name;
    }
    return 'Someone';
  }

  @override
  void announceGo() {
    _sendRace({'k': 'go'});
    _emitRace(const ArRaceEvent(ArRaceEventType.go)); // echo to own controller
  }

  @override
  void publishSpawn(ArRaceObject object) {
    _sendRace({'k': 'spawn', 'o': object.toMap()});
  }

  @override
  void publishPop({
    required String objectId,
    required String playerId,
    required int value,
    required bool isBomb,
  }) {
    // The pop ledger IS the score: apply it to the authoritative session (the
    // _apply broadcast carries the new leaderboard to every phone), then tell
    // mirrors to remove the object.
    final s = _current;
    if (s != null) {
      final old = s.players
          .where((p) => p.id == playerId)
          .map((p) => p.liveScore)
          .firstOrNull ??
          0;
      final next = isBomb ? old - value : old + value;
      _apply(s.withScore(playerId, next < 0 ? 0 : next));
    }
    _sendRace({'k': 'popped', 'id': objectId, 'by': playerId, 'v': value, 'b': isBomb});
  }

  @override
  void publishEscape(String objectId) {
    _sendRace({'k': 'escaped', 'id': objectId});
  }

  @override
  void publishSnapshot(List<ArRaceObject> objects) {
    _sendRace({'k': 'objects', 'list': objects.map((o) => o.toMap()).toList()});
  }

  @override
  void claimPop(String objectId) {
    final host = _hostEndpoint();
    if (host.isEmpty) {
      NearbyDiagnostics.instance.log('pop claim dropped: no host connection');
      return; // optimistic UI already fired; the next snapshot re-syncs us
    }
    transport
        .sendToEndpoint(host, {'k': 'pop', 'id': objectId, 'by': selfId}).catchError(
      (Object e) =>
          NearbyDiagnostics.instance.log('pop claim send failed: $e'),
    );
  }

  /// Host → everyone else, race messages. One dead peer never blocks the rest.
  void _sendRace(Map<String, dynamic> message) {
    transport.broadcast(message).catchError(
        (Object e) => NearbyDiagnostics.instance.log('race send failed: $e'));
  }

  void _emitRace(ArRaceEvent event) {
    if (!_raceEvents.isClosed) _raceEvents.add(event);
  }

  // ---- Lobby plumbing ------------------------------------------------------

  /// HOST: start advertising so peers can discover this race.
  Future<bool> startHosting() =>
      transport.startAdvertising("$selfName's Balloon Blitz");

  /// PEER: live list of nearby hosts.
  Stream<List<NearbyDevice>> get discoveredDevices =>
      transport.discoveredDevices;

  /// PEER: start scanning for hosts.
  Future<bool> startDiscovery() => transport.startDiscovery(selfName);

  /// PEER: connect to a chosen host; the first session arrives via [watchSession].
  Future<bool> connect(String endpointId) => transport.connect(endpointId);

  // ---- Live session --------------------------------------------------------

  /// The authoritative session: the current value first, then every update.
  Stream<BlitzSession?> watchSession() async* {
    yield _current;
    yield* _controller.stream;
  }

  // ---- Round lifecycle (host-authoritative) --------------------------------

  /// HOST: begin a synchronized round. Resets every score, marks the session
  /// [BlitzPhase.playing], stamps the start time, broadcasts, and schedules the
  /// authoritative time-up that flips everyone to results.
  Future<void> startRound() async {
    if (!isHost) return;
    final s = _current;
    if (s == null) return;
    _apply(s.started(now: _now()));
    _roundTimer?.cancel();
    _roundTimer = Timer(
      Duration(seconds: s.durationSeconds),
      endRound,
    );
  }

  /// HOST: end the current round and reveal the final ranking. Idempotent and
  /// safe to call from the time-up timer or an early "everyone finished" path.
  void endRound() {
    if (!isHost) return;
    final s = _current;
    if (s == null || s.phase != BlitzPhase.playing) return;
    _roundTimer?.cancel();
    _apply(s.ended());
  }

  /// HOST: drop scores and return to the lobby for another race.
  Future<void> playAgain() async {
    if (!isHost) return;
    _roundTimer?.cancel();
    final s = _current;
    if (s == null) return;
    _apply(s.backToLobby());
  }

  // ---- Internals -----------------------------------------------------------

  void _apply(BlitzSession next) {
    _current = next;
    if (!_controller.isClosed) _controller.add(next);
    transport.broadcast({'k': 'session', 'session': next.toMap()});
  }

  String _hostEndpoint() {
    // Prefer the endpoint remembered at connect time; fall back to the live
    // set in case of a reconnect under a new id.
    final remembered = _hostEndpointId;
    if (remembered != null &&
        transport.connectedEndpoints.contains(remembered)) {
      return remembered;
    }
    final ids = transport.connectedEndpoints;
    return ids.isEmpty ? '' : ids.first;
  }

  void _onEndpointConnected(String endpointId) {
    if (!isHost) _hostEndpointId = endpointId;
    if (isHost) {
      // Push the current state to the freshly-connected peer so it renders the
      // lobby immediately, even before its own join is processed.
      final s = _current;
      if (s != null) {
        transport.sendToEndpoint(
            endpointId, {'k': 'session', 'session': s.toMap()});
      }
    } else {
      // We (peer) connected to the host — announce ourselves into the roster.
      transport.sendToEndpoint(
          endpointId, {'k': 'join', 'id': selfId, 'name': selfName});
    }
  }

  void _onEndpointDisconnected(String endpointId) {
    // A drop leaves the player in the roster: the pure model owns no removal
    // rule and yanking someone mid-round would scramble the leaderboard. Lobby
    // drops are a known limitation, matching the Telephone offline flow.
  }

  void _onMessage(String endpointId, Map<String, dynamic> message) {
    final kind = message['k'] as String?;
    if (isHost) {
      final s = _current;
      if (s == null) return;
      switch (kind) {
        case 'join':
          final id = message['id'] as String?;
          final name = message['name'] as String? ?? 'Player';
          if (id != null) _apply(s.withPlayerJoined(id, name));
          break;
        case 'pop':
          // A mirror claims a tap — the host's controller adjudicates
          // (first claim wins) and answers via publishPop.
          _emitRace(ArRaceEvent(
            ArRaceEventType.popClaim,
            objectId: message['id'] as String?,
            playerId: message['by'] as String?,
          ));
          break;
      }
    } else {
      switch (kind) {
        case 'session':
          final raw = message['session'];
          if (raw is Map) {
            _current = BlitzSession.fromMap(Map<String, dynamic>.from(raw));
            if (!_controller.isClosed) _controller.add(_current);
          }
          break;
        case 'go':
          _emitRace(const ArRaceEvent(ArRaceEventType.go));
          break;
        case 'spawn':
          final raw = message['o'];
          if (raw is Map) {
            _emitRace(ArRaceEvent(
              ArRaceEventType.spawn,
              object: ArRaceObject.fromMap(Map<String, dynamic>.from(raw)),
            ));
          }
          break;
        case 'popped':
          _emitRace(ArRaceEvent(
            ArRaceEventType.pop,
            objectId: message['id'] as String?,
            playerId: message['by'] as String?,
            value: (message['v'] as num?)?.toInt() ?? 0,
            isBomb: message['b'] as bool? ?? false,
          ));
          break;
        case 'escaped':
          _emitRace(ArRaceEvent(
            ArRaceEventType.escape,
            objectId: message['id'] as String?,
          ));
          break;
        case 'objects':
          final raw = message['list'];
          if (raw is List) {
            _emitRace(ArRaceEvent(
              ArRaceEventType.snapshot,
              objects: raw
                  .whereType<Map>()
                  .map((m) =>
                      ArRaceObject.fromMap(Map<String, dynamic>.from(m)))
                  .toList(),
            ));
          }
          break;
      }
    }
  }

  Future<void> dispose() async {
    _roundTimer?.cancel();
    await transport.dispose();
    if (!_controller.isClosed) await _controller.close();
    if (!_raceEvents.isClosed) await _raceEvents.close();
  }
}
