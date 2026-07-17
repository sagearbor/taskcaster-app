import 'dart:async';

import '../../../telephone/data/datasources/nearby_diagnostics.dart';
import '../../domain/entities/clue_hunt_session.dart';
import '../datasources/clue_hunt_transport.dart';

enum ClueRole { host, seeker }

/// The host-authoritative engine for an offline Clue Hunt.
///
/// Exactly like [BalloonBlitzRepository], the HOST phone holds the one true
/// [ClueHuntSession]: it applies the pure model mutations ([ClueHuntSession.
/// started], [claimConfirmed], [advancedRound] …) and broadcasts `session.toMap()`
/// to everyone. Non-host phones never mutate locally — they rebuild the session
/// from each broadcast and send their actions to the host as tiny JSON messages,
/// which the host applies and re-broadcasts.
///
/// The hider ROLE rotates every round ([ClueHuntSession.hiderId]) while the host
/// stays the permanent authority. Whoever is the current hider is the human
/// "sensor": they drive a warmer/colder slider whose value ([setHeat]) is
/// broadcast live to every seeker. Because heat updates many times a second, it
/// travels as its own throttled `heat` message (≤ ~4/sec) — it is deliberately
/// NOT part of the session snapshot, so frequent heat can never starve the
/// authoritative state broadcasts.
///
/// Wire protocol (all maps carry a `k` kind):
///  * seeker → host  `{'k':'join','id':..,'name':..}` — announce in the lobby
///  * hider  → host  `{'k':'heat','v':0.7}`           — live warmer/colder value
///  * hider  → host  `{'k':'beginSeeking'}`           — object hidden, hunt on
///  * seeker → host  `{'k':'foundClaim','by':..}`     — "I grabbed it!"
///  * hider  → host  `{'k':'confirm'}`                — approve the pending claim
///  * hider  → host  `{'k':'reject'}`                 — reject the pending claim
///  * host   → all   `{'k':'session','session':{…}}`  — full authoritative state
///  * host   → all   `{'k':'heat','v':0.7}`           — heat, relayed to seekers
class ClueHuntRepository {
  ClueHuntRepository._({
    required this.role,
    required this.transport,
    required this.selfId,
    required this.selfName,
    ClueHuntSession? initialSession,
    int Function()? now,
  })  : _current = initialSession,
        _now = now ?? (() => DateTime.now().millisecondsSinceEpoch) {
    transport.onMessage = _onMessage;
    transport.onEndpointConnected = _onEndpointConnected;
    transport.onEndpointDisconnected = _onEndpointDisconnected;
  }

  /// Create a host that owns [session] (already built with the host in the
  /// lobby). [now] is injectable so scoring/heat timing is deterministic.
  factory ClueHuntRepository.host({
    required ClueHuntTransport transport,
    required ClueHuntSession session,
    int Function()? now,
  }) {
    return ClueHuntRepository._(
      role: ClueRole.host,
      transport: transport,
      selfId: session.hostId,
      selfName: session.host?.name ?? 'Host',
      initialSession: session,
      now: now,
    );
  }

  /// Create a seeker/peer. [selfId] is this device's per-session player id.
  factory ClueHuntRepository.seeker({
    required ClueHuntTransport transport,
    required String selfId,
    required String selfName,
    int Function()? now,
  }) {
    return ClueHuntRepository._(
      role: ClueRole.seeker,
      transport: transport,
      selfId: selfId,
      selfName: selfName,
      now: now,
    );
  }

  final ClueRole role;
  final ClueHuntTransport transport;
  final String selfId;
  final String selfName;
  final int Function() _now;

  ClueHuntSession? _current;
  final _controller = StreamController<ClueHuntSession?>.broadcast();

  /// Live heat channel (0.0–1.0). On the host this echoes what the hider drives;
  /// on a seeker it carries the heat received from the host. Seeded at 0.
  double _heat = 0.0;
  final _heatController = StreamController<double>.broadcast();

  // Heat broadcast throttle (host side): at most one send per [_heatMinGapMs].
  static const int _heatMinGapMs = 250; // ~4 sends/sec
  int _lastHeatSendMs = -1 << 30; // far in the past so the first send is instant
  double? _pendingHeat;
  Timer? _heatTimer;

  String? _hostEndpointId; // seeker: remembered at connect time

  bool get isHost => role == ClueRole.host;
  ClueHuntSession? get current => _current;

  /// True when THIS device is the current round's hider (drives the slider,
  /// confirms/rejects finds). Recomputed from the authoritative session.
  bool get isHider => _current?.hiderId == selfId;

