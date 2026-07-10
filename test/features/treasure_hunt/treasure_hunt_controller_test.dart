import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/services/ar/ar_engine.dart';
import 'package:taskcaster_app/features/treasure_hunt/treasure_hunt_controller.dart';

/// Plugin-free fake engine. [pose] is the current camera position (null =
/// tracking lost); it records front-of-camera spawns + removals and lets a test
/// drive gem taps.
class FakeArEngine implements ArEngine {
  final _planes = StreamController<ArPlane>.broadcast();
  final _taps = StreamController<ArTap>.broadcast();
  int _counter = 0;

  ArVector3? pose;
  bool spawnFrontReturnsNull = false;
  final List<String> frontSpawns = [];
  final List<String> removedIds = [];
  ArNode? lastFrontNode;

  /// When set, [cameraPosition] hangs on this completer instead of returning
  /// [pose] immediately — lets a test straddle a poll's await across an
  /// _endTurn() to reproduce the FINDING A soft-lock race.
  Completer<ArVector3?>? poseGate;

  @override
  Widget buildView() => const SizedBox.shrink();

  @override
  Future<void> initSession() async {}

  @override
  Stream<ArPlane> get planes => _planes.stream;

  @override
  Stream<ArTap> get taps => _taps.stream;

  @override
  Future<ArVector3?> cameraPosition() {
    final gate = poseGate;
    if (gate != null) return gate.future;
    return Future.value(pose);
  }

  @override
  Future<ArNode?> spawnInFrontOfCamera({
    required String modelRef,
    double distance = 1.0,
    double drop = 0.0,
  }) async {
    if (spawnFrontReturnsNull || pose == null) return null;
    frontSpawns.add(modelRef);
    lastFrontNode = ArNode('gem${_counter++}');
    return lastFrontNode;
  }

  @override
  Future<ArNode> spawn({
    required String modelRef,
    required ArVector3 position,
    ArPlane? onPlane,
  }) async =>
      ArNode('n${_counter++}');

  @override
  Future<void> move(ArNode node, ArVector3 position) async {}

  @override
  Future<void> remove(ArNode node) async => removedIds.add(node.id);

  @override
  Future<void> dispose() async {}

  void emitTap(String id) => _taps.add(ArTap(id));
}

