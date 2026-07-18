import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/features/clue_hunt/data/datasources/clue_hunt_transport.dart';
import 'package:taskcaster_app/features/clue_hunt/data/repositories/clue_hunt_repository.dart';
import 'package:taskcaster_app/features/clue_hunt/domain/entities/clue_hunt_session.dart';

/// In-memory [ClueHuntTransport] for host-authoritative tests: records every
/// broadcast and direct send, and lets a test inject inbound messages and
/// connection events as if they arrived over Nearby.
class FakeClueHuntTransport implements ClueHuntTransport {
  void Function(String endpointId, Map<String, dynamic> message)? _onMessage;
  void Function(String endpointId)? _onConnected;
  void Function(String endpointId)? _onDisconnected;

  final List<Map<String, dynamic>> broadcasts = [];
  final List<({String endpointId, Map<String, dynamic> msg})> sent = [];
  final Set<String> _connected = {};
  final _devices = StreamController<List<NearbyDevice>>.broadcast();

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
    simulateConnect(endpointId);
    return true;
  }

  @override
  Future<void> sendToEndpoint(
      String endpointId, Map<String, dynamic> message) async {
    sent.add((endpointId: endpointId, msg: message));
  }

  @override
  Future<void> broadcast(Map<String, dynamic> message) async {
    broadcasts.add(message);
  }

  @override
  Future<void> dispose() async {
    if (!_devices.isClosed) await _devices.close();
  }

  // ---- test helpers --------------------------------------------------------
  void simulateConnect(String endpointId) {
    _connected.add(endpointId);
    _onConnected?.call(endpointId);
  }

  void simulateDisconnect(String endpointId) {
    _connected.remove(endpointId);
    _onDisconnected?.call(endpointId);
  }

  void inject(String endpointId, Map<String, dynamic> message) =>
      _onMessage?.call(endpointId, message);

  ClueHuntSession lastSession() => ClueHuntSession.fromMap(
      Map<String, dynamic>.from(
          broadcasts.lastWhere((m) => m['k'] == 'session')['session'] as Map));
}

ClueHuntRepository _host(FakeClueHuntTransport t, {int Function()? now}) {
  return ClueHuntRepository.host(
    transport: t,
    session: ClueHuntSession.createHost(hostId: 'h', hostName: 'Mom'),
    now: now ?? () => 1000,
  );
}

