import 'dart:async';

import '../../../../core/models/telephone_session.dart';
import '../../../../core/utils/friendly_errors.dart';
import '../../domain/nearby_cast_label.dart';
import '../../domain/repositories/telephone_repository.dart';
import '../datasources/nearby_telephone_transport.dart';

enum NearbyRole { host, peer }

/// A [TelephoneRepository] whose transport is Google Nearby Connections instead
/// of Firestore — i.e. fully offline local multiplayer.
///
/// It is **host-authoritative**, mirroring the Firestore flow exactly:
///  * The HOST holds the one true [TelephoneSession]. Every mutation runs the
///    same pure model methods used online ([TelephoneSession.started],
///    [TelephoneSession.withPlayerJoined], [TelephoneSession.withSubmission])
///    and then broadcasts `session.toMap()` to all connected peers.
///  * PEERS never mutate locally. They receive the authoritative session map,
///    rebuild it via [TelephoneSession.fromMap], and drive the *unchanged* game
///    UI. Their actions (join, submit) are sent to the host as small JSON
///    messages, which the host applies and re-broadcasts.
///
/// The shared [TelephoneBloc] and the session/lobby/play/reveal screens work
/// against this verbatim — they only ever call [watchSession], [startGame] and
/// [submitEntry].
class NearbyTelephoneRepository implements TelephoneRepository {
  NearbyTelephoneRepository._({
    required this.role,
    required this.transport,
    required this.selfUid,
    required this.selfName,
    TelephoneSession? initialSession,
  }) : _current = initialSession {
    transport.onMessage = _onMessage;
    transport.onEndpointConnected = _onEndpointConnected;
    transport.onEndpointDisconnected = _onEndpointDisconnected;
  }

  /// Create a host repository that owns [session] (already built with the
  /// creator present in the lobby).
  factory NearbyTelephoneRepository.host({
    required NearbyTelephoneTransport transport,
    required TelephoneSession session,
  }) {
    return NearbyTelephoneRepository._(
      role: NearbyRole.host,
      transport: transport,
      selfUid: session.creatorUid,
      selfName: session.players.isNotEmpty
          ? session.players.first.displayName
          : 'Host',
      initialSession: session,
    );
  }

  /// Create a peer repository. [selfUid] is this device's per-session player id.
  factory NearbyTelephoneRepository.peer({
    required NearbyTelephoneTransport transport,
    required String selfUid,
    required String selfName,
  }) {
    return NearbyTelephoneRepository._(
      role: NearbyRole.peer,
      transport: transport,
      selfUid: selfUid,
      selfName: selfName,
    );
  }

  final NearbyRole role;
  final NearbyTelephoneTransport transport;
  final String selfUid;
  final String selfName;

  TelephoneSession? _current;
  final _controller = StreamController<TelephoneSession?>.broadcast();

  bool get isHost => role == NearbyRole.host;

  /// Current authoritative/known session id, once one exists.
  String? get sessionId => _current?.id;

  // ---- Offline-only entry points (used by the lobby/join screens) ----------

  /// HOST: start advertising so peers can discover this game. Returns false on
  /// unsupported platforms or if advertising could not start.
  Future<bool> startHosting() {
    return transport.startAdvertising(_advertisedName());
  }

  /// PEER: live list of nearby hosts.
  Stream<List<NearbyDevice>> get discoveredDevices =>
      transport.discoveredDevices;

  /// PEER: begin scanning for hosts.
  Future<bool> startDiscovery() => transport.startDiscovery(selfName);

  /// PEER: connect to a chosen host. The join handshake + first session arrive
  /// asynchronously via [watchSession].
  Future<bool> connect(String endpointId) => transport.connect(endpointId);

  /// The Nearby advertising endpoint name. We "cast" structured game info here
  /// (host name + game type + session fingerprint) so a passive discoverer can
  /// show a meaningful one-tap-join banner before any connection is opened.
  /// [NearbyCastLabel.encode] keeps it under Nearby's short length budget.
  String _advertisedName() {
    final session = _current;
    final hostName = session != null && session.players.isNotEmpty
        ? session.players.first.displayName
        : selfName;
    return NearbyCastLabel.encode(
      hostName: hostName,
      gameType: NearbyGameType.telephone,
      sessionId: session?.id,
    );
  }

  // ---- TelephoneRepository -------------------------------------------------

  @override
  Stream<TelephoneSession?> watchSession(String sessionId) async* {
    yield _current;
    yield* _controller.stream;
  }

  @override
  Future<void> startGame(String sessionId) async {
    if (!isHost) return; // Only the host may start; peers have no Start button.
    final s = _current;
    if (s == null) return;
    _apply(s.started());
  }

  @override
  Future<void> submitEntry({
    required String sessionId,
    required String uid,
    required String content,
  }) async {
    if (isHost) {
      final s = _current;
      if (s == null) return;
      _apply(s.withSubmission(uid, content));
    } else {
      await _sendToHost({'k': 'submit', 'uid': uid, 'content': content});
    }
  }

