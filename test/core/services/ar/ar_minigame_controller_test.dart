import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/services/ar/ar_engine.dart';
import 'package:taskcaster_app/core/services/ar/ar_games.dart';
import 'package:taskcaster_app/core/services/ar/ar_minigame_controller.dart';

/// A plugin-free fake [ArEngine] that records spawns/moves/removes and lets a
/// test drive taps. Spawns complete on a microtask so [FakeAsync.flushMicrotasks]
/// drives the controller's sequential spawn loop.
class FakeArEngine implements ArEngine {
  final _planes = StreamController<ArPlane>.broadcast();
  final _taps = StreamController<ArTap>.broadcast();
  int _counter = 0;

  final List<String> spawnedModels = [];
  final List<String> liveIds = [];
  final List<String> removedIds = [];
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
    removedIds.add(node.id);
  }

  @override
  Future<void> dispose() async {}

  void emitTap(String id) => _taps.add(ArTap(id));
}

ArGameConfig _cfg({
  int count = 3,
  int durationS = 45,
  bool respawn = true,
  bool distance = true,
  int lifespanS = 60,
  double bombChance = 0,
  int pointsPerHit = 1,
  bool speedBonus = false,
}) {
  return ArGameConfig(
    id: 't',
    title: 't',
    modelRef: 'balloon.glb',
    objectCount: count,
    duration: Duration(seconds: durationS),
    respawnOnHit: respawn,
    pointsPerHit: pointsPerHit,
    speedBonus: speedBonus,
    objectLifespan: Duration(seconds: lifespanS),
    scoreByDistance: distance,
    bombChance: bombChance,
    bombPenalty: 3,
    bombModelRef: 'bomb.glb',
  );
}

void main() {
  ArMinigameController boot(FakeAsync async, FakeArEngine eng, ArGameConfig c) {
    final ctrl = ArMinigameController(engine: eng, config: c);
    ctrl.start();
    async.flushMicrotasks(); // initSession
    async.elapse(const Duration(seconds: 2)); // fallback → spawn
    async.flushMicrotasks(); // sequential spawn loop
    return ctrl;
  }

  test('spawns objectCount objects and starts the clock once one is live', () {
    fakeAsync((async) {
      final eng = FakeArEngine();
      final c = boot(async, eng, _cfg(count: 3, bombChance: 0));
      expect(eng.liveIds.length, 3);
      expect(c.objectsSpawned, isTrue);
      expect(c.hasLiveObjects, isTrue);
      c.dispose();
    });
  });

  test('tapping a target scores by distance (>=1) and respawns a replacement',
      () {
    fakeAsync((async) {
      final eng = FakeArEngine();
      final c = boot(async, eng, _cfg(count: 3, bombChance: 0));
      final id = eng.liveIds.first;
      eng.emitTap(id);
      async.flushMicrotasks();

      expect(c.hits, 1);
      expect(c.liveScore, greaterThanOrEqualTo(1));
      expect(eng.removedIds, contains(id));
      expect(eng.liveIds.length, 3, reason: 'popped balloon is replaced');
      c.dispose();
    });
  });

  test('tapping a bomb costs points (never below 0), flips bombFlash briefly',
      () {
    fakeAsync((async) {
      final eng = FakeArEngine();
      final c = boot(async, eng, _cfg(count: 2, bombChance: 1.0));
      expect(eng.spawnedModels.every((m) => m == 'bomb.glb'), isTrue);

      eng.emitTap(eng.liveIds.first);
      async.flushMicrotasks();

      expect(c.bombsHit, 1);
      expect(c.hits, 0);
      expect(c.liveScore, 0, reason: 'score clamped at 0');
      expect(c.bombFlash, isTrue);

      async.elapse(const Duration(milliseconds: 500));
      expect(c.bombFlash, isFalse, reason: 'flash auto-clears');
      c.dispose();
    });
  });

  test('an unpopped balloon rises, escapes after its lifespan, and is replaced',
      () {
    fakeAsync((async) {
      final eng = FakeArEngine();
      final c = boot(async, eng, _cfg(count: 2, bombChance: 0, lifespanS: 3));
      final originals = List<String>.of(eng.liveIds);

      async.elapse(const Duration(seconds: 4)); // beyond the 3s lifespan
      async.flushMicrotasks();

      for (final id in originals) {
        expect(eng.removedIds, contains(id), reason: 'original escaped');
      }
      expect(eng.liveIds.length, 2, reason: 'escaped balloons are replaced');
      c.dispose();
    });
  });

  test('non-distance game scores via pointsPerHit and ends when all are found',
      () {
    fakeAsync((async) {
      final eng = FakeArEngine();
      final c = boot(
        async,
        eng,
        _cfg(
          count: 2,
          respawn: false,
          distance: false,
          lifespanS: 0,
          pointsPerHit: 10,
        ),
      );
      final ids = List<String>.of(eng.liveIds);

      eng.emitTap(ids[0]);
      async.flushMicrotasks();
      expect(c.liveScore, 10);
      expect(c.finished, isFalse);

      eng.emitTap(ids[1]);
      async.flushMicrotasks();
      expect(c.hits, 2);
      expect(c.finished, isTrue, reason: 'all gems found');
      expect(c.finalScore, 20);
      c.dispose();
    });
  });

  test('the countdown ends the round and freezes the final score', () {
    fakeAsync((async) {
      final eng = FakeArEngine();
      final c = boot(async, eng, _cfg(count: 1, durationS: 5, bombChance: 0));
      eng.emitTap(eng.liveIds.first);
      async.flushMicrotasks();
      final scoreAtPop = c.liveScore;

      async.elapse(const Duration(seconds: 6)); // exceed the 5s round
      expect(c.finished, isTrue);
      expect(c.finalScore, scoreAtPop);
      c.dispose();
    });
  });
}
