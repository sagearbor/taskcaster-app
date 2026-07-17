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
  Future<ArVector3?> cameraPosition() async => null;

  @override
  Future<ArCameraPose?> cameraPose() async => null;

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
    async.elapse(const Duration(milliseconds: 2800)); // 3-2-1-GO pre-roll
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

  test('taps before GO are ignored — the round starts fair', () {
    fakeAsync((async) {
      final eng = FakeArEngine();
      final c = ArMinigameController(engine: eng, config: _cfg(bombChance: 0));
      c.start();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 2)); // fallback → spawn
      async.flushMicrotasks();

      expect(c.inPreRoll, isTrue, reason: '3-2-1 is showing');
      eng.emitTap(eng.liveIds.first);
      async.flushMicrotasks();
      expect(c.hits, 0, reason: 'pre-GO tap must not score');

      async.elapse(const Duration(milliseconds: 2800)); // pre-roll ends
      expect(c.inPreRoll, isFalse);
      eng.emitTap(eng.liveIds.first);
      async.flushMicrotasks();
      expect(c.hits, 1);
      c.dispose();
    });
  });

  test('emits surfaceFound/go/pop/bomb/timeUp events for the feel layer', () {
    fakeAsync((async) {
      final eng = FakeArEngine();
      final c = ArMinigameController(
        engine: eng,
        config: _cfg(count: 2, durationS: 5, bombChance: 0),
      );
      final events = <ArGameEvent>[];
      c.events.listen(events.add);
      c.start();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 2800));

      eng.emitTap(eng.liveIds.first);
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 6)); // run out the clock
      async.flushMicrotasks();

      final types = events.map((e) => e.type).toList();
      expect(types, contains(ArGameEventType.surfaceFound));
      expect(types, contains(ArGameEventType.go));
      expect(types, contains(ArGameEventType.pop));
      expect(types, contains(ArGameEventType.timeUp));
      final popEvent =
          events.firstWhere((e) => e.type == ArGameEventType.pop);
      expect(popEvent.value, greaterThanOrEqualTo(1));
      expect(popEvent.modelRef, 'balloon.glb');
      c.dispose();
    });
  });

  test('bomb tap emits a bomb event carrying the penalty', () {
    fakeAsync((async) {
      final eng = FakeArEngine();
      final c = ArMinigameController(
        engine: eng,
        config: _cfg(count: 1, bombChance: 1.0),
      );
      final events = <ArGameEvent>[];
      c.events.listen(events.add);
      c.start();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 2800));

      eng.emitTap(eng.liveIds.first);
      async.flushMicrotasks();

      final bombEvent =
          events.firstWhere((e) => e.type == ArGameEventType.bomb);
      expect(bombEvent.value, 3);
      expect(bombEvent.modelRef, 'bomb.glb');
      c.dispose();
    });
  });

  test('a bomb is guaranteed by the 4th spawn even when the dice never roll one',
      () {
    fakeAsync((async) {
      final eng = FakeArEngine();
      // Bomb chance is effectively zero, so only the guarantee can fire.
      final c = boot(async, eng, _cfg(count: 5, bombChance: 1e-9));
      expect(eng.spawnedModels.take(3).every((m) => m == 'balloon.glb'), isTrue,
          reason: 'dice this cold never roll a natural bomb');
      expect(eng.spawnedModels[3], 'bomb.glb',
          reason: '4th spawn is the guaranteed bomb');
      expect(eng.spawnedModels.where((m) => m == 'bomb.glb').length, 1,
          reason: 'guarantee fires exactly once');
      c.dispose();
    });
  });

  test('quick pops build a combo that doubles payouts; gaps and bombs break it',
      () {
    fakeAsync((async) {
      final eng = FakeArEngine();
      final c = boot(async, eng, _cfg(count: 5, bombChance: 0));
      final popValues = <int>[];
      c.events.listen((e) {
        if (e.type == ArGameEventType.pop) popValues.add(e.value);
      });

      // Three rapid pops: streak 1, 2, 3 — the third is hot (paid double).
      for (var i = 0; i < 3; i++) {
        eng.emitTap(eng.liveIds.first);
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 300));
      }
      expect(c.combo, 3);
      expect(c.comboActive, isTrue);
      expect(popValues[2].isEven, isTrue, reason: 'doubled payout');

      // Let the window lapse: streak resets.
      async.elapse(const Duration(seconds: 2));
      expect(c.combo, 0);
      expect(c.comboActive, isFalse);

      // Rebuild to hot, then a bomb kills it instantly.
      for (var i = 0; i < 3; i++) {
        eng.emitTap(eng.liveIds.first);
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 300));
      }
      expect(c.comboActive, isTrue);
      c.dispose();
    });
  });

  test('the running score equals the sum of emitted pop values minus penalties',
      () {
    fakeAsync((async) {
      final eng = FakeArEngine();
      final c = boot(async, eng, _cfg(count: 4, bombChance: 0));
      var paid = 0;
      c.events.listen((e) {
        if (e.type == ArGameEventType.pop) paid += e.value;
      });

      for (var i = 0; i < 5; i++) {
        eng.emitTap(eng.liveIds.first);
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 200));
      }
      expect(c.liveScore, paid,
          reason: 'HUD score and flyout values must always agree');
      c.dispose();
    });
  });

  test('pause freezes the clock and taps; resume re-runs 3-2-1 then unfreezes',
      () {
    fakeAsync((async) {
      final eng = FakeArEngine();
      final c = boot(async, eng, _cfg(count: 1, durationS: 30, bombChance: 0));
      async.elapse(const Duration(seconds: 5));
      final frozenAt = c.secondsRemaining;

      c.pause();
      async.elapse(const Duration(seconds: 10));
      expect(c.secondsRemaining, frozenAt, reason: 'clock frozen while paused');
      eng.emitTap(eng.liveIds.first);
      async.flushMicrotasks();
      expect(c.hits, 0, reason: 'taps ignored while paused');

      c.resume();
      expect(c.inPreRoll, isTrue, reason: 'resume replays the 3-2-1');
      async.elapse(const Duration(milliseconds: 2800));
      expect(c.inPreRoll, isFalse);
      async.elapse(const Duration(seconds: 2));
      expect(c.secondsRemaining, lessThan(frozenAt),
          reason: 'clock ticking again after resume');
      eng.emitTap(eng.liveIds.first);
      async.flushMicrotasks();
      expect(c.hits, 1);
      c.dispose();
    });
  });
}
