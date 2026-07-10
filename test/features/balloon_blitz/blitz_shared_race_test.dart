import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/services/ar/ar_engine.dart';
import 'package:taskcaster_app/core/services/ar/ar_games.dart';
import 'package:taskcaster_app/core/services/ar/ar_minigame_controller.dart';
import 'package:taskcaster_app/features/balloon_blitz/data/datasources/blitz_transport.dart';
import 'package:taskcaster_app/features/balloon_blitz/data/repositories/balloon_blitz_repository.dart';
import 'package:taskcaster_app/features/balloon_blitz/domain/entities/blitz_session.dart';

/// End-to-end proof of the SHARED balloon race: a host controller and a peer
/// controller, each with its own fake AR engine, joined by a pair of linked
/// in-memory transports — exactly the two-phone setup that failed in the field
/// ("the other phone popped a lot but got zero points on my phone").

class FakeArEngine implements ArEngine {
  final _planes = StreamController<ArPlane>.broadcast();
  final _taps = StreamController<ArTap>.broadcast();
  int _counter = 0;

  final List<String> spawnedModels = [];
  final List<String> liveIds = [];
  final Map<String, ArVector3> positions = {};

  @override
  Widget buildView() => const SizedBox.shrink();

  @override
  Future<void> initSession() async {}

  @override
  Stream<ArPlane> get planes => _planes.stream;

  @override
  Stream<ArTap> get taps => _taps.stream;

  @override
  Future<ArNode> spawn({
    required String modelRef,
    required ArVector3 position,
    ArPlane? onPlane,
  }) async {
    final id = 'n${_counter++}';
    spawnedModels.add(modelRef);
    liveIds.add(id);
    positions[id] = position;
    return ArNode(id);
  }

  @override
  Future<void> move(ArNode node, ArVector3 position) async {
    positions[node.id] = position;
  }

  @override
  Future<void> remove(ArNode node) async {
    liveIds.remove(node.id);
  }

  @override
  Future<ArVector3?> cameraPosition() async => null;

  @override
  Future<ArNode?> spawnInFrontOfCamera({
    required String modelRef,
    double distance = 1.0,
    double drop = 0.0,
  }) async =>
      null;

  @override
  Future<void> dispose() async {}

  void emitTap(String id) => _taps.add(ArTap(id));
}

/// Two transports whose sends deliver straight into each other's callbacks.
class LinkedTransport implements BlitzTransport {
  LinkedTransport? other;
  final String selfEndpointId;

  void Function(String endpointId, Map<String, dynamic> message)? _onMessage;
  void Function(String endpointId)? _onConnected;
  final Set<String> _connected = {};
  final _devices = StreamController<List<NearbyDevice>>.broadcast();

  LinkedTransport(this.selfEndpointId);

  static (LinkedTransport, LinkedTransport) pair() {
    final a = LinkedTransport('host-endpoint');
    final b = LinkedTransport('peer-endpoint');
    a.other = b;
    b.other = a;
    return (a, b);
  }

  @override
  set onMessage(
          void Function(String endpointId, Map<String, dynamic> message)? cb) =>
      _onMessage = cb;

  @override
  set onEndpointConnected(void Function(String endpointId)? cb) =>
      _onConnected = cb;

  @override
  set onEndpointDisconnected(void Function(String endpointId)? cb) {}

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
    linkUp();
    other!.linkUp();
    return true;
  }

  void linkUp() {
    _connected.add(other!.selfEndpointId);
    _onConnected?.call(other!.selfEndpointId);
  }

  @override
  Future<void> sendToEndpoint(
      String endpointId, Map<String, dynamic> message) async {
    // Deliver as a decoded copy, like real JSON round-tripping.
    other!._onMessage?.call(selfEndpointId, Map<String, dynamic>.from(message));
  }

  @override
  Future<void> broadcast(Map<String, dynamic> message) async {
    for (final id in _connected.toList()) {
      await sendToEndpoint(id, message);
    }
  }

  @override
  Future<void> dispose() async {
    if (!_devices.isClosed) await _devices.close();
  }
}

