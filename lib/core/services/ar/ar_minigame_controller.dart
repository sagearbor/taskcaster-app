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
  final String modelRef; // which model was placed (lets the UI color the FX)
  final double phase; // per-object wiggle phase so they don't move in lockstep
  double age = 0; // seconds since it appeared (drives rise + escape)

  _LiveObject({
    required this.node,
    required this.base,
    required this.isBomb,
    required this.value,
    required this.modelRef,
    required this.phase,
  });
}

/// Discrete game moments the view layer reacts to with sound/haptics/FX.
/// The controller stays pure (no Flutter services); the view decides how each
/// event looks, sounds and feels.
enum ArGameEventType {
  /// First object is actually on screen — tracking locked, pre-roll begins.
  surfaceFound,

  /// The 3-2-1 pre-roll finished; the round clock just started.
  go,

  /// A target was popped ([ArGameEvent.value] = points awarded).
  pop,

  /// A bomb was tapped ([ArGameEvent.value] = penalty subtracted).
  bomb,

  /// A target aged out and floated away unpopped.
  escape,

  /// The round just ended.
  timeUp,
}

class ArGameEvent {
  final ArGameEventType type;
  final int value;

  /// The model of the object involved (pop/bomb/escape), e.g.
  /// 'assets/ar/balloon_red.glb' — lets the view match FX color to the balloon.
  final String? modelRef;

  const ArGameEvent(this.type, {this.value = 0, this.modelRef});
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

  /// 3-2-1 pre-roll digit currently showing (0 = pre-roll over / not started).
  /// The round clock — and tap handling — only go live once this reaches 0
  /// AFTER a pre-roll ran, so every player gets a clean "GO!" moment instead of
  /// the clock silently starting mid-scan.
  int goCountdown = 0;
  bool get inPreRoll => goCountdown > 0;

  /// True while the app is backgrounded (view calls [pause]/[resume]); the
  /// clock and animation freeze so a notification pull doesn't burn the round.
  bool paused = false;
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

  /// Discrete moments (pop/bomb/go/escape/…) for the view's sound + FX layer.
  Stream<ArGameEvent> get events => _events.stream;
  final StreamController<ArGameEvent> _events =
      StreamController<ArGameEvent>.broadcast();

  // ---- Internals ----------------------------------------------------------
  final List<_LiveObject> _objects = [];
  StreamSubscription<ArTap>? _tapSub;
  StreamSubscription<ArPlane>? _planeSub;
  Timer? _countdown;
  Timer? _animTimer;
  Timer? _fallbackTimer;
  Timer? _flashTimer;
  Timer? _preRollTimer;
  bool _preRollStarted = false;
  bool _roundLive = false; // clocks have started (pre-roll finished)
  double _animClock = 0;
  bool _disposed = false;

  /// Cadence of the 3-2-1 pre-roll digits.
  static const Duration _preRollTick = Duration(milliseconds: 900);

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

  /// Run the 3-2-1-GO pre-roll, then start the clocks. Called once, when the
  /// first object is actually on screen. Also reused by [resume] so coming
  /// back from a pause gives the player a beat to re-orient.
  void _beginPreRoll() {
    if (_preRollStarted) return;
    _preRollStarted = true;
    _emit(const ArGameEvent(ArGameEventType.surfaceFound));
    _runPreRoll();
  }

  void _runPreRoll() {
    goCountdown = 3;
    _safeNotify();
    _preRollTimer?.cancel();
    _preRollTimer = Timer.periodic(_preRollTick, (t) {
      if (paused) return; // frozen — digits hold until resume re-runs us
      goCountdown--;
      if (goCountdown <= 0) {
        goCountdown = 0;
        t.cancel();
        _startClocks();
        _emit(const ArGameEvent(ArGameEventType.go));
      }
      _safeNotify();
    });
  }

