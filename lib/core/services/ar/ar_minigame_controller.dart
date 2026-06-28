import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'ar_engine.dart';
import 'ar_games.dart';

/// The ONE shared tap-game framework that drives Balloon Pop and Treasure Hunt.
/// It talks ONLY to the [ArEngine] abstraction (never a plugin), so all of its
/// logic — spawning, scoring, respawn, the countdown, win detection — is unit
/// testable with a fake engine and [package:fake_async].
///
/// Lifecycle: [start] → objects spawn (on first detected plane, or a short
/// fallback) → player taps objects (each tap removes the node + scores; Balloon
/// Pop respawns, Treasure Hunt ends when all gems are found) → the countdown or
/// a full clear calls [finish]. Listeners (the HUD + the screen) read [hits],
/// [secondsRemaining], [liveScore], [finished] and [finalScore].
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
  int hits = 0;
  int secondsRemaining;
  int finalScore = 0;
  String? error;

  /// The live, in-progress score shown on the HUD.
  int get liveScore =>
      config.computeScore(hits: hits, secondsRemaining: _clampedSeconds);

  /// Gems still to find (Treasure Hunt) / balloons currently floating.
  int get objectsRemaining =>
      config.respawnOnHit ? _activeNodes.length : config.objectCount - hits;

  /// Whether at least one model actually placed. Lets the UI surface a
  /// model-load failure instead of silently running a timer over an empty scene.
  bool get hasLiveObjects => _activeNodes.isNotEmpty;

  // ---- Internals ----------------------------------------------------------
  final List<ArNode> _activeNodes = [];
  final Map<String, ArVector3> _basePos = {};
  StreamSubscription<ArTap>? _tapSub;
  StreamSubscription<ArPlane>? _planeSub;
  Timer? _countdown;
  Timer? _bobTimer;
  Timer? _fallbackTimer;
  double _bobClock = 0;
  bool _disposed = false;

  int get _clampedSeconds => secondsRemaining < 0 ? 0 : secondsRemaining;

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
    _spawnInitial();
    _countdown = Timer.periodic(const Duration(seconds: 1), _onTick);
    if (config.respawnOnHit) {
      _bobTimer = Timer.periodic(const Duration(milliseconds: 120), _onBob);
    }
    _safeNotify();
  }

  Future<void> _spawnInitial() async {
    for (var i = 0; i < config.objectCount; i++) {
      if (_disposed || finished) return;
      await _spawnOne();
    }
  }

  Future<void> _spawnOne() async {
    final pos = _randomPosition();
    try {
      final node = await engine.spawn(modelRef: config.modelRef, position: pos);
      if (_disposed || finished) {
        await engine.remove(node);
        return;
      }
      _activeNodes.add(node);
      _basePos[node.id] = pos;
      _safeNotify();
    } catch (e) {
      // A single failed placement must not kill the round; record once.
      error ??= e.toString();
    }
  }

  void _onTap(ArTap tap) {
    if (finished || _disposed) return;
    final idx = _activeNodes.indexWhere((n) => n.id == tap.nodeId);
    if (idx == -1) return; // a plane tap or a stale node — ignore.

    final node = _activeNodes.removeAt(idx);
    _basePos.remove(node.id);
    engine.remove(node);
    hits++;
    _safeNotify();

    if (config.respawnOnHit) {
      _spawnOne();
    } else if (hits >= config.objectCount) {
      finish();
    }
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

  void _onBob(Timer _) {
    if (finished || _disposed) return;
    _bobClock += 0.12;
    for (final node in _activeNodes) {
      final base = _basePos[node.id];
      if (base == null) continue;
      final dy = sin(_bobClock + base.x * 3) * 0.04;
      engine.move(node, ArVector3(base.x, base.y + dy, base.z));
    }
  }

  /// End the round and compute the final score. Idempotent.
  void finish() {
    if (finished) return;
    finished = true;
    _countdown?.cancel();
    _bobTimer?.cancel();
    _fallbackTimer?.cancel();
    _planeSub?.cancel();
    finalScore =
        config.computeScore(hits: hits, secondsRemaining: _clampedSeconds);
    _safeNotify();
  }

  ArVector3 _randomPosition() {
    // Spread objects across a ~140° arc, 1.0–2.5 m out, around eye level.
    final angle = (_random.nextDouble() * 2 - 1) * 1.2; // ±~70°
    final dist = 1.0 + _random.nextDouble() * 1.5;
    final x = sin(angle) * dist;
    final z = -cos(angle) * dist; // forward is -z
    final y = -0.3 + _random.nextDouble() * 1.2;
    return ArVector3(x, y, z);
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _countdown?.cancel();
    _bobTimer?.cancel();
    _fallbackTimer?.cancel();
    _tapSub?.cancel();
    _planeSub?.cancel();
    engine.dispose();
    super.dispose();
  }
}
