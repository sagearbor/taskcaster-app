import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'ar_engine.dart';
import 'ar_games.dart';

/// One live object in the scene (a target or a bomb), with the bookkeeping the
/// animation + scoring need.
class _LiveObject {
  final ArNode node;
  final ArVector3 base; // spawn position; rise/wiggle are offsets from this
  final bool isBomb;
  final int value; // points awarded when popped (0 for bombs)
  final double phase; // per-object wiggle phase so they don't move in lockstep
  double age = 0; // seconds since it appeared (drives rise + escape)

  _LiveObject({
    required this.node,
    required this.base,
    required this.isBomb,
    required this.value,
    required this.phase,
  });
}

/// The ONE shared tap-game framework that drives Balloon Pop and Treasure Hunt.
/// It talks ONLY to the [ArEngine] abstraction (never a plugin), so all of its
/// logic — spawning, scoring, respawn, bombs, rise-and-escape, the countdown,
/// win detection — is unit testable with a fake engine and [package:fake_async].
///
/// Lifecycle: [start] → objects spawn (on first detected plane, or a short
/// fallback) → player taps objects (each target tap removes the node + scores;
/// each bomb tap costs points; Balloon Pop respawns, Treasure Hunt ends when all
/// gems are found) → the countdown or a full clear calls [finish]. Listeners
/// (the HUD + the screen) read [hits], [secondsRemaining], [liveScore],
/// [finished], [finalScore] and [bombFlash].
class ArMinigameController extends ChangeNotifier {
  final ArEngine engine;
  final ArGameConfig config;
  final Random _random;

  /// How long to wait for a detected plane before spawning anyway (so the game
  /// still starts in a feature-poor room).
  final Duration spawnFallback;

  ArMinigameController({
    required this.engine,
    required this.config,
    Random? random,
    this.spawnFallback = const Duration(seconds: 2),
  })  : _random = random ?? Random(),
        secondsRemaining = config.duration.inSeconds;

  // ---- Observable state ---------------------------------------------------
  bool started = false;
  bool finished = false;
  bool objectsSpawned = false;
  int hits = 0; // targets popped (NOT bombs) — drives the "X popped" readout
  int bombsHit = 0;
  int secondsRemaining;
  int finalScore = 0;
  String? error;

  /// True briefly after a bomb is tapped, so the view can flash a red "oops".
  bool bombFlash = false;

  /// Running points for distance-scored games (Balloon Pop). Bomb penalties are
  /// already subtracted; never below 0.
  int _points = 0;

  /// The live, in-progress score shown on the HUD.
  int get liveScore => config.scoreByDistance
      ? _points
      : config.computeScore(hits: hits, secondsRemaining: _clampedSeconds);

  /// Gems still to find (Treasure Hunt) / objects currently floating.
  int get objectsRemaining =>
      config.respawnOnHit ? _objects.length : config.objectCount - hits;

  /// Whether at least one model actually placed. Lets the UI surface a
  /// model-load failure instead of silently running a timer over an empty scene.
  bool get hasLiveObjects => _objects.isNotEmpty;

  // ---- Internals ----------------------------------------------------------
  final List<_LiveObject> _objects = [];
  StreamSubscription<ArTap>? _tapSub;
  StreamSubscription<ArPlane>? _planeSub;
  Timer? _countdown;
  Timer? _animTimer;
  Timer? _fallbackTimer;
  Timer? _flashTimer;
  double _animClock = 0;
  bool _disposed = false;

  static const double _riseSpeed = 0.16; // metres/second a balloon floats up
  static const double _animDt = 0.06; // animation tick (~16 fps)

  int get _clampedSeconds => secondsRemaining < 0 ? 0 : secondsRemaining;

  bool get _animated =>
      config.respawnOnHit || config.objectLifespan > Duration.zero;

  /// Begin the round. Safe to call once; further calls are ignored.
  Future<void> start() async {
    if (started) return;
    started = true;
    _safeNotify();

    try {
      await engine.initSession();
    } catch (e) {
      error = e.toString();
      _safeNotify();
      return;
    }
    if (_disposed) return;

    _tapSub = engine.taps.listen(_onTap);
    // Spawn once tracking finds a surface, or after a short fallback so we never
    // hang in a featureless room.
    _planeSub = engine.planes.listen((_) => _spawnObjects());
    _fallbackTimer = Timer(spawnFallback, _spawnObjects);
  }

  void _spawnObjects() {
    if (objectsSpawned || finished || _disposed) return;
    objectsSpawned = true;
    _planeSub?.cancel();
    _fallbackTimer?.cancel();

    // Spawn the initial objects one at a time (sequential awaits) rather than
    // firing all placements concurrently — concurrent spawns raced on both the
    // model-file write and the native addNode, intermittently failing nodes.
    // The countdown is started from inside _spawnInitial, only once the first
    // object is actually live, so the clock never ticks during scanning/loading.
    _spawnInitial();
    _safeNotify();
  }

  void _startClocks() {
    if (_countdown != null) return; // already running
    _countdown = Timer.periodic(const Duration(seconds: 1), _onTick);
    if (_animated) {
      _animTimer = Timer.periodic(
        const Duration(milliseconds: 60),
        _onAnim,
      );
    }
    _safeNotify();
  }

