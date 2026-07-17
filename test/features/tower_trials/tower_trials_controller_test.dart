import 'dart:async';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/services/ar/ar_engine.dart';
import 'package:taskcaster_app/features/tower_trials/tower_trials_controller.dart';

/// Plugin-free fake engine: records spawns/moves/removes with model refs so
/// tests can assert base/ghost/player-block choreography.
class FakeArEngine implements ArEngine {
  final _planes = StreamController<ArPlane>.broadcast();
  final _taps = StreamController<ArTap>.broadcast();
  int _counter = 0;

  ArVector3? pose = const ArVector3(0, 0, 0);
  ArCameraPose? cameraPoseValue;

  final List<String> spawnedModels = [];
  final Map<String, String> modelById = {};
  final Map<String, ArVector3> positions = {};
  final List<String> removedIds = [];

  @override
  Widget buildView() => const SizedBox.shrink();

  @override
  Future<void> initSession() async {}

  @override
  Stream<ArPlane> get planes => _planes.stream;

  @override
  Stream<ArTap> get taps => _taps.stream;

  @override
  Future<ArVector3?> cameraPosition() async => pose;

  @override
  Future<ArCameraPose?> cameraPose() async => cameraPoseValue;

  @override
  Future<ArNode> spawn({
    required String modelRef,
    required ArVector3 position,
    ArPlane? onPlane,
  }) async {
    final id = 'n${_counter++}';
    spawnedModels.add(modelRef);
    modelById[id] = modelRef;
    positions[id] = position;
    return ArNode(id);
  }

  @override
  Future<ArNode?> spawnInFrontOfCamera({
    required String modelRef,
    double distance = 1.0,
    double drop = 0.0,
  }) async =>
      null;

  @override
  Future<void> move(ArNode node, ArVector3 position) async {
    positions[node.id] = position;
  }

  @override
  Future<void> remove(ArNode node) async => removedIds.add(node.id);

  @override
  Future<void> dispose() async {}
}