  void _startClocks() {
    _roundLive = true;
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

  /// Freeze the round (app backgrounded / pause sheet open). Idempotent.
  void pause() {
    if (paused || finished || _disposed) return;
    paused = true;
    _countdown?.cancel();
    _countdown = null;
    _animTimer?.cancel();
    _animTimer = null;
    _preRollTimer?.cancel();
    _safeNotify();
  }

  /// Unfreeze after [pause]. If the round was already live, re-runs the 3-2-1
  /// pre-roll so play never resumes mid-blink.
  void resume() {
    if (!paused || _disposed) return;
    paused = false;
    if (finished) return;
    if (_roundLive || _preRollStarted) {
      _runPreRoll();
    }
    _safeNotify();
  }

  Future<void> _spawnInitial() async {
    for (var i = 0; i < config.objectCount; i++) {
      if (_disposed || finished) return;
      await _spawnOne();
      // Kick off the pre-roll as soon as the first object is on screen; the
      // remaining objects keep placing behind the 3-2-1.
      if (hasLiveObjects) _beginPreRoll();
    }
  }

  Future<void> _spawnOne() async {
    final pos = _randomPosition();
    final isBomb = config.bombChance > 0 &&
        config.bombModelRef != null &&
        _random.nextDouble() < config.bombChance;
    final targets = config.targetModels;
    final model = isBomb
        ? config.bombModelRef!
        : targets[_random.nextInt(targets.length)];
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
        modelRef: model,
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
    // No scoring before "GO!" or while frozen — a race must start fair.
    if (!_roundLive || paused) return;
    final idx = _objects.indexWhere((o) => o.node.id == tap.nodeId);
    if (idx == -1) return; // a plane tap or a stale node — ignore.

    final obj = _objects.removeAt(idx);
    engine.remove(obj.node);

    if (obj.isBomb) {
      bombsHit++;
      _points = max(0, _points - config.bombPenalty);
      _flashBomb();
      _emit(ArGameEvent(
        ArGameEventType.bomb,
        value: config.bombPenalty,
        modelRef: obj.modelRef,
      ));
    } else {
      hits++;
      if (config.scoreByDistance) _points += obj.value;
      _emit(ArGameEvent(
        ArGameEventType.pop,
        value: config.scoreByDistance ? obj.value : config.pointsPerHit,
        modelRef: obj.modelRef,
      ));
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
    if (!obj.isBomb) {
      _emit(ArGameEvent(ArGameEventType.escape, modelRef: obj.modelRef));
    }
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
    _preRollTimer?.cancel();
    _planeSub?.cancel();
    finalScore = config.scoreByDistance
        ? _points
        : config.computeScore(hits: hits, secondsRemaining: _clampedSeconds);
    _emit(const ArGameEvent(ArGameEventType.timeUp));
    _safeNotify();
  }

  ArVector3 _randomPosition() {
    // Spread objects across a ~70° arc IN FRONT of the player. The nearest is
    // 1.5 m (~5 ft) away so a balloon never appears right on top of you, out to
    // 3.6 m so far ones genuinely look smaller (real AR perspective) and — when
    // [config.scoreByDistance] — are worth more. The wider distance band also
    // separates balloons in depth so they don't stack on the same spot.
    final angle = (_random.nextDouble() * 2 - 1) * 0.62; // ±~35°
    final dist = 1.5 + _random.nextDouble() * 2.1; // 1.5–3.6 m (≈5–12 ft)
    final x = sin(angle) * dist;
    final z = -cos(angle) * dist; // forward is -z
    final y = -0.3 + _random.nextDouble() * 1.0; // ~knee to above eye level
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

  void _emit(ArGameEvent event) {
    if (!_disposed && !_events.isClosed) _events.add(event);
  }

  @override
  void dispose() {
    _disposed = true;
    _countdown?.cancel();
    _animTimer?.cancel();
    _fallbackTimer?.cancel();
    _flashTimer?.cancel();
    _preRollTimer?.cancel();
    _tapSub?.cancel();
    _planeSub?.cancel();
    _events.close();
    engine.dispose();
    super.dispose();
  }
}