  // ---- Lobby plumbing ------------------------------------------------------

  /// HOST: start advertising so seekers can discover this hunt.
  Future<bool> startHosting() =>
      transport.startAdvertising("$selfName's Clue Hunt");

  /// SEEKER: live list of nearby hosts.
  Stream<List<NearbyDevice>> get discoveredDevices =>
      transport.discoveredDevices;

  /// SEEKER: start scanning for hosts.
  Future<bool> startDiscovery() => transport.startDiscovery(selfName);

  /// SEEKER: connect to a chosen host; the first session arrives via watchSession.
  Future<bool> connect(String endpointId) => transport.connect(endpointId);

  // ---- Live streams --------------------------------------------------------

  /// The authoritative session: the current value first, then every update.
  Stream<ClueHuntSession?> watchSession() async* {
    yield _current;
    yield* _controller.stream;
  }

  /// The live heat channel: the current value first, then every update.
  Stream<double> watchHeat() async* {
    yield _heat;
    yield* _heatController.stream;
  }

  double get heat => _heat;

  // ---- Host lifecycle (host-only) ------------------------------------------

  /// HOST: leave the lobby and begin round 1 (the host hides first).
  void startGame() {
    if (!isHost) return;
    final s = _current;
    if (s == null || s.phase != CluePhase.lobby) return;
    if (s.players.length < 2) return; // need at least a hider + a seeker
    _resetHeat();
    _apply(s.started());
  }

  /// HOST: advance past a round result — rotate the hider and begin the next
  /// round, or end the game after the final round.
  void nextRound() {
    if (!isHost) return;
    final s = _current;
    if (s == null || s.phase != CluePhase.roundResult) return;
    _resetHeat();
    _apply(s.advancedRound());
  }

  /// HOST: start a whole new game from the winner ceremony (scores cleared).
  void playAgain() {
    if (!isHost) return;
    final s = _current;
    if (s == null) return;
    _resetHeat();
    _apply(s.backToLobby());
  }

  // ---- Hider actions (work whether the hider is the host or a seeker) -------

  /// HIDER: the object is hidden — start the hunt (stamps the seek clock).
  void beginSeeking() {
    _hiderAction(
      apply: (s) => s.beganSeeking(now: _now()),
      message: const {'k': 'beginSeeking'},
    );
  }

  /// HIDER: confirm the pending claim — score the finder and freeze the result.
  void confirmFind() {
    _hiderAction(
      apply: (s) => s.claimConfirmed(now: _now()),
      message: const {'k': 'confirm'},
    );
  }

  /// HIDER: reject the pending claim — clear the slot so seeking resumes.
  void rejectFind() {
    _hiderAction(
      apply: (s) => s.claimRejected(),
      message: const {'k': 'reject'},
    );
  }

  /// HIDER: push a new warmer/colder value (0.0–1.0). Applied + relayed live;
  /// the broadcast is throttled so heat can never flood the link.
  void setHeat(double value) {
    final clamped = value.clamp(0.0, 1.0);
    if (isHost) {
      // We are the authority: only the current hider may drive heat, and only
      // while seeking.
      final s = _current;
      if (s == null || s.phase != CluePhase.seeking || s.hiderId != selfId) {
        return;
      }
      _setLocalHeat(clamped);
      _broadcastHeatThrottled(clamped);
    } else {
      // Peer-hider: reflect locally for our own UI and forward to the host,
      // which validates and relays to the seekers.
      _setLocalHeat(clamped);
      _sendToHost({'k': 'heat', 'v': clamped});
    }
  }

  // ---- Seeker action -------------------------------------------------------

  /// SEEKER: claim "Found it!" — I physically grabbed the object.
  void claimFound() {
    if (isHost) {
      final s = _current;
      if (s != null) _apply(s.withClaim(selfId));
    } else {
      _sendToHost({'k': 'foundClaim', 'by': selfId});
    }
  }

  // ---- Internals -----------------------------------------------------------

  void _hiderAction({
    required ClueHuntSession Function(ClueHuntSession) apply,
    required Map<String, dynamic> message,
  }) {
    if (isHost) {
      final s = _current;
      if (s != null) _apply(apply(s));
    } else {
      _sendToHost(message);
    }
  }

  void _apply(ClueHuntSession next) {
    _current = next;
    if (!_controller.isClosed) _controller.add(next);
    transport.broadcast({'k': 'session', 'session': next.toMap()}).catchError(
        (Object e) => NearbyDiagnostics.instance.log('session send failed: $e'));
  }

