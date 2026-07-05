import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/services/ar/ar_engine.dart';
import 'package:taskcaster_app/core/services/ar/ar_race.dart';
import 'package:taskcaster_app/features/balloon_blitz/data/datasources/blitz_transport.dart';
import 'package:taskcaster_app/features/balloon_blitz/data/repositories/balloon_blitz_repository.dart';
import 'package:taskcaster_app/features/balloon_blitz/domain/entities/blitz_session.dart';

/// In-memory [BlitzTransport] for host-authoritative tests: records every
/// broadcast and direct send, and lets a test inject inbound messages and
/// connection events as if they arrived over Nearby.
class FakeBlitzTransport implements BlitzTransport {
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
}

void main() {
  group('Host-authoritative score aggregation', () {
    late FakeBlitzTransport transport;
    late BalloonBlitzRepository host;

    setUp(() {
      transport = FakeBlitzTransport();
      host = BalloonBlitzRepository.host(
        transport: transport,
        session: BlitzSession.createHost(hostId: 'h', hostName: 'Host'),
        now: () => 1000,
      );
    });

    tearDown(() => host.dispose());

    test('a peer joining is added to the roster and broadcast', () async {
      transport.inject('e1', {'k': 'join', 'id': 'p1', 'name': 'Pat'});

      expect(host.current!.players.map((p) => p.id), containsAll(['h', 'p1']));
      // Last broadcast carries the new roster.
      final last = BlitzSession.fromMap(
          Map<String, dynamic>.from(transport.broadcasts.last['session']));
      expect(last.players.any((p) => p.id == 'p1'), isTrue);
    });

    test('publishPop pays the popping player and re-broadcasts the ledger',
        () async {
      transport.inject('e1', {'k': 'join', 'id': 'p1', 'name': 'Pat'});
      await host.startRound();
      transport.broadcasts.clear();

      host.publishPop(objectId: 'r0', playerId: 'p1', value: 5, isBomb: false);

      expect(
        host.current!.players.firstWhere((p) => p.id == 'p1').liveScore,
        5,
      );
      // Session broadcast (new leaderboard) + the 'popped' removal message.
      expect(transport.broadcasts.any((m) => m['k'] == 'session'), isTrue);
      final popped =
          transport.broadcasts.lastWhere((m) => m['k'] == 'popped');
      expect(popped['id'], 'r0');
      expect(popped['by'], 'p1');
      expect(popped['v'], 5);
    });

    test('bomb pops subtract, clamped at zero', () async {
      transport.inject('e1', {'k': 'join', 'id': 'p1', 'name': 'Pat'});
      await host.startRound();

      host.publishPop(objectId: 'r0', playerId: 'p1', value: 2, isBomb: false);
      host.publishPop(objectId: 'r1', playerId: 'p1', value: 5, isBomb: true);

      expect(
        host.current!.players.firstWhere((p) => p.id == 'p1').liveScore,
        0,
        reason: '2 - 5 clamps to 0',
      );
    });

    test('the pop ledger ranks everyone (host pops score the same way)',
        () async {
      transport.inject('e1', {'k': 'join', 'id': 'p1', 'name': 'Pat'});
      await host.startRound();

      host.publishPop(objectId: 'r0', playerId: 'p1', value: 5, isBomb: false);
      host.publishPop(objectId: 'r1', playerId: 'h', value: 3, isBomb: false);

      final board = host.current!.leaderboard;
      expect(board.first.id, 'p1'); // 5 beats 3
      expect(board.first.liveScore, 5);
      expect(board.last.id, 'h');
    });

    test("a mirror's pop claim surfaces as a popClaim race event", () async {
      transport.inject('e1', {'k': 'join', 'id': 'p1', 'name': 'Pat'});
      await host.startRound();

      final events = <ArRaceEvent>[];
      final sub = host.events.listen(events.add);
      addTearDown(sub.cancel);

      transport.inject('e1', {'k': 'pop', 'id': 'r7', 'by': 'p1'});
      await Future<void>.delayed(Duration.zero);

      final claim =
          events.singleWhere((e) => e.type == ArRaceEventType.popClaim);
      expect(claim.objectId, 'r7');
      expect(claim.playerId, 'p1');
    });

    test('announceGo broadcasts AND echoes to the local controller', () async {
      final events = <ArRaceEvent>[];
      final sub = host.events.listen(events.add);
      addTearDown(sub.cancel);

      host.announceGo();
      await Future<void>.delayed(Duration.zero);

      expect(transport.broadcasts.any((m) => m['k'] == 'go'), isTrue);
      expect(events.any((e) => e.type == ArRaceEventType.go), isTrue);
    });

    test('on a peer connecting, the host pushes the current session to it',
        () async {
      transport.simulateConnect('e1');
      expect(transport.sent, isNotEmpty);
      expect(transport.sent.last.msg['k'], 'session');
    });

    test('a dropped peer stays in the roster (no mid-game removal)', () async {
      transport.inject('e1', {'k': 'join', 'id': 'p1', 'name': 'Pat'});
      expect(host.current!.players.any((p) => p.id == 'p1'), isTrue);

      transport.simulateDisconnect('e1');
      expect(host.current!.players.any((p) => p.id == 'p1'), isTrue);
    });
  });

  group('Round lifecycle (host-authoritative)', () {
    test('startRound enters playing, resets scores and stamps start time',
        () async {
      final transport = FakeBlitzTransport();
      final host = BalloonBlitzRepository.host(
        transport: transport,
        session: BlitzSession.createHost(hostId: 'h', hostName: 'Host'),
        now: () => 4242,
      );
      addTearDown(host.dispose);

      transport.inject('e1', {'k': 'join', 'id': 'p1', 'name': 'Pat'});
      host.publishPop(objectId: 'r0', playerId: 'p1', value: 9, isBomb: false);
      await host.startRound();

      expect(host.current!.phase, BlitzPhase.playing);
      expect(host.current!.startAtEpochMs, 4242);
      expect(host.current!.players.every((p) => p.liveScore == 0), isTrue);
    });

    test('endRound freezes to results; playAgain returns to a clean lobby',
        () async {
      final transport = FakeBlitzTransport();
      final host = BalloonBlitzRepository.host(
        transport: transport,
        session: BlitzSession.createHost(hostId: 'h', hostName: 'Host'),
        now: () => 1,
      );
      addTearDown(host.dispose);

      await host.startRound();
      host.publishPop(objectId: 'r0', playerId: 'h', value: 6, isBomb: false);
      host.endRound();
      expect(host.current!.phase, BlitzPhase.results);

      await host.playAgain();
      expect(host.current!.phase, BlitzPhase.lobby);
      expect(host.current!.startAtEpochMs, isNull);
      expect(host.current!.players.every((p) => p.liveScore == 0), isTrue);
    });

    test('the authoritative timer auto-ends the round at time-up', () async {
      final transport = FakeBlitzTransport();
      final host = BalloonBlitzRepository.host(
        transport: transport,
        // Zero-second round so the time-up Timer fires on the next event loop.
        session: const BlitzSession(
          hostId: 'h',
          durationSeconds: 0,
          players: [BlitzPlayer(id: 'h', name: 'Host', isHost: true)],
        ),
        now: () => 1,
      );
      addTearDown(host.dispose);

      await host.startRound();
      expect(host.current!.phase, BlitzPhase.playing);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(host.current!.phase, BlitzPhase.results);
    });
  });

  group('Peer behaviour', () {
    test('a pop claim goes to the remembered host endpoint', () async {
      final transport = FakeBlitzTransport();
      final peer = BalloonBlitzRepository.peer(
        transport: transport,
        selfId: 'p1',
        selfName: 'Pat',
      );
      addTearDown(peer.dispose);

      await peer.connect('host'); // announces 'join' to the host
      expect(transport.sent.first.msg['k'], 'join');

      peer.claimPop('r3');
      await Future<void>.delayed(Duration.zero);
      final claim = transport.sent.lastWhere((s) => s.msg['k'] == 'pop');
      expect(claim.endpointId, 'host');
      expect(claim.msg['id'], 'r3');
      expect(claim.msg['by'], 'p1');
      // A peer never broadcasts and never mutates the session locally.
      expect(transport.broadcasts, isEmpty);
      expect(peer.current, isNull);
    });

    test('host race messages surface as typed ArRaceEvents', () async {
      final transport = FakeBlitzTransport();
      final peer = BalloonBlitzRepository.peer(
        transport: transport,
        selfId: 'p1',
        selfName: 'Pat',
      );
      addTearDown(peer.dispose);

      final events = <ArRaceEvent>[];
      final sub = peer.events.listen(events.add);
      addTearDown(sub.cancel);

      transport.inject('host', {'k': 'go'});
      transport.inject('host', {
        'k': 'spawn',
        'o': const ArRaceObject(
          id: 'r0',
          position: ArVector3(1, 0, -2),
          modelRef: 'assets/ar/balloon_red.glb',
          value: 3,
          isBomb: false,
          phase: 0.5,
        ).toMap(),
      });
      transport.inject(
          'host', {'k': 'popped', 'id': 'r0', 'by': 'h', 'v': 3, 'b': false});
      transport.inject('host', {'k': 'escaped', 'id': 'r1'});
      transport.inject('host', {
        'k': 'objects',
        'list': [
          const ArRaceObject(
            id: 'r2',
            position: ArVector3(0, 0, -2),
            modelRef: 'assets/ar/balloon_blue.glb',
            value: 2,
            isBomb: false,
            phase: 1.0,
            age: 2.5,
          ).toMap(),
        ],
      });
      await Future<void>.delayed(Duration.zero);

      expect(events.map((e) => e.type), [
        ArRaceEventType.go,
        ArRaceEventType.spawn,
        ArRaceEventType.pop,
        ArRaceEventType.escape,
        ArRaceEventType.snapshot,
      ]);
      expect(events[1].object!.id, 'r0');
      expect(events[1].object!.position.z, -2);
      expect(events[2].playerId, 'h');
      expect(events[2].value, 3);
      expect(events[4].objects.single.age, 2.5);
    });

    test('a peer adopts the host authoritative session from a broadcast',
        () async {
      final transport = FakeBlitzTransport();
      final peer = BalloonBlitzRepository.peer(
        transport: transport,
        selfId: 'p1',
        selfName: 'Pat',
      );
      addTearDown(peer.dispose);

      const hostSession = BlitzSession(
        hostId: 'h',
        phase: BlitzPhase.playing,
        players: [
          BlitzPlayer(id: 'h', name: 'Host', liveScore: 2, isHost: true),
          BlitzPlayer(id: 'p1', name: 'Pat', liveScore: 4),
        ],
      );

      transport.inject('host', {'k': 'session', 'session': hostSession.toMap()});

      expect(peer.current, equals(hostSession));
      expect(peer.current!.leaderboard.first.id, 'p1');
    });
  });
}
