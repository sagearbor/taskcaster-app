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

  // HOST: which player id each connected endpoint belongs to, learned from that
  // endpoint's `join`. Lets a disconnect flag the right player (see finding 1).
  final Map<String, String> _endpointToPlayer = {};

  // SEEKER: true once we've announced our join at least once. Gates the
  // self-heal that re-sends the join if a snapshot arrives without us in it.
  bool _joinAnnounced = false;

  // Emits the endpoint id whenever a link drops, so UI (e.g. the join screen's
  // "connecting" state) can react to a disconnect instead of hanging.
  final _disconnectController = StreamController<String>.broadcast();

  bool _disposed = false;

  bool get isHost => role == ClueRole.host;
  ClueHuntSession? get current => _current;

  /// Fires with the dropped endpoint id every time a connection is lost.
  Stream<String> get disconnections => _disconnectController.stream;

  /// How many times a seeker retries its lobby `join` before giving up, and the
  /// per-attempt backoff. Small so a transient send failure heals within a
  /// second without a visible stall.
  static const int _joinAttempts = 3;
  static Duration _joinBackoff(int attempt) =>
      Duration(milliseconds: 200 * (attempt + 1));

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

  /// HOST escape hatch: the current hider has gone dark during HIDING (their
  /// phone dropped, or they're stalling), leaving everyone stuck on
  /// "X is hiding…". Hand the hider role to the next connected player and
  /// re-broadcast, WITHOUT advancing the round. No-op off the hiding phase.
  void skipHider() {
    if (!isHost) return;
    final s = _current;
    if (s == null || s.phase != CluePhase.hiding) return;
    _resetHeat();
    _apply(s.hiderSkipped());
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
  /// The verdict names the exact claimant it applies to ([claimId]) so a stale
  /// confirm can never award a claim the hider didn't actually approve.
  void confirmFind() {
    final claimId = _current?.pendingClaimBy;
    _hiderAction(
      apply: (s) => s.claimConfirmed(now: _now(), expectClaimant: claimId),
      message: {'k': 'confirm', 'claimId': claimId},
    );
  }

  /// HIDER: reject the pending claim — clear the slot so seeking resumes. Carries
  /// the exact claimant ([claimId]) so a stale reject can't drop a newer claim.
  void rejectFind() {
    final claimId = _current?.pendingClaimBy;
    _hiderAction(
      apply: (s) => s.claimRejected(expectClaimant: claimId),
      message: {'k': 'reject', 'claimId': claimId},
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
      _throttledHeatSend(clamped);
    } else {
      // Peer-hider: reflect locally for our own UI and forward to the host,
      // which validates and relays to the seekers. The slider fires ~60+ frames
      // a second, so the peer→host path is throttled with the SAME coalescing
      // (immediate + trailing-latest, ≤4/sec) as the host→seeker relay — a burst
      // of frames can never flood the link.
      _setLocalHeat(clamped);
      _throttledHeatSend(clamped);
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

  /// Emit a heat value on the outbound path at most once per [_heatMinGapMs]. A
  /// burst coalesces into a single trailing send carrying the latest value. Used
  /// in BOTH directions: the host→seekers broadcast and the peer-hider→host
  /// forward, so neither can flood the link with per-frame slider updates.
  void _throttledHeatSend(double value) {
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

  /// Deliver one heat frame the right way for this device's role: the host
  /// broadcasts it to every seeker; a peer-hider forwards it to the host, which
  /// validates and relays.
  void _sendHeat(double value) {
    if (isHost) {
      transport.broadcast({'k': 'heat', 'v': value}).catchError((Object e) =>
          NearbyDiagnostics.instance.log('heat send failed: $e'));
    } else {
      _sendToHost({'k': 'heat', 'v': value});
    }
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
      // We connected to the host — announce ourselves into the roster, retrying
      // on failure so a single dropped send can't leave us invisible.
      unawaited(_announceJoin(endpointId));
    }
  }

  /// SEEKER: send our `join` with bounded retries + backoff. A fire-and-forget
  /// one-shot could silently fail (the host never learns we exist, and every
  /// action we send is discarded); retrying heals that transient failure.
  Future<void> _announceJoin(String endpointId) async {
    _joinAnnounced = true;
    final msg = {'k': 'join', 'id': selfId, 'name': selfName};
    for (var attempt = 0; attempt < _joinAttempts; attempt++) {
      if (_disposed) return;
      try {
        await transport.sendToEndpoint(endpointId, msg);
        return; // sent — the self-heal covers the rare "sent but lost" case.
      } catch (e) {
        NearbyDiagnostics.instance
            .log('clue join attempt ${attempt + 1} failed: $e');
        await Future<void>.delayed(_joinBackoff(attempt));
      }
    }
    NearbyDiagnostics.instance.log('clue join gave up after $_joinAttempts tries');
  }

  /// SEEKER: re-announce our join to whatever host endpoint we have. Used by the
  /// self-heal when a snapshot arrives without us in the roster.
  void _resendJoin() {
    final host = _hostEndpoint();
    if (host.isEmpty) return;
    NearbyDiagnostics.instance.log('clue self-heal: re-announcing join');
    unawaited(_announceJoin(host));
  }

  void _onEndpointDisconnected(String endpointId) {
    if (!_disconnectController.isClosed) _disconnectController.add(endpointId);
    if (isHost) {
      // Keep the player in the roster (scores + history survive) but FLAG them
      // disconnected so the hider rotation skips them — a dropped phone can
      // never be handed the hider role and soft-lock the game. Re-joining clears
      // the flag (see withPlayerJoined).
      final playerId = _endpointToPlayer.remove(endpointId);
      final s = _current;
      if (playerId != null && s != null) {
        _apply(s.withPlayerConnection(playerId, false));
      }
    } else if (_hostEndpointId == endpointId) {
      _hostEndpointId = null;
    }
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
          if (id != null) {
            // Remember which endpoint owns this player so a later drop flags the
            // right one (and re-joining an existing player clears any stale
            // mapping for the same id from a previous endpoint).
            _endpointToPlayer
                .removeWhere((_, playerId) => playerId == id);
            _endpointToPlayer[endpointId] = id;
            _apply(s.withPlayerJoined(id, name));
          }
          break;
        case 'heat':
          // Only the current hider may drive heat, and only while seeking.
          final v = (message['v'] as num?)?.toDouble();
          if (v == null) break;
          if (s.phase != CluePhase.seeking) break;
          // Trust: the sender's UI only exposes the slider when it is the hider.
          _setLocalHeat(v.clamp(0.0, 1.0));
          _throttledHeatSend(v.clamp(0.0, 1.0));
          break;
        case 'beginSeeking':
          _apply(s.beganSeeking(now: _now()));
          break;
        case 'foundClaim':
          final by = message['by'] as String?;
          if (by != null) _apply(s.withClaim(by));
          break;
        case 'confirm':
          // Apply ONLY if the verdict's claimant still matches the pending slot;
          // a late confirm for an already-cleared claim is ignored (older peers
          // that omit 'claimId' fall back to the unconditional behaviour).
          _apply(s.claimConfirmed(
              now: _now(), expectClaimant: message['claimId'] as String?));
          break;
        case 'reject':
          _apply(s.claimRejected(expectClaimant: message['claimId'] as String?));
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
            // Self-heal: if we've announced our join but the authoritative
            // roster still doesn't list us, our join was lost — re-send it.
            final s = _current;
            if (_joinAnnounced &&
                s != null &&
                !s.players.any((p) => p.id == selfId)) {
              _resendJoin();
            }
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
    // Idempotent: a screen that backs out mid-`startHosting()`/`startDiscovery()`
    // disposes the repo both from State.dispose and again after the await
    // resolves unmounted (finding 5), so a double dispose must be safe.
    if (_disposed) return;
    _disposed = true;
    _heatTimer?.cancel();
    await transport.dispose();
    if (!_controller.isClosed) await _controller.close();
    if (!_heatController.isClosed) await _heatController.close();
    if (!_disconnectController.isClosed) await _disconnectController.close();
  }
}