  void _setLocalHeat(double value) {
    _heat = value;
    if (!_heatController.isClosed) _heatController.add(value);
  }

  void _resetHeat() {
    _heatTimer?.cancel();
    _heatTimer = null;
    _pendingHeat = null;
    _lastHeatSendMs = -1 << 30;
    _setLocalHeat(0.0);
    if (isHost) {
      // Make sure seekers snap their meters back to cold at a round boundary.
      transport.broadcast({'k': 'heat', 'v': 0.0}).catchError((Object e) =>
          NearbyDiagnostics.instance.log('heat reset send failed: $e'));
    }
  }

  /// HOST: relay heat to all seekers, at most once per [_heatMinGapMs]. A burst
  /// coalesces into a single trailing send carrying the latest value.
  void _broadcastHeatThrottled(double value) {
    final nowMs = _now();
    final since = nowMs - _lastHeatSendMs;
    if (since >= _heatMinGapMs) {
      _lastHeatSendMs = nowMs;
      _sendHeat(value);
      return;
    }
    _pendingHeat = value;
    _heatTimer ??= Timer(Duration(milliseconds: _heatMinGapMs - since), () {
      _heatTimer = null;
      final pending = _pendingHeat;
      _pendingHeat = null;
      if (pending == null) return;
      _lastHeatSendMs = _now();
      _sendHeat(pending);
    });
  }

  void _sendHeat(double value) {
    transport.broadcast({'k': 'heat', 'v': value}).catchError((Object e) =>
        NearbyDiagnostics.instance.log('heat send failed: $e'));
  }

  void _sendToHost(Map<String, dynamic> message) {
    final host = _hostEndpoint();
    if (host.isEmpty) {
      NearbyDiagnostics.instance.log('clue action dropped: no host connection');
      return;
    }
    transport.sendToEndpoint(host, message).catchError((Object e) =>
        NearbyDiagnostics.instance.log('clue action send failed: $e'));
  }

  String _hostEndpoint() {
    final remembered = _hostEndpointId;
    if (remembered != null &&
        transport.connectedEndpoints.contains(remembered)) {
      return remembered;
    }
    final ids = transport.connectedEndpoints;
    return ids.isEmpty ? '' : ids.first;
  }

  void _onEndpointConnected(String endpointId) {
    if (isHost) {
      // Push current state to the freshly-connected seeker so it renders the
      // lobby immediately, even before its own join is processed.
      final s = _current;
      if (s != null) {
        transport.sendToEndpoint(
            endpointId, {'k': 'session', 'session': s.toMap()});
      }
    } else {
      _hostEndpointId = endpointId;
      // We connected to the host — announce ourselves into the roster.
      transport.sendToEndpoint(
          endpointId, {'k': 'join', 'id': selfId, 'name': selfName});
    }
  }

  void _onEndpointDisconnected(String endpointId) {
    // A drop leaves the player in the roster: the pure model owns no removal
    // rule and yanking someone mid-game would scramble scores and the rotation.
    // Lobby drops are a known limitation, matching the other offline flows.
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
        case 'heat':
          // Only the current hider may drive heat, and only while seeking.
          final v = (message['v'] as num?)?.toDouble();
          if (v == null) break;
          if (s.phase != CluePhase.seeking) break;
          // Trust: the sender's UI only exposes the slider when it is the hider.
          _setLocalHeat(v.clamp(0.0, 1.0));
          _broadcastHeatThrottled(v.clamp(0.0, 1.0));
          break;
        case 'beginSeeking':
          _apply(s.beganSeeking(now: _now()));
          break;
        case 'foundClaim':
          final by = message['by'] as String?;
          if (by != null) _apply(s.withClaim(by));
          break;
        case 'confirm':
          _apply(s.claimConfirmed(now: _now()));
          break;
        case 'reject':
          _apply(s.claimRejected());
          break;
      }
    } else {
      switch (kind) {
        case 'session':
          final raw = message['session'];
          if (raw is Map) {
            _current =
                ClueHuntSession.fromMap(Map<String, dynamic>.from(raw));
            if (!_controller.isClosed) _controller.add(_current);
          }
          break;
        case 'heat':
          final v = (message['v'] as num?)?.toDouble();
          if (v != null) _setLocalHeat(v.clamp(0.0, 1.0));
          break;
      }
    }
  }

  Future<void> dispose() async {
    _heatTimer?.cancel();
    await transport.dispose();
    if (!_controller.isClosed) await _controller.close();
    if (!_heatController.isClosed) await _heatController.close();
  }
}