void main() {
  /// Build a controller mid-game: started, roster locked, base spawned, and
  /// (by default) the first turn live.
  TowerTrialsController live(
    FakeAsync async,
    FakeArEngine eng, {
    List<String> names = const ['Ann', 'Bob'],
    bool beginFirstTurn = true,
  }) {
    final c = TowerTrialsController(engine: eng);
    c.start();
    async.flushMicrotasks();
    c.startGame(names);
    async.flushMicrotasks(); // base + ghost spawn
    expect(c.baseReady, isTrue);
    if (beginFirstTurn) {
      c.beginTurn();
    }
    return c;
  }

  /// Aim + drop with the given offset for whoever's turn it is.
  void drop(FakeAsync async, TowerTrialsController c, double dx, double dz) {
    expect(c.phase, TowerTrialsPhase.aiming);
    c.updateAim(dx, dz);
    c.dropBlock();
    async.flushMicrotasks();
  }

  /// From handoff, start the next player's turn.
  void nextTurn(TowerTrialsController c) {
    expect(c.phase, TowerTrialsPhase.handoff);
    c.beginTurn();
  }

  // ---- Pure mappings --------------------------------------------------------

  group('aimFromPose (camera ray → landing-plane offset)', () {
    test('dead-centre aim yields ~zero offset', () {
      // Camera at origin, tower-top landing centre at (0, -0.3, -1.1).
      final len = sqrt(0.3 * 0.3 + 1.1 * 1.1);
      final aim = TowerTrialsController.aimFromPose(
        pose: ArCameraPose(
          position: const ArVector3(0, 0, 0),
          forward: ArVector3(0, -0.3 / len, -1.1 / len),
        ),
        targetX: 0,
        targetY: -0.3,
        targetZ: -1.1,
      );
      expect(aim, isNotNull);
      expect(aim!.dx.abs(), lessThan(1e-9));
      expect(aim.dz.abs(), lessThan(1e-9));
    });

    test('aiming to the side reports the sideways miss', () {
      // 45° down-forward ray from 0.3 m above the plane, panned 0.2 m right of
      // the target: hits the plane 0.3 m forward, dx = 0.2.
      final aim = TowerTrialsController.aimFromPose(
        pose: ArCameraPose(
          position: const ArVector3(0.2, 0, 0),
          forward: ArVector3(0, -sqrt(0.5), -sqrt(0.5)),
        ),
        targetX: 0,
        targetY: -0.3,
        targetZ: -0.3,
      );
      expect(aim, isNotNull);
      expect(aim!.dx, closeTo(0.2, 1e-9));
      expect(aim.dz, closeTo(0, 1e-9));
    });

    test('looking level or away from the plane has no aim', () {
      // Dead level: never meets the horizontal plane.
      expect(
        TowerTrialsController.aimFromPose(
          pose: const ArCameraPose(
            position: ArVector3(0, 0, 0),
            forward: ArVector3(0, 0, -1),
          ),
          targetX: 0,
          targetY: -0.3,
          targetZ: -1.1,
        ),
        isNull,
      );
      // Looking UP while the plane is below: intersection is behind you.
      expect(
        TowerTrialsController.aimFromPose(
          pose: const ArCameraPose(
            position: ArVector3(0, 0, 0),
            forward: ArVector3(0, 0.7, -0.7),
          ),
          targetX: 0,
          targetY: -0.3,
          targetZ: -1.1,
        ),
        isNull,
      );
    });
  });

  group('clampAim / instabilityDelta (pure placement math)', () {
    test('clampAim preserves direction, caps magnitude', () {
      final a = TowerTrialsController.clampAim(3.0, 4.0); // len 5 → maxAim
      expect(a.length, closeTo(TowerTrialsController.maxAim, 1e-9));
      expect(a.dx / a.dz, closeTo(3 / 4, 1e-9));
      final b = TowerTrialsController.clampAim(0.01, -0.02);
      expect(b.dx, 0.01);
      expect(b.dz, -0.02);
    });

    test('perfect at/under the threshold, rebate is negative', () {
      expect(TowerTrialsController.isPerfect(0.0), isTrue);
      expect(
        TowerTrialsController.isPerfect(TowerTrialsController.perfectThreshold),
        isTrue,
      );
      expect(TowerTrialsController.isPerfect(0.031), isFalse);
      expect(TowerTrialsController.instabilityDelta(0.01),
          -TowerTrialsController.perfectRebate);
    });

    test('instability grows monotonically with offset', () {
      final small = TowerTrialsController.instabilityDelta(0.05);
      final medium = TowerTrialsController.instabilityDelta(0.12);
      final large = TowerTrialsController.instabilityDelta(0.25);
      expect(small, greaterThan(0));
      expect(medium, greaterThan(small));
      expect(large, greaterThan(medium));
      // A full-block-width miss adds the documented amount.
      expect(large,
          closeTo(TowerTrialsController.instabilityPerBlockOffset, 1e-9));
    });
  });

  group('swayOffset / collapseOffset (deterministic, no physics)', () {
    test('no sway for the base or for a rock-solid tower', () {
      const zero = ArVector3(0, 0, 0);
      final base = TowerTrialsController.swayOffset(
          level: 0, instability: 0.9, driftX: 1, driftZ: 0, time: 3);
      final solid = TowerTrialsController.swayOffset(
          level: 4, instability: 0, driftX: 1, driftZ: 0, time: 3);
      expect(base.x, zero.x);
      expect(base.z, zero.z);
      expect(solid.x, zero.x);
      expect(solid.z, zero.z);
    });

    test('sway is deterministic and grows with height', () {
      final a = TowerTrialsController.swayOffset(
          level: 2, instability: 0.5, driftX: 0.1, driftZ: 0, time: 1.2);
      final b = TowerTrialsController.swayOffset(
          level: 2, instability: 0.5, driftX: 0.1, driftZ: 0, time: 1.2);
      expect(a.x, b.x);
      expect(a.z, b.z);
      // The lean component points along +x drift and grows with level.
      final low = TowerTrialsController.swayOffset(
          level: 1, instability: 1, driftX: 1, driftZ: 0, time: 0);
      final high = TowerTrialsController.swayOffset(
          level: 5, instability: 1, driftX: 1, driftZ: 0, time: 0);
      expect(high.x.abs(), greaterThan(low.x.abs()));
    });

    test('collapse tumble moves blocks outward and down over time', () {
      final early =
          TowerTrialsController.collapseOffset(level: 3, t: 0.2);
      final late =
          TowerTrialsController.collapseOffset(level: 3, t: 1.0);
      final earlyOut = sqrt(early.x * early.x + early.z * early.z);
      final lateOut = sqrt(late.x * late.x + late.z * late.z);
      expect(lateOut, greaterThan(earlyOut));
      expect(late.y, lessThan(early.y));
      expect(late.y,
          closeTo(-3 * TowerTrialsController.blockSize, 1e-9));
      // Base never tumbles.
      final base = TowerTrialsController.collapseOffset(level: 0, t: 1.0);
      expect(base.x, 0);
      expect(base.y, 0);
    });
  });

  // ---- Setup / base ---------------------------------------------------------

  test('startGame needs 2+ players and spawns the base + ghost', () {
    fakeAsync((async) {
      final eng = FakeArEngine();
      final c = TowerTrialsController(engine: eng);
      c.start();
      async.flushMicrotasks();

      c.startGame(['OnlyOne']);
      expect(c.phase, TowerTrialsPhase.setup, reason: 'versus needs 2+');

      c.startGame(['Ann', 'Bob', 'Cass']);
      async.flushMicrotasks();
      expect(c.phase, TowerTrialsPhase.handoff);
      expect(c.currentPlayerName, 'Ann');
      expect(c.baseReady, isTrue);
      expect(eng.spawnedModels,
          ['assets/ar/block_base.glb', 'assets/ar/block_ghost.glb']);
      // Base sits baseDrop below and towerDistance in front of the camera.
      final basePos = eng.positions['n0']!;
      expect(basePos.y, closeTo(-TowerTrialsController.baseDrop, 1e-9));
      expect(basePos.z, closeTo(-TowerTrialsController.towerDistance, 1e-9));
      c.dispose();
    });
  });

  test('players get distinct block colors by seat order', () {
    fakeAsync((async) {
      final eng = FakeArEngine();
      final c = live(async, eng, names: ['A', 'B', 'C']);
      expect(c.players[0].blockModelRef, 'assets/ar/block_red.glb');
      expect(c.players[1].blockModelRef, 'assets/ar/block_blue.glb');
      expect(c.players[2].blockModelRef, 'assets/ar/block_green.glb');
      c.dispose();
    });
  });

  // ---- Aiming / dropping ----------------------------------------------------

  test('updateAim clamps and moves the ghost; clearAim disables the drop', () {
    fakeAsync((async) {
      final eng = FakeArEngine();
      final c = live(async, eng);

      expect(c.hasAim, isFalse);
      c.dropBlock();
      expect(c.blocksPlaced, 0, reason: 'no aim → no drop');

      c.updateAim(9.0, 0.0); // absurd — clamped to maxAim
      expect(c.hasAim, isTrue);
      expect(c.aim!.length, closeTo(TowerTrialsController.maxAim, 1e-9));
      // Ghost moved to the clamped preview spot (ghost node is n1).
      final ghostPos = eng.positions['n1']!;
      expect(ghostPos.x, closeTo(TowerTrialsController.maxAim, 1e-9));

      c.clearAim();
      expect(c.hasAim, isFalse);
      c.dropBlock();
      expect(c.blocksPlaced, 0);
      c.dispose();
    });
  });

  test('a drop spawns the player-colored block at top + offset and hands off',
      () {
    fakeAsync((async) {
      final eng = FakeArEngine();
      final events = <TowerTrialsEventType>[];
      final c = live(async, eng);
      c.events.listen((e) => events.add(e.type));

      drop(async, c, 0.10, 0.0);

      expect(c.blocksPlaced, 1);
      expect(c.tower.last.x, closeTo(0.10, 1e-9));
      expect(c.tower.last.level, 1);
      // Ann is red; the new block sits one blockSize above the base.
      expect(eng.spawnedModels.last, 'assets/ar/block_red.glb');
      final blockPos = eng.positions[eng.modelById.entries
          .lastWhere((e) => e.value == 'assets/ar/block_red.glb')
          .key]!;
      expect(
        blockPos.y,
        closeTo(-TowerTrialsController.baseDrop + TowerTrialsController.blockSize,
            1e-9),
      );
      expect(events, contains(TowerTrialsEventType.place));
      expect(c.phase, TowerTrialsPhase.handoff, reason: 'pass the phone');
      expect(c.currentPlayerName, 'Bob');
      c.dispose();
    });
  });

  test('turn order rotates through all players and wraps', () {
    fakeAsync((async) {
      final eng = FakeArEngine();
      final c = live(async, eng, names: ['A', 'B', 'C']);

      expect(c.currentPlayerName, 'A');
      drop(async, c, 0.05, 0);
      expect(c.currentPlayerName, 'B');
      nextTurn(c);
      drop(async, c, 0.05, 0);
      expect(c.currentPlayerName, 'C');
      nextTurn(c);
      drop(async, c, 0.05, 0);
      expect(c.currentPlayerName, 'A', reason: 'wraps around');
      c.dispose();
    });
  });

  test('offsets ACCUMULATE into instability across turns', () {
    fakeAsync((async) {
      final eng = FakeArEngine();
      final c = live(async, eng);

      drop(async, c, 0.10, 0.0);
      final afterOne = c.instability;
      expect(afterOne, closeTo(TowerTrialsController.instabilityDelta(0.10), 1e-9));

      nextTurn(c);
      drop(async, c, 0.0, 0.10);
      expect(c.instability, closeTo(afterOne * 2, 1e-9),
          reason: 'equal offsets add equal instability');
      // Drift tracks both axes.
      expect(c.driftX, closeTo(0.10, 1e-9));
      expect(c.driftZ, closeTo(0.10, 1e-9));
      c.dispose();
    });
  });

  test('PERFECT drop refunds instability (never below zero) and emits perfect',
      () {
    fakeAsync((async) {
      final eng = FakeArEngine();
      final events = <TowerTrialsEventType>[];
      final c = live(async, eng);
      c.events.listen((e) => events.add(e.type));

      // A perfect on a pristine tower can't go negative.
      drop(async, c, 0.0, 0.0);
      async.flushMicrotasks();
      expect(c.instability, 0);
      expect(c.lastWasPerfect, isTrue);
      expect(events, contains(TowerTrialsEventType.perfect));

      // Build up wobble, then a perfect claws some back.
      nextTurn(c);
      drop(async, c, 0.15, 0.0);
      final wobbly = c.instability;
      expect(wobbly, greaterThan(0));
      nextTurn(c);
      drop(async, c, 0.01, 0.0);
      expect(
        c.instability,
        closeTo(
          (wobbly - TowerTrialsController.perfectRebate).clamp(0.0, 99.0),
          1e-9,
        ),
      );
      c.dispose();
    });
  });

  test('crossing the warn threshold emits warning exactly once per climb', () {
    fakeAsync((async) {
      final eng = FakeArEngine();
      final events = <TowerTrialsEventType>[];
      final c = live(async, eng);
      c.events.listen((e) => events.add(e.type));

      // 0.16 offset → +0.352 instability per drop: 0.352 → 0.704 (warn).
      drop(async, c, 0.16, 0);
      async.flushMicrotasks();
      expect(events, isNot(contains(TowerTrialsEventType.warning)));
      nextTurn(c);
      drop(async, c, 0.16, 0);
      async.flushMicrotasks();
      expect(
          events.where((e) => e == TowerTrialsEventType.warning).length, 1);
      expect(c.instability, greaterThan(TowerTrialsController.warnThreshold));
      expect(c.phase, TowerTrialsPhase.handoff, reason: 'not collapsed yet');
      c.dispose();
    });
  });

  // ---- Collapse / elimination / winner --------------------------------------

  test('crossing the collapse threshold eliminates the dropper; the other '
      'player wins (2-player game)', () {
    fakeAsync((async) {
      final eng = FakeArEngine();
      final events = <TowerTrialsEvent>[];
      final c = live(async, eng);
      c.events.listen(events.add);

      // Three max-offset drops: 0.55 + 0.55 ≥ 1.0 → the 2nd sloppy drop kills.
      drop(async, c, 0.25, 0); // Ann: +0.55
      nextTurn(c);
      drop(async, c, 0.25, 0); // Bob: +0.55 → 1.10 ≥ 1.0 → collapse
      expect(c.phase, TowerTrialsPhase.collapsing);
      expect(c.collapsedBy, 'Bob');
      expect(
        events.any((e) =>
            e.type == TowerTrialsEventType.collapse && e.playerName == 'Bob'),
        isTrue,
      );

      // Tumble FX beat, then straight to results — only Ann stands.
      async.elapse(const Duration(milliseconds: 1500));
      async.flushMicrotasks();
      expect(c.phase, TowerTrialsPhase.results);
      expect(c.winnerName, 'Ann');
      expect(
        events.any((e) =>
            e.type == TowerTrialsEventType.winner && e.playerName == 'Ann'),
        isTrue,
      );
      expect(c.finishOrder, ['Ann', 'Bob']);
      c.dispose();
    });
  });

  test('collapse removes every block node (and the ghost) from the scene', () {
    fakeAsync((async) {
      final eng = FakeArEngine();
      final c = live(async, eng);

      drop(async, c, 0.25, 0);
      nextTurn(c);
      drop(async, c, 0.25, 0);
      expect(c.phase, TowerTrialsPhase.collapsing);
      async.elapse(const Duration(milliseconds: 1500));
      async.flushMicrotasks();

      // Spawned: base n0, ghost n1, Ann's n2, Bob's n3 — ALL removed.
      expect(eng.removedIds.toSet(), {'n0', 'n1', 'n2', 'n3'});
      expect(c.tower, isEmpty);
      c.dispose();
    });
  });

  test('multi-round: 3 players, eliminations chain until one stands; each '
      'round resets the tower and starts with the seat after the loser', () {
    fakeAsync((async) {
      final eng = FakeArEngine();
      final c = live(async, eng, names: ['A', 'B', 'C']);

      // Round 1: A sloppy, B sloppy → B eliminated.
      drop(async, c, 0.25, 0);
      nextTurn(c);
      drop(async, c, 0.25, 0);
      expect(c.collapsedBy, 'B');
      async.elapse(const Duration(milliseconds: 1500));
      async.flushMicrotasks();

      // Round 2: fresh tower, C (seat after B) starts, instability reset.
      expect(c.phase, TowerTrialsPhase.handoff);
      expect(c.round, 2);
      expect(c.currentPlayerName, 'C');
      expect(c.instability, 0);
      expect(c.blocksPlaced, 0);
      expect(c.baseReady, isTrue, reason: 'new base spawned');

      // Round 2: C sloppy, A sloppy, C sloppy → C eliminated (B skipped).
      nextTurn(c);
      drop(async, c, 0.20, 0); // C: +0.44
      expect(c.currentPlayerName, 'A', reason: 'B is out — skip her seat');
      nextTurn(c);
      drop(async, c, 0.05, 0); // A: +0.11 → 0.55
      expect(c.currentPlayerName, 'C');
      nextTurn(c);
      drop(async, c, 0.25, 0); // C: +0.55 → 1.10 → collapse
      expect(c.collapsedBy, 'C');
      async.elapse(const Duration(milliseconds: 1500));
      async.flushMicrotasks();

      expect(c.phase, TowerTrialsPhase.results);
      expect(c.winnerName, 'A');
      expect(c.eliminationOrder, ['B', 'C']);
      expect(c.finishOrder, ['A', 'C', 'B'],
          reason: 'winner, then reverse knock-out order');
      c.dispose();
    });
  });

  test('wobbling tower animates via engine.move, deterministically from '
      'cumulative offset (no physics)', () {
    fakeAsync((async) {
      final eng = FakeArEngine();
      final c = live(async, eng);

      drop(async, c, 0.20, 0.0); // real wobble now exists
      // Ann's block is n2; its logical position:
      final logical = eng.positions['n2']!;
      async.elapse(TowerTrialsController.animTick);
      final moved = eng.positions['n2']!;
      // The anim tick displaced the block from its logical spot (lean+wobble).
      expect(moved.x != logical.x || moved.z != logical.z, isTrue);
      // The base never sways.
      final base = eng.positions['n0']!;
      expect(base.y, closeTo(-TowerTrialsController.baseDrop, 1e-9));
      expect(base.x, closeTo(0, 1e-9));
      c.dispose();
    });
  });

  test('guards: beginTurn only from handoff, drop only while aiming', () {
    fakeAsync((async) {
      final eng = FakeArEngine();
      final c = TowerTrialsController(engine: eng);
      c.start();
      async.flushMicrotasks();

      c.beginTurn(); // still in setup
      expect(c.phase, TowerTrialsPhase.setup);
      c.dropBlock();
      expect(c.blocksPlaced, 0);

      c.startGame(['Ann', 'Bob']);
      async.flushMicrotasks();
      c.updateAim(0.1, 0.1); // handoff — ignored
      expect(c.hasAim, isFalse);
      c.dropBlock();
      expect(c.blocksPlaced, 0);
      c.dispose();
    });
  });
}