  /// Offline play never types an invite code — discovery handles addressing —
  /// so these are not part of the Nearby flow.
  @override
  Future<({String sessionId, String inviteCode})> createSession({
    required String creatorUid,
    required String creatorName,
    String? gameName,
    TelephoneGameMode gameMode = TelephoneGameMode.classicTelephone,
  }) {
    throw UnsupportedError(
        'Offline games are created via NearbyTelephoneRepository.host');
  }

  @override
  Future<void> submitRating({
    required String sessionId,
    required String raterUid,
    required String targetUid,
    required int value,
  }) async {
    if (isHost) {
      final s = _current;
      if (s == null) return;
      _apply(s.withRating(
          raterUid: raterUid, targetUid: targetUid, value: value));
    } else {
      await _sendToHost({
        'k': 'rate',
        'raterUid': raterUid,
        'targetUid': targetUid,
        'value': value,
      });
    }
  }

  @override
  Future<void> playAgain(String sessionId) async {
    if (isHost) {
      final s = _current;
      if (s == null) return;
      _apply(s.playAgain());
    } else {
      await _sendToHost({'k': 'again'});
    }
  }

  @override
  Future<void> removePlayer({
    required String sessionId,
    required String uid,
  }) async {
    // Host kick isn't wired into the offline Nearby flow yet — no-op so the
    // shared session screen's kick control can't crash an offline game.
  }

  @override
  Future<String> joinSession({
    required String inviteCode,
    required String uid,
    required String displayName,
  }) {
    throw UnsupportedError(
        'Offline games are joined via discovery, not an invite code');
  }

  // ---- Internals -----------------------------------------------------------

  /// HOST: set the authoritative session, push it to local UI, and broadcast.
  void _apply(TelephoneSession next) {
    _current = next;
    if (!_controller.isClosed) _controller.add(next);
    transport.broadcast({'k': 'session', 'session': next.toMap()});
  }

  String _hostEndpoint() {
    // A peer is connected to exactly one endpoint: the host.
    final ids = transport.connectedEndpoints;
    return ids.isEmpty ? '' : ids.first;
  }

  /// PEER: deliver one action message to the host — failing FAST and LOUD.
  ///
  /// Before the transport was hardened, sending with a dropped/never-completed
  /// connection hung the caller's Future forever, which is exactly the field
  /// bug "the joiner's Submit button did nothing". Now we throw a
  /// [StateError] whose message is already player-ready copy, so the bloc can
  /// surface it verbatim in a SnackBar and the submit button stays usable for
  /// a retry. Messages stay small; chunking/time-boxing is the transport's job.
  Future<void> _sendToHost(Map<String, dynamic> message) async {
    if (!transport.hasConnection) {
      throw StateError(FriendlyErrors.nearbyHostLost);
    }
    try {
      await transport.sendToEndpoint(_hostEndpoint(), message);
    } catch (e) {
      // The transport already logged the specifics to NearbyDiagnostics —
      // the player just needs to know what to do next.
      throw StateError(FriendlyErrors.nearbyHostUnreachable);
    }
  }

  void _onEndpointConnected(String endpointId) {
    if (isHost) {
      // Push the current lobby to the freshly-connected peer immediately so it
      // can render even before its own join is processed.
      final s = _current;
      if (s != null) {
        transport.sendToEndpoint(endpointId, {'k': 'session', 'session': s.toMap()});
      }
    } else {
      // We (peer) just connected to the host — announce ourselves so the host
      // adds us to the lobby roster.
      transport.sendToEndpoint(
          endpointId, {'k': 'join', 'uid': selfUid, 'name': selfName});
    }
  }

  void _onEndpointDisconnected(String endpointId) {
    // Host: a peer dropped. We intentionally leave them in the roster — the
    // pure model owns no removal rule, and dropping a player mid-game would
    // break chain assignment. Lobby-phase drops are a known limitation.
  }

  void _onMessage(String endpointId, Map<String, dynamic> message) {
    final kind = message['k'] as String?;
    if (isHost) {
      final s = _current;
      if (s == null) return;
      switch (kind) {
        case 'join':
          final uid = message['uid'] as String?;
          final name = message['name'] as String? ?? 'Player';
          if (uid != null) _apply(s.withPlayerJoined(uid, name));
          break;
        case 'submit':
          final uid = message['uid'] as String?;
          final content = message['content'] as String? ?? '';
          if (uid != null) _apply(s.withSubmission(uid, content));
          break;
        case 'rate':
          final raterUid = message['raterUid'] as String?;
          final targetUid = message['targetUid'] as String?;
          final value = (message['value'] as num?)?.toInt();
          if (raterUid != null && targetUid != null && value != null) {
            _apply(s.withRating(
                raterUid: raterUid, targetUid: targetUid, value: value));
          }
          break;
        case 'again':
          _apply(s.playAgain());
          break;
      }
    } else {
      if (kind == 'session') {
        final raw = message['session'];
        if (raw is Map) {
          _current =
              TelephoneSession.fromMap(Map<String, dynamic>.from(raw));
          if (!_controller.isClosed) _controller.add(_current);
        }
      }
    }
  }

  Future<void> dispose() async {
    await transport.dispose();
    if (!_controller.isClosed) await _controller.close();
  }
}