void main() {
  group('Host authority — roster & lifecycle', () {
    late FakeClueHuntTransport transport;
    late ClueHuntRepository host;

    setUp(() {
      transport = FakeClueHuntTransport();
      host = _host(transport);
    });

    tearDown(() => host.dispose());

    test('a seeker joining is added to the roster and broadcast', () {
      transport.inject('e1', {'k': 'join', 'id': 'p1', 'name': 'Ava'});
      expect(host.current!.players.map((p) => p.id), containsAll(['h', 'p1']));
      expect(transport.lastSession().players.any((p) => p.id == 'p1'), isTrue);
    });

    test('startGame needs at least two players', () {
      host.startGame(); // only the host so far
      expect(host.current!.phase, CluePhase.lobby);
      transport.inject('e1', {'k': 'join', 'id': 'p1', 'name': 'Ava'});
      host.startGame();
      expect(host.current!.phase, CluePhase.hiding);
      expect(host.current!.hiderId, 'h'); // host hides first
    });

    test('on a seeker connecting, the host pushes the current session', () {
      transport.simulateConnect('e1');
      expect(transport.sent, isNotEmpty);
      expect(transport.sent.last.msg['k'], 'session');
    });

    test('a dropped seeker stays in the roster (no mid-game removal)', () {
      transport.inject('e1', {'k': 'join', 'id': 'p1', 'name': 'Ava'});
      transport.simulateDisconnect('e1');
      expect(host.current!.players.any((p) => p.id == 'p1'), isTrue);
    });
  });

  group('Host authority — claim, confirm, reject, rotate', () {
    late FakeClueHuntTransport transport;
    late int clock;
    late ClueHuntRepository host;

    setUp(() {
      transport = FakeClueHuntTransport();
      clock = 1000;
      host = _host(transport, now: () => clock);
      transport.inject('e1', {'k': 'join', 'id': 'p1', 'name': 'Ava'});
      transport.inject('e2', {'k': 'join', 'id': 'p2', 'name': 'Ben'});
      host.startGame(); // hiding, hider = h
    });

    tearDown(() => host.dispose());

    test('a seeker foundClaim sets the pending slot; first wins', () {
      host.beginSeeking(); // host is hider → applies locally
      transport.inject('e1', {'k': 'foundClaim', 'by': 'p1'});
      expect(host.current!.pendingClaimBy, 'p1');
      // A second claim while pending is ignored.
      transport.inject('e2', {'k': 'foundClaim', 'by': 'p2'});
      expect(host.current!.pendingClaimBy, 'p1');
    });

    test('confirm scores the finder by elapsed time and moves to roundResult',
        () {
      clock = 1000;
      host.beginSeeking();
      clock = 11000; // 10s later
      transport.inject('e1', {'k': 'foundClaim', 'by': 'p1'});
      host.confirmFind(); // host is the hider
      final s = host.current!;
      expect(s.phase, CluePhase.roundResult);
      expect(s.lastFinderId, 'p1');
      expect(s.lastAward, 850);
      expect(s.players.firstWhere((p) => p.id == 'p1').totalScore, 850);
    });

    test('reject clears the pending slot so seeking resumes', () {
      host.beginSeeking();
      transport.inject('e1', {'k': 'foundClaim', 'by': 'p1'});
      host.rejectFind();
      expect(host.current!.pendingClaimBy, isNull);
      expect(host.current!.phase, CluePhase.seeking);
    });

    test('nextRound rotates the hider and only works from a round result', () {
      host.beginSeeking();
      transport.inject('e1', {'k': 'foundClaim', 'by': 'p1'});
      host.nextRound(); // wrong phase (seeking) → ignored
      expect(host.current!.phase, CluePhase.seeking);
      host.confirmFind();
      host.nextRound();
      expect(host.current!.phase, CluePhase.hiding);
      expect(host.current!.hiderId, 'p1'); // rotated
      expect(host.current!.roundNumber, 2);
    });
  });

  group('Host authority — the hider role can be a peer', () {
    test('a peer-hider drives the game via messages once the role rotates', () {
      final transport = FakeClueHuntTransport();
      var clock = 1000;
      final host = _host(transport, now: () => clock);
      addTearDown(host.dispose);
      transport.inject('e1', {'k': 'join', 'id': 'p1', 'name': 'Ava'});
      host.startGame();
      host.beginSeeking();
      transport.inject('e1', {'k': 'foundClaim', 'by': 'p1'});
      host.confirmFind();
      host.nextRound(); // now p1 (a peer) is the hider

      expect(host.current!.hiderId, 'p1');
      // The peer-hider's beginSeeking arrives as a message and is applied.
      clock = 5000;
      transport.inject('e1', {'k': 'beginSeeking'});
      expect(host.current!.phase, CluePhase.seeking);
      expect(host.current!.roundStartEpochMs, 5000);
      // The host (now a seeker) can claim its own find directly.
      clock = 8000;
      host.claimFound();
      expect(host.current!.pendingClaimBy, 'h');
      // The peer-hider confirms via a message.
      transport.inject('e1', {'k': 'confirm'});
      expect(host.current!.phase, CluePhase.roundResult);
      expect(host.current!.lastFinderId, 'h');
    });
  });

  group('Heat relay & throttle', () {
    test('the host relays a hider heat drive to the seekers', () {
      final transport = FakeClueHuntTransport();
      final host = _host(transport);
      addTearDown(host.dispose);
      transport.inject('e1', {'k': 'join', 'id': 'p1', 'name': 'Ava'});
      host.startGame();
      host.beginSeeking();
      transport.broadcasts.clear();

      host.setHeat(0.7);
      final heatMsgs = transport.broadcasts.where((m) => m['k'] == 'heat');
      expect(heatMsgs, isNotEmpty);
      expect(heatMsgs.last['v'], 0.7);
    });

    test('heat is ignored outside seeking', () {
      final transport = FakeClueHuntTransport();
      final host = _host(transport);
      addTearDown(host.dispose);
      transport.inject('e1', {'k': 'join', 'id': 'p1', 'name': 'Ava'});
      host.startGame(); // hiding, not seeking
      transport.broadcasts.clear();
      host.setHeat(0.9);
      expect(transport.broadcasts.where((m) => m['k'] == 'heat'), isEmpty);
    });

    test('bursts of heat coalesce — only one immediate send, rest trailing', () {
      fakeAsync((async) {
        final transport = FakeClueHuntTransport();
        // A monotonically advancing clock so the throttle window behaves.
        var t = 1000;
        final host = ClueHuntRepository.host(
          transport: transport,
          session: ClueHuntSession.createHost(hostId: 'h', hostName: 'Mom'),
          now: () => t,
        );
        addTearDown(host.dispose);
        transport.inject('e1', {'k': 'join', 'id': 'p1', 'name': 'Ava'});
        host.startGame();
        host.beginSeeking();
        transport.broadcasts.clear();

        // Rapid drives within the same throttle window.
        host.setHeat(0.2);
        host.setHeat(0.5);
        host.setHeat(0.8);
        // Exactly one immediate send so far.
        expect(transport.broadcasts.where((m) => m['k'] == 'heat').length, 1);

        // Let the trailing timer fire; it carries the LATEST value.
        t = 1300;
        async.elapse(const Duration(milliseconds: 300));
        final heat = transport.broadcasts.where((m) => m['k'] == 'heat');
        expect(heat.length, 2);
        expect(heat.last['v'], 0.8);
      });
    });
  });

  group('Connectivity, liveness & the skip escape hatch (finding 1)', () {
    test('a dropped seeker is flagged disconnected and re-broadcast', () {
      final transport = FakeClueHuntTransport();
      final host = _host(transport);
      addTearDown(host.dispose);
      transport.inject('e1', {'k': 'join', 'id': 'p1', 'name': 'Ava'});
      transport.simulateDisconnect('e1');
      final p1 = host.current!.players.firstWhere((p) => p.id == 'p1');
      expect(p1.connected, isFalse);
      // Kept in the roster (scores/history survive) — just flagged.
      expect(host.current!.players.length, 2);
      expect(
          transport
              .lastSession()
              .players
              .firstWhere((p) => p.id == 'p1')
              .connected,
          isFalse);
    });

    test('a re-join after a drop clears the disconnected flag', () {
      final transport = FakeClueHuntTransport();
      final host = _host(transport);
      addTearDown(host.dispose);
      transport.inject('e1', {'k': 'join', 'id': 'p1', 'name': 'Ava'});
      transport.simulateDisconnect('e1');
      transport.inject('e9', {'k': 'join', 'id': 'p1', 'name': 'Ava'});
      expect(host.current!.players.firstWhere((p) => p.id == 'p1').connected,
          isTrue);
    });

    test('nextRound rotation skips a hider that dropped before their round', () {
      final transport = FakeClueHuntTransport();
      var clock = 1000;
      final host = _host(transport, now: () => clock);
      addTearDown(host.dispose);
      transport.inject('e1', {'k': 'join', 'id': 'p1', 'name': 'Ava'});
      transport.inject('e2', {'k': 'join', 'id': 'p2', 'name': 'Ben'});
      host.startGame();
      host.beginSeeking();
      transport.inject('e1', {'k': 'foundClaim', 'by': 'p1'});
      host.confirmFind();
      // p1 (the next hider in order) drops before the rotation reaches them.
      transport.simulateDisconnect('e1');
      host.nextRound();
      expect(host.current!.hiderId, 'p2',
          reason: 'the role skips the departed p1');
    });

    test('skipHider hands a stalled/departed hider role to the next connected '
        'player without advancing the round, and re-broadcasts', () {
      final transport = FakeClueHuntTransport();
      var clock = 1000;
      final host = _host(transport, now: () => clock);
      addTearDown(host.dispose);
      transport.inject('e1', {'k': 'join', 'id': 'p1', 'name': 'Ava'});
      transport.inject('e2', {'k': 'join', 'id': 'p2', 'name': 'Ben'});
      host.startGame();
      host.beginSeeking();
      transport.inject('e1', {'k': 'foundClaim', 'by': 'p1'});
      host.confirmFind();
      host.nextRound(); // hiding, hider = p1
      expect(host.current!.hiderId, 'p1');
      final round = host.current!.roundNumber;
      // p1's phone goes dark; the host taps "skip their turn".
      transport.simulateDisconnect('e1');
      transport.broadcasts.clear();
      host.skipHider();
      expect(host.current!.hiderId, 'p2');
      expect(host.current!.roundNumber, round,
          reason: 'skip does NOT advance the round');
      expect(host.current!.phase, CluePhase.hiding);
      expect(transport.lastSession().hiderId, 'p2',
          reason: 'seekers are unstuck via the re-broadcast');
    });

    test('skipHider is ignored outside the hiding phase', () {
      final transport = FakeClueHuntTransport();
      final host = _host(transport);
      addTearDown(host.dispose);
      transport.inject('e1', {'k': 'join', 'id': 'p1', 'name': 'Ava'});
      host.startGame();
      host.beginSeeking(); // now seeking
      host.skipHider();
      expect(host.current!.phase, CluePhase.seeking);
      expect(host.current!.hiderId, 'h');
    });

    test('a disconnect is surfaced on the disconnections stream (finding 7)',
        () async {
      final transport = FakeClueHuntTransport();
      final host = _host(transport);
      addTearDown(host.dispose);
      final lost = <String>[];
      final sub = host.disconnections.listen(lost.add);
      addTearDown(sub.cancel);
      transport.inject('e1', {'k': 'join', 'id': 'p1', 'name': 'Ava'});
      transport.simulateDisconnect('e1');
      await Future<void>.delayed(Duration.zero);
      expect(lost, contains('e1'));
    });
  });

  group('Stale confirm/reject carry the claimant id (finding 3)', () {
    test('a stale confirm for an already-rejected claim never scores the wrong '
        'seeker', () {
      final transport = FakeClueHuntTransport();
      var clock = 1000;
      final host = _host(transport, now: () => clock);
      addTearDown(host.dispose);
      transport.inject('e1', {'k': 'join', 'id': 'p1', 'name': 'Ava'});
      transport.inject('e2', {'k': 'join', 'id': 'p2', 'name': 'Ben'});
      host.startGame();
      host.beginSeeking();
      transport.inject('e1', {'k': 'foundClaim', 'by': 'p1'});
      host.confirmFind();
      host.nextRound(); // p1 becomes the (peer) hider
      expect(host.current!.hiderId, 'p1');
      transport.inject('e1', {'k': 'beginSeeking'});
      expect(host.current!.phase, CluePhase.seeking);

      // A (the host, now a seeker) claims; the peer-hider rejects A.
      host.claimFound();
      expect(host.current!.pendingClaimBy, 'h');
      transport.inject('e1', {'k': 'reject', 'claimId': 'h'});
      expect(host.current!.pendingClaimBy, isNull);

      // B (p2) claims.
      transport.inject('e2', {'k': 'foundClaim', 'by': 'p2'});
      expect(host.current!.pendingClaimBy, 'p2');

      // A STALE confirm for h (in flight from before the reject) is IGNORED,
      // because the pending claim has moved on to p2.
      transport.inject('e1', {'k': 'confirm', 'claimId': 'h'});
      expect(host.current!.phase, CluePhase.seeking,
          reason: 'the stale confirm is dropped');
      expect(host.current!.pendingClaimBy, 'p2');
      expect(host.current!.players.firstWhere((p) => p.id == 'h').totalScore, 0,
          reason: 'h was rejected and must not be awarded');

      // The correct confirm for p2 scores p2.
      transport.inject('e1', {'k': 'confirm', 'claimId': 'p2'});
      expect(host.current!.phase, CluePhase.roundResult);
      expect(host.current!.lastFinderId, 'p2');
    });
  });

  group('Peer-hider heat is throttled on the peer→host path too (finding 2)',
      () {
    test('a burst of peer slider frames coalesces into immediate + trailing', () {
      fakeAsync((async) {
        final transport = FakeClueHuntTransport();
        var t = 1000;
        final peer = ClueHuntRepository.seeker(
          transport: transport,
          selfId: 'p1',
          selfName: 'Ava',
          now: () => t,
        );
        addTearDown(peer.dispose);
        transport.simulateConnect('host'); // also announces join
        transport.sent.clear(); // count only heat frames from here

        // Rapid slider frames within one throttle window.
        peer.setHeat(0.2);
        peer.setHeat(0.5);
        peer.setHeat(0.8);
        var heat = transport.sent.where((s) => s.msg['k'] == 'heat').toList();
        expect(heat.length, 1, reason: 'exactly one immediate send');
        expect(heat.single.endpointId, 'host');

        // The trailing timer fires with the LATEST value.
        t = 1300;
        async.elapse(const Duration(milliseconds: 300));
        heat = transport.sent.where((s) => s.msg['k'] == 'heat').toList();
        expect(heat.length, 2);
        expect(heat.last.msg['v'], 0.8);
        expect(heat.every((s) => s.endpointId == 'host'), isTrue);
      });
    });
  });

  group('Join is resilient (finding 4)', () {
    test('a seeker re-announces its join when a snapshot arrives without it '
        '(self-heal)', () {
      final transport = FakeClueHuntTransport();
      final peer = ClueHuntRepository.seeker(
        transport: transport,
        selfId: 'p1',
        selfName: 'Ava',
      );
      addTearDown(peer.dispose);
      peer.connect('host'); // announces the (lost) join, marks _joinAnnounced
      transport.sent.clear();

      // The host's snapshot does NOT contain us — our join must have been lost.
      final hostSession =
          ClueHuntSession.createHost(hostId: 'h', hostName: 'Mom');
      transport.inject('host', {'k': 'session', 'session': hostSession.toMap()});

      final joins = transport.sent.where((s) => s.msg['k'] == 'join').toList();
      expect(joins, isNotEmpty, reason: 'the seeker re-sends its join');
      expect(joins.last.msg['id'], 'p1');
    });

    test('a seeker does NOT re-announce when the snapshot already lists it', () {
      final transport = FakeClueHuntTransport();
      final peer = ClueHuntRepository.seeker(
        transport: transport,
        selfId: 'p1',
        selfName: 'Ava',
      );
      addTearDown(peer.dispose);
      peer.connect('host');
      transport.sent.clear();

      final withMe = ClueHuntSession.createHost(hostId: 'h', hostName: 'Mom')
          .withPlayerJoined('p1', 'Ava');
      transport.inject('host', {'k': 'session', 'session': withMe.toMap()});
      expect(transport.sent.where((s) => s.msg['k'] == 'join'), isEmpty);
    });

    test('dispose is idempotent — safe to call twice (finding 5)', () async {
      final transport = FakeClueHuntTransport();
      final host = _host(transport);
      await host.dispose();
      await host.dispose(); // must not throw
    });
  });

  group('Seeker (peer) behaviour', () {
    test('a peer never broadcasts and forwards actions to the host', () async {
      final transport = FakeClueHuntTransport();
      final peer = ClueHuntRepository.seeker(
        transport: transport,
        selfId: 'p1',
        selfName: 'Ava',
      );
      addTearDown(peer.dispose);

      await peer.connect('host'); // announces 'join'
      expect(transport.sent.first.msg['k'], 'join');

      peer.claimFound();
      final claim = transport.sent.lastWhere((s) => s.msg['k'] == 'foundClaim');
      expect(claim.endpointId, 'host');
      expect(claim.msg['by'], 'p1');
      expect(transport.broadcasts, isEmpty);
      expect(peer.current, isNull);
    });

    test('a peer adopts the host authoritative session from a broadcast', () {
      final transport = FakeClueHuntTransport();
      final peer = ClueHuntRepository.seeker(
        transport: transport,
        selfId: 'p1',
        selfName: 'Ava',
      );
      addTearDown(peer.dispose);

      final hostSession = ClueHuntSession.createHost(hostId: 'h', hostName: 'M')
          .withPlayerJoined('p1', 'Ava')
          .started();
      transport.inject('host', {'k': 'session', 'session': hostSession.toMap()});
      expect(peer.current, equals(hostSession));
      expect(peer.isHider, isFalse); // host is the first hider
    });

    test('a peer surfaces received heat on its heat stream', () async {
      final transport = FakeClueHuntTransport();
      final peer = ClueHuntRepository.seeker(
        transport: transport,
        selfId: 'p1',
        selfName: 'Ava',
      );
      addTearDown(peer.dispose);

      final heats = <double>[];
      final sub = peer.watchHeat().listen(heats.add);
      addTearDown(sub.cancel);

      transport.inject('host', {'k': 'heat', 'v': 0.6});
      await Future<void>.delayed(Duration.zero);
      expect(heats.last, 0.6);
    });
  });
}