void main() {
  const origin = ArVector3(0, 0, 0);

  /// Drive a controller through hide (at [hides]) and into the live hunt.
  TreasureHuntController hunting(
    FakeAsync async,
    FakeArEngine eng, {
    required List<ArVector3> hides,
  }) {
    final c = TreasureHuntController(engine: eng);
    c.start();
    async.flushMicrotasks();
    for (final h in hides) {
      eng.pose = h;
      c.hideHere();
      async.flushMicrotasks();
    }
    c.doneHiding();
    c.beginCountdown();
    async.elapse(const Duration(milliseconds: 2200)); // 3-2-1 → hunt
    return c;
  }

  // ---- Pure mappings --------------------------------------------------------

  group('tickIntervalMsForDistance (pure geiger)', () {
    test('silence with no target or beyond 6 m', () {
      expect(TreasureHuntController.tickIntervalMsForDistance(null), isNull);
      expect(TreasureHuntController.tickIntervalMsForDistance(6.01), isNull);
      expect(TreasureHuntController.tickIntervalMsForDistance(50), isNull);
    });

    test('exactly 6 m is the slowest audible tick', () {
      expect(TreasureHuntController.tickIntervalMsForDistance(6.0),
          TreasureHuntController.slowestIntervalMs);
    });

    test('frantic at/under 1 m (~8 ticks/sec)', () {
      expect(TreasureHuntController.tickIntervalMsForDistance(1.0),
          TreasureHuntController.franticIntervalMs);
      expect(TreasureHuntController.tickIntervalMsForDistance(0.3),
          TreasureHuntController.franticIntervalMs);
      expect(TreasureHuntController.franticIntervalMs, 125);
    });

    test('interval shortens monotonically as you get closer', () {
      final near = TreasureHuntController.tickIntervalMsForDistance(2.0)!;
      final mid = TreasureHuntController.tickIntervalMsForDistance(4.0)!;
      final far = TreasureHuntController.tickIntervalMsForDistance(5.5)!;
      expect(near, lessThan(mid));
      expect(mid, lessThan(far));
    });
  });

  group('heatForDistance (haptics)', () {
    test('boundaries', () {
      expect(TreasureHuntController.heatForDistance(null), GeigerHeat.silent);
      expect(TreasureHuntController.heatForDistance(7), GeigerHeat.silent);
      expect(TreasureHuntController.heatForDistance(5), GeigerHeat.cold);
      expect(TreasureHuntController.heatForDistance(3.0), GeigerHeat.warm);
      expect(TreasureHuntController.heatForDistance(1.0), GeigerHeat.hot);
    });
  });

  // ---- Hide phase -----------------------------------------------------------

  test('hideHere stores the camera position; caps at maxTreasures', () {
    fakeAsync((async) {
      final eng = FakeArEngine();
      final c = TreasureHuntController(engine: eng, maxTreasures: 2);
      c.start();
      async.flushMicrotasks();

      eng.pose = const ArVector3(1, 0, 0);
      c.hideHere();
      async.flushMicrotasks();
      expect(c.treasureCount, 1);

      eng.pose = const ArVector3(2, 0, 0);
      c.hideHere();
      async.flushMicrotasks();
      expect(c.treasureCount, 2);
      expect(c.canHideMore, isFalse);

      // Third is rejected by the cap.
      eng.pose = const ArVector3(3, 0, 0);
      c.hideHere();
      async.flushMicrotasks();
      expect(c.treasureCount, 2);
      c.dispose();
    });
  });

  test('hideHere does nothing while tracking is lost (null pose)', () {
    fakeAsync((async) {
      final eng = FakeArEngine();
      final c = TreasureHuntController(engine: eng);
      c.start();
      async.flushMicrotasks();

      eng.pose = null; // tracking lost
      c.hideHere();
      async.flushMicrotasks();
      expect(c.treasureCount, 0);
      c.dispose();
    });
  });

  test('doneHiding requires at least one spot', () {
    fakeAsync((async) {
      final eng = FakeArEngine();
      final c = TreasureHuntController(engine: eng);
      c.start();
      async.flushMicrotasks();

      c.doneHiding();
      expect(c.phase, TreasureHuntPhase.hiding, reason: 'no spots yet');

      eng.pose = origin;
      c.hideHere();
      async.flushMicrotasks();
      c.doneHiding();
      expect(c.phase, TreasureHuntPhase.handoff);
      c.dispose();
    });
  });

  // ---- Phase flow -----------------------------------------------------------

  test('hiding → handoff → countdown → hunting, emitting go', () {
    fakeAsync((async) {
      final eng = FakeArEngine();
      final events = <TreasureHuntEventType>[];
      final c = TreasureHuntController(engine: eng);
      c.events.listen((e) => events.add(e.type));
      c.start();
      async.flushMicrotasks();

      eng.pose = origin;
      c.hideHere();
      async.flushMicrotasks();
      c.doneHiding();
      expect(c.phase, TreasureHuntPhase.handoff);

      c.beginCountdown();
      expect(c.phase, TreasureHuntPhase.countdown);
      expect(c.countdownValue, 3);

      async.elapse(const Duration(milliseconds: 2200));
      expect(c.phase, TreasureHuntPhase.hunting);
      expect(c.secondsRemaining, 90);
      expect(events, contains(TreasureHuntEventType.go));
      c.dispose();
    });
  });

  // ---- Reveal / collect / retarget -----------------------------------------

  test('coming within 1 m reveals a gem in front of the camera, once', () {
    fakeAsync((async) {
      final eng = FakeArEngine();
      final c = hunting(async, eng, hides: [origin]);

      // Seeker is 0.5 m from the hidden spot → reveal.
      eng.pose = const ArVector3(0.5, 0, 0);
      async.elapse(TreasureHuntController.pollInterval);
      async.flushMicrotasks();

      expect(c.revealPending, isTrue);
      expect(eng.frontSpawns, ['assets/ar/gem.glb']);

      // Still close: further polls must NOT spawn another gem.
      async.elapse(TreasureHuntController.pollInterval);
      async.flushMicrotasks();
      expect(eng.frontSpawns.length, 1, reason: 'reveal fires once per spot');
      c.dispose();
    });
  });

  test('tapping the revealed gem collects it (found + removed)', () {
    fakeAsync((async) {
      final eng = FakeArEngine();
      final c = hunting(async, eng, hides: [origin]);

      eng.pose = const ArVector3(0.5, 0, 0);
      async.elapse(TreasureHuntController.pollInterval);
      async.flushMicrotasks();
      expect(c.revealPending, isTrue);

      eng.emitTap(eng.lastFrontNode!.id);
      async.flushMicrotasks();

      expect(c.revealPending, isFalse);
      expect(c.foundThisTurn, 1);
      expect(eng.removedIds, contains(eng.lastFrontNode!.id));
      // Only one treasure → the turn ends as a win.
      expect(c.phase, TreasureHuntPhase.betweenTurns);
      c.dispose();
    });
  });

  test('collectRevealed (banner tap) works and retargets the next nearest', () {
    fakeAsync((async) {
      final eng = FakeArEngine();
      final c = hunting(
        async,
        eng,
        hides: [const ArVector3(0, 0, 0), const ArVector3(5, 0, 0)],
      );

      // Near treasure A.
      eng.pose = const ArVector3(0.4, 0, 0);
      async.elapse(TreasureHuntController.pollInterval);
      async.flushMicrotasks();
      expect(c.revealedIndex, 0);

      c.collectRevealed();
      expect(c.foundThisTurn, 1);
      expect(c.phase, TreasureHuntPhase.hunting, reason: 'one still hidden');

      // Walk to treasure B → geiger retargets and reveals it.
      eng.pose = const ArVector3(5.2, 0, 0);
      async.elapse(TreasureHuntController.pollInterval);
      async.flushMicrotasks();
      expect(c.revealedIndex, 1);
      expect(eng.frontSpawns.length, 2);
      c.dispose();
    });
  });

  test('a null spawn (no pose at reveal) still collects via the banner', () {
    fakeAsync((async) {
      final eng = FakeArEngine();
      final c = hunting(async, eng, hides: [origin]);

      eng.spawnFrontReturnsNull = true; // simulate placement failure
      eng.pose = const ArVector3(0.6, 0, 0);
      async.elapse(TreasureHuntController.pollInterval);
      async.flushMicrotasks();
      expect(c.revealPending, isTrue);
      expect(eng.lastFrontNode, isNull);

      c.collectRevealed();
      expect(c.foundThisTurn, 1);
      c.dispose();
    });
  });

  // ---- Tracking loss --------------------------------------------------------

  test('tracking loss pauses the timer + geiger; regain resumes them', () {
    fakeAsync((async) {
      final eng = FakeArEngine();
      final c = hunting(async, eng, hides: [origin]);

      // Seeker far away (silent, no reveal); clock runs.
      eng.pose = const ArVector3(10, 0, 0);
      async.elapse(const Duration(seconds: 3));
      async.flushMicrotasks();
      final beforeLoss = c.secondsRemaining;
      expect(beforeLoss, 87);

      // Lose tracking.
      eng.pose = null;
      async.elapse(TreasureHuntController.pollInterval);
      async.flushMicrotasks();
      expect(c.phase, TreasureHuntPhase.trackingLost);

      // Clock is frozen for the whole outage.
      async.elapse(const Duration(seconds: 5));
      async.flushMicrotasks();
      expect(c.secondsRemaining, beforeLoss, reason: 'timer paused');

      // Regain tracking → back to hunting, clock ticks again.
      eng.pose = const ArVector3(10, 0, 0);
      async.elapse(TreasureHuntController.pollInterval);
      async.flushMicrotasks();
      expect(c.phase, TreasureHuntPhase.hunting);
      async.elapse(const Duration(seconds: 2));
      expect(c.secondsRemaining, lessThan(beforeLoss));
      c.dispose();
    });
  });

  // ---- Turn end / next seeker / leaderboard --------------------------------

  test('time up ends the turn and records the result', () {
    fakeAsync((async) {
      final eng = FakeArEngine();
      final c = TreasureHuntController(
        engine: eng,
        huntDuration: const Duration(seconds: 4),
      );
      final events = <TreasureHuntEventType>[];
      c.events.listen((e) => events.add(e.type));
      c.start();
      async.flushMicrotasks();
      eng.pose = origin;
      c.hideHere();
      async.flushMicrotasks();
      c.doneHiding();
      c.beginCountdown();
      async.elapse(const Duration(milliseconds: 2200));

      eng.pose = const ArVector3(10, 0, 0); // stay far → find nothing
      async.elapse(const Duration(seconds: 5));
      async.flushMicrotasks();

      expect(c.phase, TreasureHuntPhase.betweenTurns);
      expect(events, contains(TreasureHuntEventType.timeUp));
      expect(c.leaderboard.single.treasuresFound, 0);
      expect(c.leaderboard.single.timeUsedSeconds, 4);
      c.dispose();
    });
  });

  test('next seeker replays the SAME layout with found flags reset', () {
    fakeAsync((async) {
      final eng = FakeArEngine();
      final c = hunting(async, eng, hides: [origin], /* Seeker 1 */);

      // Seeker 1 finds it (win).
      eng.pose = const ArVector3(0.3, 0, 0);
      async.elapse(TreasureHuntController.pollInterval);
      async.flushMicrotasks();
      c.collectRevealed();
      expect(c.phase, TreasureHuntPhase.betweenTurns);

      // Hand off to seeker 2 — same hidden spot, fresh run.
      c.nextSeeker('Bob');
      expect(c.phase, TreasureHuntPhase.handoff);
      expect(c.currentSeekerName, 'Bob');
      c.beginCountdown();
      async.elapse(const Duration(milliseconds: 2200));
      expect(c.phase, TreasureHuntPhase.hunting);
      expect(c.foundThisTurn, 0, reason: 'found flags reset');
      expect(c.totalTreasures, 1, reason: 'layout preserved');

      // The same spot is findable again.
      eng.pose = const ArVector3(0.3, 0, 0);
      async.elapse(TreasureHuntController.pollInterval);
      async.flushMicrotasks();
      expect(c.revealPending, isTrue);
      c.dispose();
    });
  });

  test('leaderboard ranks by treasures found, then by fastest time', () {
    fakeAsync((async) {
      final eng = FakeArEngine();
      final c = TreasureHuntController(
        engine: eng,
        huntDuration: const Duration(seconds: 60),
        firstSeekerName: 'Ann',
      );
      c.start();
      async.flushMicrotasks();
      eng.pose = origin;
      c.hideHere();
      async.flushMicrotasks();
      c.doneHiding();

      // Ann: finds it quickly.
      c.beginCountdown();
      async.elapse(const Duration(milliseconds: 2200));
      eng.pose = const ArVector3(0.3, 0, 0);
      async.elapse(TreasureHuntController.pollInterval);
      async.flushMicrotasks();
      c.collectRevealed();
      expect(c.phase, TreasureHuntPhase.betweenTurns);

      // Bob: never finds it (times out with 0).
      c.nextSeeker('Bob');
      c.beginCountdown();
      async.elapse(const Duration(milliseconds: 2200));
      eng.pose = const ArVector3(10, 0, 0);
      async.elapse(const Duration(seconds: 61));
      async.flushMicrotasks();

      final board = c.leaderboard;
      expect(board.length, 2);
      expect(board.first.seekerName, 'Ann', reason: 'more found ranks first');
      expect(board.first.treasuresFound, 1);
      expect(board.last.seekerName, 'Bob');

      c.finishGame();
      expect(c.phase, TreasureHuntPhase.results);
      c.dispose();
    });
  });

  test('all-found ends the turn with an allFound event + time bonus recorded',
      () {
    fakeAsync((async) {
      final eng = FakeArEngine();
      final events = <TreasureHuntEventType>[];
      final c = TreasureHuntController(
        engine: eng,
        huntDuration: const Duration(seconds: 90),
      );
      c.events.listen((e) => events.add(e.type));
      c.start();
      async.flushMicrotasks();
      eng.pose = origin;
      c.hideHere();
      async.flushMicrotasks();
      c.doneHiding();
      c.beginCountdown();
      async.elapse(const Duration(milliseconds: 2200));

      // Spend ~10s then find it.
      eng.pose = const ArVector3(10, 0, 0);
      async.elapse(const Duration(seconds: 10));
      async.flushMicrotasks();
      eng.pose = const ArVector3(0.3, 0, 0);
      async.elapse(TreasureHuntController.pollInterval);
      async.flushMicrotasks();
      c.collectRevealed();
      async.flushMicrotasks(); // deliver the collect + allFound stream events

      expect(events, contains(TreasureHuntEventType.allFound));
      final r = c.leaderboard.single;
      expect(r.allFound, isTrue);
      expect(r.timeUsedSeconds, lessThan(90),
          reason: 'finishing early beats the clock');
      c.dispose();
    });
  });

  // ---- Regression: async race / double-end / cap / header (FINDINGS A–D) ----

  test('FINDING A: a late null poll resolving after time-up does NOT '
      'flip to trackingLost (no soft-lock)', () {
    fakeAsync((async) {
      final eng = FakeArEngine();
      final c = TreasureHuntController(
        engine: eng,
        huntDuration: const Duration(seconds: 3),
      );
      c.start();
      async.flushMicrotasks();
      eng.pose = origin;
      c.hideHere();
      async.flushMicrotasks();
      c.doneHiding();
      c.beginCountdown();
      async.elapse(const Duration(milliseconds: 2200)); // → hunting

      // Gate the NEXT camera read so a poll suspends mid-await.
      final gate = Completer<ArVector3?>();
      eng.poseGate = gate;
      async.elapse(TreasureHuntController.pollInterval); // poll starts + hangs
      expect(c.phase, TreasureHuntPhase.hunting);

      // The hunt clock runs out WHILE the poll is still awaiting → _endTurn.
      async.elapse(const Duration(seconds: 4));
      async.flushMicrotasks();
      expect(c.phase, TreasureHuntPhase.betweenTurns);

      // The stale poll now resolves null (tracking-lost signal), too late.
      gate.complete(null);
      async.flushMicrotasks();

      expect(c.phase, TreasureHuntPhase.betweenTurns,
          reason: 'stale null must be dropped, not resurrect trackingLost');
      expect(c.leaderboard.length, 1, reason: 'no duplicate turn recorded');
      c.dispose();
    });
  });

  test('FINDING B: collect after time-up is ignored; _endTurn clears the '
      'revealed gem and never double-records', () {
    fakeAsync((async) {
      final eng = FakeArEngine();
      // Two treasures so revealing/finding one does NOT end the turn.
      final c = TreasureHuntController(
        engine: eng,
        huntDuration: const Duration(seconds: 3),
      );
      c.start();
      async.flushMicrotasks();
      eng.pose = const ArVector3(0, 0, 0);
      c.hideHere();
      async.flushMicrotasks();
      eng.pose = const ArVector3(5, 0, 0);
      c.hideHere();
      async.flushMicrotasks();
      c.doneHiding();
      c.beginCountdown();
      async.elapse(const Duration(milliseconds: 2200)); // → hunting

      // Reveal treasure 0 (but don't collect it).
      eng.pose = const ArVector3(0.5, 0, 0);
      async.elapse(TreasureHuntController.pollInterval);
      async.flushMicrotasks();
      expect(c.revealPending, isTrue);
      final gemId = eng.lastFrontNode!.id;

      // Let the clock run out with the gem still revealed → _endTurn(timeUp).
      async.elapse(const Duration(seconds: 4));
      async.flushMicrotasks();
      expect(c.phase, TreasureHuntPhase.betweenTurns);

      // _endTurn cleared the reveal state and removed the spawned gem.
      expect(c.revealPending, isFalse, reason: 'reveal state cleared on end');
      expect(eng.removedIds, contains(gemId), reason: 'gem node removed');
      expect(c.leaderboard.length, 1);
      expect(c.foundThisTurn, 0);

      // A stale tap on the (gone) gem/banner in betweenTurns is a no-op.
      c.collectRevealed();
      async.flushMicrotasks();
      expect(c.leaderboard.length, 1, reason: 'no duplicate result row');
      expect(c.foundThisTurn, 0, reason: 'stale collect ignored');
      expect(c.phase, TreasureHuntPhase.betweenTurns);
      c.dispose();
    });
  });

  test('FINDING C: concurrent hideHere at the cap never exceeds maxTreasures',
      () {
    fakeAsync((async) {
      final eng = FakeArEngine();
      final c = TreasureHuntController(engine: eng, maxTreasures: 5);
      c.start();
      async.flushMicrotasks();

      // Fill 4 of 5 serially.
      for (var i = 0; i < 4; i++) {
        eng.pose = ArVector3(i.toDouble(), 0, 0);
        c.hideHere();
        async.flushMicrotasks();
      }
      expect(c.treasureCount, 4);
      expect(c.canHideMore, isTrue);

      // Double-tap "Hide here" at 4/5: two calls in flight before either awaits.
      eng.pose = const ArVector3(9, 0, 0);
      bool? r1, r2;
      c.hideHere().then((v) => r1 = v);
      c.hideHere().then((v) => r2 = v);
      async.flushMicrotasks();

      expect(c.treasureCount, 5, reason: 'the cap holds — never 6/5');
      expect(c.canHideMore, isFalse);
      expect([r1, r2], containsAll(<bool>[true, false]),
          reason: 'exactly one concurrent hide succeeds');
      c.dispose();
    });
  });

  test('FINDING D: lastTurnResult is the turn that just ended, not the best '
      'leaderboard row', () {
    fakeAsync((async) {
      final eng = FakeArEngine();
      final c = TreasureHuntController(
        engine: eng,
        huntDuration: const Duration(seconds: 60),
        firstSeekerName: 'Ann',
      );
      c.start();
      async.flushMicrotasks();
      eng.pose = origin;
      c.hideHere();
      async.flushMicrotasks();
      c.doneHiding();

      // Ann aces it (allFound).
      c.beginCountdown();
      async.elapse(const Duration(milliseconds: 2200));
      eng.pose = const ArVector3(0.3, 0, 0);
      async.elapse(TreasureHuntController.pollInterval);
      async.flushMicrotasks();
      c.collectRevealed();
      expect(c.phase, TreasureHuntPhase.betweenTurns);
      expect(c.lastTurnResult!.seekerName, 'Ann');
      expect(c.lastTurnResult!.allFound, isTrue);

      // Bob times out with nothing.
      c.nextSeeker('Bob');
      c.beginCountdown();
      async.elapse(const Duration(milliseconds: 2200));
      eng.pose = const ArVector3(10, 0, 0);
      async.elapse(const Duration(seconds: 61));
      async.flushMicrotasks();

      // Just-ended turn is Bob's failure; leaderboard.first is still Ann.
      expect(c.lastTurnResult!.seekerName, 'Bob');
      expect(c.lastTurnResult!.allFound, isFalse,
          reason: 'header must read "Time\'s up!" for Bob');
      expect(c.leaderboard.first.seekerName, 'Ann',
          reason: 'best-sorted row is unchanged — the bug source');
      c.dispose();
    });
  });
}