const _config = ArGameConfig(
  id: 'race',
  title: 'race',
  modelRef: 'balloon.glb',
  objectCount: 3,
  duration: Duration(seconds: 45),
  respawnOnHit: true,
  pointsPerHit: 1,
  speedBonus: false,
  objectLifespan: Duration(seconds: 60),
  scoreByDistance: true,
  bombChance: 0,
  bombPenalty: 3,
  bombModelRef: 'bomb.glb',
);

void main() {
  ({
    BalloonBlitzRepository hostRepo,
    BalloonBlitzRepository peerRepo,
    FakeArEngine hostEngine,
    FakeArEngine peerEngine,
    ArMinigameController hostCtrl,
    ArMinigameController peerCtrl,
  }) bootRace(FakeAsync async) {
    final (hostT, peerT) = LinkedTransport.pair();
    final hostRepo = BalloonBlitzRepository.host(
      transport: hostT,
      session: BlitzSession.createHost(hostId: 'h', hostName: 'Mom'),
      now: () => 1000,
    );
    final peerRepo = BalloonBlitzRepository.peer(
      transport: peerT,
      selfId: 'p1',
      selfName: 'Kid',
    );
    peerT.connect('host-endpoint'); // join handshake both ways
    async.flushMicrotasks();

    final hostEngine = FakeArEngine();
    final peerEngine = FakeArEngine();
    final hostCtrl = ArMinigameController(
      engine: hostEngine,
      config: _config,
      race: hostRepo,
    );
    final peerCtrl = ArMinigameController(
      engine: peerEngine,
      config: _config,
      race: peerRepo,
    );
    hostCtrl.start();
    peerCtrl.start();
    async.flushMicrotasks();

    // Host: no plane in the fake → 2s fallback → announceGo (shared preroll
    // on both phones), then 3-2-1 (2.7s) → GO → host spawns + broadcasts.
    async.elapse(const Duration(seconds: 2));
    async.flushMicrotasks();
    async.elapse(const Duration(milliseconds: 2800));
    async.flushMicrotasks();

    return (
      hostRepo: hostRepo,
      peerRepo: peerRepo,
      hostEngine: hostEngine,
      peerEngine: peerEngine,
      hostCtrl: hostCtrl,
      peerCtrl: peerCtrl,
    );
  }

  test('both phones render the SAME shared balloon set after GO', () {
    fakeAsync((async) {
      final r = bootRace(async);

      expect(r.hostEngine.liveIds.length, 3);
      expect(r.peerEngine.liveIds.length, 3,
          reason: 'mirror spawned every broadcast object');
      // Same models, same base positions (each in its own frame).
      expect(r.peerEngine.spawnedModels, r.hostEngine.spawnedModels);
      expect(
        r.peerEngine.positions.values.map((v) => (v.x, v.y, v.z)).toSet(),
        r.hostEngine.positions.values.map((v) => (v.x, v.y, v.z)).toSet(),
      );

      r.hostCtrl.dispose();
      r.peerCtrl.dispose();
    });
  });

  test("REGRESSION: the peer's pops actually score on the host's leaderboard",
      () {
    fakeAsync((async) {
      final r = bootRace(async);

      // The kid pops two balloons on their phone.
      r.peerEngine.emitTap(r.peerEngine.liveIds.first);
      async.flushMicrotasks();
      r.peerEngine.emitTap(r.peerEngine.liveIds.first);
      async.flushMicrotasks();

      final kidOnHost =
          r.hostRepo.current!.players.firstWhere((p) => p.id == 'p1');
      expect(kidOnHost.liveScore, greaterThan(0),
          reason: "the field bug: peer pops must reach the host's ledger");
      expect(r.hostRepo.current!.leaderboard.first.id, 'p1');

      r.hostCtrl.dispose();
      r.peerCtrl.dispose();
    });
  });

  test('a popped balloon disappears from BOTH phones and respawns everywhere',
      () {
    fakeAsync((async) {
      final r = bootRace(async);
      final hostSpawnsBefore = r.hostEngine.spawnedModels.length;

      r.peerEngine.emitTap(r.peerEngine.liveIds.first);
      async.flushMicrotasks();

      // Host adjudicated: its copy removed + a replacement spawned + mirrored.
      expect(r.hostEngine.liveIds.length, 3);
      expect(r.hostEngine.spawnedModels.length, hostSpawnsBefore + 1);
      expect(r.peerEngine.liveIds.length, 3,
          reason: 'optimistic removal + mirrored replacement');

      r.hostCtrl.dispose();
      r.peerCtrl.dispose();
    });
  });

  test("host pops emit rivalPop on the peer (with the host's name)", () {
    fakeAsync((async) {
      final r = bootRace(async);
      final peerEvents = <ArGameEvent>[];
      r.peerCtrl.events.listen(peerEvents.add);

      r.hostEngine.emitTap(r.hostEngine.liveIds.first);
      async.flushMicrotasks();

      final rival = peerEvents
          .singleWhere((e) => e.type == ArGameEventType.rivalPop);
      expect(rival.playerName, 'Mom');
      expect(rival.value, greaterThan(0));

      r.hostCtrl.dispose();
      r.peerCtrl.dispose();
    });
  });

  test("peer claims emit rivalPop on the host (with the peer's name)", () {
    fakeAsync((async) {
      final r = bootRace(async);
      final hostEvents = <ArGameEvent>[];
      r.hostCtrl.events.listen(hostEvents.add);

      r.peerEngine.emitTap(r.peerEngine.liveIds.first);
      async.flushMicrotasks();

      final rival =
          hostEvents.singleWhere((e) => e.type == ArGameEventType.rivalPop);
      expect(rival.playerName, 'Kid');

      r.hostCtrl.dispose();
      r.peerCtrl.dispose();
    });
  });

  test('double-claim on the same balloon pays only the first claimant', () {
    fakeAsync((async) {
      final r = bootRace(async);

      // Both phones tap the SAME logical balloon at once. The host processes
      // its own tap first, then the peer's late claim must be ignored.
      final hostNode = r.hostEngine.liveIds.first;
      final peerNode = r.peerEngine.liveIds.first; // same race object (n0)
      r.hostEngine.emitTap(hostNode);
      r.peerEngine.emitTap(peerNode);
      async.flushMicrotasks();

      final host = r.hostRepo.current!.players.firstWhere((p) => p.id == 'h');
      final kid = r.hostRepo.current!.players.firstWhere((p) => p.id == 'p1');
      expect(host.liveScore, greaterThan(0));
      expect(kid.liveScore, 0, reason: 'late claim on a dead balloon = no pay');

      r.hostCtrl.dispose();
      r.peerCtrl.dispose();
    });
  });

  test('escapes propagate: the balloon leaves both phones', () {
    fakeAsync((async) {
      final (hostT, peerT) = LinkedTransport.pair();
      final hostRepo = BalloonBlitzRepository.host(
        transport: hostT,
        session: BlitzSession.createHost(hostId: 'h', hostName: 'Mom'),
        now: () => 1000,
      );
      final peerRepo = BalloonBlitzRepository.peer(
        transport: peerT,
        selfId: 'p1',
        selfName: 'Kid',
      );
      peerT.connect('host-endpoint');
      async.flushMicrotasks();

      const shortLife = ArGameConfig(
        id: 'race',
        title: 'race',
        modelRef: 'balloon.glb',
        objectCount: 2,
        duration: Duration(seconds: 45),
        respawnOnHit: true,
        pointsPerHit: 1,
        speedBonus: false,
        objectLifespan: Duration(seconds: 3),
        scoreByDistance: true,
        bombChance: 0,
        bombPenalty: 3,
        bombModelRef: 'bomb.glb',
      );
      final hostEngine = FakeArEngine();
      final peerEngine = FakeArEngine();
      final hostCtrl = ArMinigameController(
          engine: hostEngine, config: shortLife, race: hostRepo);
      final peerCtrl = ArMinigameController(
          engine: peerEngine, config: shortLife, race: peerRepo);
      hostCtrl.start();
      peerCtrl.start();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 2800));
      async.flushMicrotasks();

      final originalPeerNodes = List<String>.of(peerEngine.liveIds);
      // Age past the 3s lifespan: the host escapes + respawns, mirrors follow.
      async.elapse(const Duration(seconds: 4));
      async.flushMicrotasks();

      for (final id in originalPeerNodes) {
        expect(peerEngine.liveIds, isNot(contains(id)),
            reason: 'escaped balloons leave the mirror too');
      }
      expect(peerEngine.liveIds.length, 2, reason: 'replacements mirrored');

      hostCtrl.dispose();
      peerCtrl.dispose();
    });
  });
}