  Future<void> _spawnInitial() async {
    for (var i = 0; i < config.objectCount; i++) {
      if (_disposed || finished) return;
      await _spawnOne();
      // Start the clock as soon as the first object is actually on screen.
      if (hasLiveObjects) _startClocks();
    }
  }

  Future<void> _spawnOne() async {
    final pos = _randomPosition();
    final isBomb = config.bombChance > 0 &&
        config.bombModelRef != null &&
        _random.nextDouble() < config.bombChance;
    final model = isBomb ? config.bombModelRef! : config.modelRef;
    final value = isBomb ? 0 : _scoreForPosition(pos);
    try {
      final node = await engine.spawn(modelRef: model, position: pos);
      if (_disposed || finished) {
        await engine.remove(node);
        return;
      }
      _objects.add(_LiveObject(
        node: node,
        base: pos,
        isBomb: isBomb,
        value: value,
        phase: _random.nextDouble() * 2 * pi,
      ));
      _safeNotify();
    } catch (e) {
      // A single failed placement must not kill the round; record once.
      error ??= e.toString();
    }
  }

  void _onTap(ArTap tap) {
    if (finished || _disposed) return;
    final idx = _objects.indexWhere((o) => o.node.id == tap.nodeId);
    if (idx == -1) return; // a plane tap or a stale node — ignore.

    final obj = _objects.removeAt(idx);
    engine.remove(obj.node);

    if (obj.isBomb) {
      bombsHit++;
      _points = max(0, _points - config.bombPenalty);
      _flashBomb();
    } else {
      hits++;
      if (config.scoreByDistance) _points += obj.value;
    }
    _safeNotify();

    if (config.respawnOnHit) {
      _spawnOne();
    } else if (!obj.isBomb && hits >= config.objectCount) {
      finish();
    }
  }

  void _flashBomb() {
    bombFlash = true;
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 450), () {
      bombFlash = false;
      _safeNotify();
    });
  }

  void _onTick(Timer _) {
    if (finished || _disposed) return;
    secondsRemaining--;
    if (secondsRemaining <= 0) {
      secondsRemaining = 0;
      finish();
    } else {
      _safeNotify();
    }
  }

  void _onAnim(Timer _) {
    if (finished || _disposed) return;
    _animClock += _animDt;
    final lifespanS = config.objectLifespan.inMilliseconds / 1000.0;
    // Iterate a copy: escaping mutates _objects.
    for (final obj in List<_LiveObject>.of(_objects)) {
      obj.age += _animDt;
      if (lifespanS > 0) {
        // Rise straight up with a sideways S-curve wiggle (air escaping).
        final rise = _riseSpeed * obj.age;
        final wx = sin(obj.age * 2.4 + obj.phase) * 0.10;
        final wz = cos(obj.age * 1.6 + obj.phase) * 0.05;
        engine.move(
          obj.node,
          ArVector3(obj.base.x + wx, obj.base.y + rise, obj.base.z + wz),
        );
        if (obj.age >= lifespanS) _escape(obj);
      } else {
        // Gentle bob in place (e.g. Treasure Hunt gems if animated).
        final dy = sin(_animClock + obj.base.x * 3) * 0.04;
        engine.move(
          obj.node,
          ArVector3(obj.base.x, obj.base.y + dy, obj.base.z),
        );
      }
    }
  }

  /// An object floated away unpopped: remove it and (for respawning games) put a
  /// fresh one in its place so the scene stays full.
  void _escape(_LiveObject obj) {
    if (!_objects.remove(obj)) return;
    engine.remove(obj.node);
    _safeNotify();
    if (config.respawnOnHit && !finished && !_disposed) {
      _spawnOne();
    }
  }

  /// End the round and compute the final score. Idempotent.
  void finish() {
    if (finished) return;
    finished = true;
    _countdown?.cancel();
    _animTimer?.cancel();
    _fallbackTimer?.cancel();
    _flashTimer?.cancel();
    _planeSub?.cancel();
    finalScore = config.scoreByDistance
        ? _points
        : config.computeScore(hits: hits, secondsRemaining: _clampedSeconds);
    _safeNotify();
  }

  ArVector3 _randomPosition() {
    // Spread objects across a ~90° arc IN FRONT of the player. Distance varies
    // widely (1.3–3.8 m) so far balloons genuinely look smaller (real AR
    // perspective) and — when [config.scoreByDistance] — are worth more. Even
    // the nearest is at arm's length so a balloon never engulfs the camera.
    final angle = (_random.nextDouble() * 2 - 1) * 0.8; // ±~45°
    final dist = 1.3 + _random.nextDouble() * 2.5; // 1.3–3.8 m
    final x = sin(angle) * dist;
    final z = -cos(angle) * dist; // forward is -z
    final y = -0.2 + _random.nextDouble() * 0.8; // ~knee to just above eye level
    return ArVector3(x, y, z);
  }

  /// Points for a target at [pos]: farther (harder to tap) is worth more, 1–5.
  int _scoreForPosition(ArVector3 pos) {
    if (!config.scoreByDistance) return config.pointsPerHit;
    final dist = sqrt(pos.x * pos.x + pos.y * pos.y + pos.z * pos.z);
    return ((dist - 1.0) / 0.55).floor().clamp(1, 5);
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _countdown?.cancel();
    _animTimer?.cancel();
    _fallbackTimer?.cancel();
    _flashTimer?.cancel();
    _tapSub?.cancel();
    _planeSub?.cancel();
    engine.dispose();
    super.dispose();
  }
}
