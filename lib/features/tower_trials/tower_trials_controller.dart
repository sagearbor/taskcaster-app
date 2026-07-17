import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../core/services/ar/ar_engine.dart';

/// The life-cycle of a pass-the-phone Tower Trials match.
///
/// setup → (startGame) → handoff → aiming → [drop … drop] → collapsing →
/// (next round: handoff …) → results
enum TowerTrialsPhase {
  /// Start card: enter 2+ player names.
  setup,

  /// Full-screen "hand the phone to X" card between turns and rounds.
  handoff,

  /// The current builder aims the ghost preview block and drops.
  aiming,

  /// The tower is tumbling — the FX beat between a fatal drop and the next
  /// round (or the results).
  collapsing,

  /// Game over — one builder left standing.
  results,
}

/// Discrete moments the view turns into sound / haptics / FX.
enum TowerTrialsEventType {
  /// A fresh tower base just went up (game start + every new round).
  roundStart,

  /// The handoff card was dismissed — this player's turn is live.
  turnStart,

  /// A block landed (non-perfect). [TowerTrialsEvent.offset] is how far off
  /// centre it was, in metres.
  place,

  /// A near-centre drop: instability rebate + "PERFECT!" flash.
  perfect,

  /// Instability just crossed [TowerTrialsController.warnThreshold] — the
  /// meter goes red and the room holds its breath.
  warning,

  /// The tower collapsed; [TowerTrialsEvent.playerName] is who toppled it
  /// (and is now out).
  collapse,

  /// Last builder standing — [TowerTrialsEvent.playerName] wins.
  winner,
}

class TowerTrialsEvent {
  final TowerTrialsEventType type;

  /// Placement offset in metres (place/perfect events).
  final double offset;

  /// The player involved (turnStart/place/perfect/collapse/winner).
  final String? playerName;

  const TowerTrialsEvent(this.type, {this.offset = 0, this.playerName});
}

/// One contestant. [blockModelRef] is the colored cube dropped on their turns.
class TowerPlayer {
  final String name;
  final String blockModelRef;
  bool eliminated = false;

  TowerPlayer(this.name, this.blockModelRef);
}

/// One placed block. (x, z) is its LOGICAL resting centre in AR world space —
/// the wobble/lean/tumble animations are render-time offsets on top of this,
/// never mutations of it, so the stack math stays deterministic.
class TowerBlock {
  final int level; // 0 = the base block
  final double x;
  final double z;
  final String modelRef;
  ArNode? node; // null until the async spawn lands (or if it failed)

  TowerBlock({
    required this.level,
    required this.x,
    required this.z,
    required this.modelRef,
  });
}

/// A horizontal aim offset (metres) of the camera's aim point relative to the
/// tower top — the ONE number pair the controller consumes from the AR layer.
class TowerAim {
  final double dx;
  final double dz;

  const TowerAim(this.dx, this.dz);

  double get length => sqrt(dx * dx + dz * dz);
}

/// Pure-Dart controller for Tower Trials: no Flutter services, no AR plugin —
/// it talks ONLY to the plugin-agnostic [ArEngine]. The aim offset arrives via
/// [updateAim]/[clearAim] (the screen derives it from the camera pose with the
/// pure [aimFromPose]); the controller just consumes numbers. Every rule —
/// turn order, offset → instability accumulation, the perfect rebate, the
/// collapse threshold, eliminations, last-standing winner, multi-round reset —
/// is unit-testable with a fake engine + `fake_async` (the injected zone clock
/// that drives the anim/collapse timers in tests).
///
/// There is deliberately NO physics engine: the tower's lean/wobble and the
/// collapse tumble are deterministic pure functions of cumulative offsets and
/// time ([swayOffset], [collapseOffset]) applied as render offsets via
/// `engine.move`.
class TowerTrialsController extends ChangeNotifier {
  final ArEngine engine;

  /// The anchor block spawned at every round start.
  final String baseModelRef;

  /// The translucent preview block that hovers where the next drop lands.
  final String ghostModelRef;

  /// Per-player block colors, cycled by seat order.
  final List<String> playerModels;

  /// How long the tumble FX plays before the next round / results.
  final Duration collapseDuration;

  TowerTrialsController({
    required this.engine,
    this.baseModelRef = 'assets/ar/block_base.glb',
    this.ghostModelRef = 'assets/ar/block_ghost.glb',
    this.playerModels = const [
      'assets/ar/block_red.glb',
      'assets/ar/block_blue.glb',
      'assets/ar/block_green.glb',
      'assets/ar/block_yellow.glb',
    ],
    this.collapseDuration = const Duration(milliseconds: 1400),
  });

  // ---- Tuning (all pure) ----------------------------------------------------

  /// Rendered block edge in metres. The engine normalizes every model's
  /// largest dimension to 0.25 m (scaleToUnits), so a cube renders exactly
  /// this big — stacking height and offset ratios both key off it.
  static const double blockSize = 0.25;

  /// How far in front of the camera the base block spawns (metres).
  static const double towerDistance = 1.1;

  /// How far below the camera the base block spawns (metres) — belly height,
  /// so a 5-6 block tower climbs toward eye level.
  static const double baseDrop = 0.55;

  /// Gap between the tower top and the hovering ghost preview.
  static const double hoverGap = 0.06;

  /// Aim offsets are clamped to this radius — past it the preview pins to the
  /// edge (you can't wander the ghost across the room).
  static const double maxAim = 0.35;

  /// At/under this offset a drop is PERFECT (instability rebate).
  static const double perfectThreshold = 0.03;

  /// How much instability a perfect drop refunds.
  static const double perfectRebate = 0.18;

  /// Instability added by a drop that is off by a FULL block width.
  static const double instabilityPerBlockOffset = 0.55;

  /// The tower collapses when cumulative instability reaches this.
  static const double collapseThreshold = 1.0;

  /// The "meter goes red" line.
  static const double warnThreshold = 0.7;

  /// Max sideways lean per tower level at full instability (metres).
  static const double leanPerLevel = 0.010;

  /// Max wobble sway per tower level at full instability (metres).
  static const double wobbleAmpPerLevel = 0.006;

  /// Cadence of the deterministic wobble/tumble animation.
  static const Duration animTick = Duration(milliseconds: 60);

  /// PURE: where the camera ray meets the horizontal landing plane of the next
  /// block, as an offset from the tower top. Null when the camera is not
  /// looking anywhere useful (parallel to the plane, aiming away from it, or
  /// hitting it absurdly far away) — the view shows an "aim at the tower"
  /// coach and disables the drop.
  static TowerAim? aimFromPose({
    required ArCameraPose pose,
    required double targetX,
    required double targetY,
    required double targetZ,
  }) {
    final fy = pose.forward.y;
    if (fy.abs() < 1e-4) return null; // looking dead level — no intersection
    final t = (targetY - pose.position.y) / fy;
    if (t < 0.05 || t > 8.0) return null; // behind the camera / silly far
    final dx = pose.position.x + pose.forward.x * t - targetX;
    final dz = pose.position.z + pose.forward.z * t - targetZ;
    return TowerAim(dx, dz);
  }

  /// PURE: clamp an aim offset to [maxAim] preserving direction.
  static TowerAim clampAim(double dx, double dz) {
    final len = sqrt(dx * dx + dz * dz);
    if (len <= maxAim || len == 0) return TowerAim(dx, dz);
    final s = maxAim / len;
    return TowerAim(dx * s, dz * s);
  }

  /// PURE: is this placement offset a PERFECT drop?
  static bool isPerfect(double offset) => offset <= perfectThreshold;

  /// PURE: the aim-offset → instability mapping. Perfect drops REFUND
  /// [perfectRebate] (the comeback mechanic); anything else adds instability
  /// linearly in the offset-to-block-width ratio.
  static double instabilityDelta(double offset) {
    final clamped = min(offset.abs(), maxAim);
    if (isPerfect(clamped)) return -perfectRebate;
    return (clamped / blockSize) * instabilityPerBlockOffset;
  }

  /// PURE: deterministic lean + wobble render offset for the block at [level].
  /// Lean points along the cumulative drift direction and grows with height ×
  /// instability; the wobble is a per-level phase-shifted sway. Zero for the
  /// base and for a perfectly stable tower — no physics engine anywhere.
  static ArVector3 swayOffset({
    required int level,
    required double instability,
    required double driftX,
    required double driftZ,
    required double time,
  }) {
    if (level <= 0 || instability <= 0) return const ArVector3(0, 0, 0);
    final driftLen = sqrt(driftX * driftX + driftZ * driftZ);
    final ux = driftLen < 1e-6 ? 0.0 : driftX / driftLen;
    final uz = driftLen < 1e-6 ? 0.0 : driftZ / driftLen;
    final lean = leanPerLevel * instability * level;
    final wobble = wobbleAmpPerLevel * instability * level;
    final wx = sin(time * 3.2 + level * 0.7) * wobble;
    final wz = cos(time * 2.5 + level * 0.7) * wobble;
    return ArVector3(ux * lean + wx, 0, uz * lean + wz);
  }

  /// PURE: deterministic tumble offset for the block at [level], [t] ∈ 0..1
  /// through the collapse. Blocks scatter outward (direction fanned by level so
  /// they don't fly in formation) while falling back toward base height.
  static ArVector3 collapseOffset({required int level, required double t}) {
    if (level <= 0) return const ArVector3(0, 0, 0);
    final tt = t.clamp(0.0, 1.0);
    final angle = level * 2.4; // golden-ish fan so directions spread
    final out = tt * (0.25 + 0.10 * level);
    final fall = -level * blockSize * tt * tt; // ends near the floor
    return ArVector3(cos(angle) * out, fall, sin(angle) * out);
  }

  // ---- Observable state -----------------------------------------------------

  TowerTrialsPhase phase = TowerTrialsPhase.setup;

  final List<TowerPlayer> _players = [];
  List<TowerPlayer> get players => List.unmodifiable(_players);

  final List<TowerBlock> _tower = [];
  List<TowerBlock> get tower => List.unmodifiable(_tower);

  /// Blocks stacked by players this round (the base doesn't count).
  int get blocksPlaced => _tower.isEmpty ? 0 : _tower.length - 1;

  /// The base has spawned — turns may begin.
  bool get baseReady => _tower.isNotEmpty;

  int round = 1;

  /// Cumulative wobble, 0 → [collapseThreshold].
  double instability = 0;

  /// 1.0 = rock solid, 0.0 = collapsing. Drives the stability meter.
  double get stability01 =>
      (1 - instability / collapseThreshold).clamp(0.0, 1.0);

  /// Cumulative signed drift of all placements — the lean direction.
  double driftX = 0;
  double driftZ = 0;

  /// The last drop's offset + verdict, for HUD feedback.
  double? lastOffset;
  bool lastWasPerfect = false;

  /// Who toppled the tower most recently (shown on the next handoff card).
  String? collapsedBy;

  /// Names in the order they were knocked out.
  final List<String> eliminationOrder = [];

  String? get winnerName {
    final active = _players.where((p) => !p.eliminated);
    return active.length == 1 ? active.first.name : null;
  }

  int _turnIndex = 0;
  String get currentPlayerName =>
      _players.isEmpty ? '' : _players[_turnIndex].name;

  TowerAim? _aim;
  bool get hasAim => _aim != null;
  TowerAim? get aim => _aim;

  /// Where the camera ray should be intersected: the landing centre of the
  /// NEXT block. Only meaningful while [baseReady].
  double get aimTargetX => _tower.isEmpty ? 0 : _tower.last.x;
  double get aimTargetZ => _tower.isEmpty ? 0 : _tower.last.z;
  double get aimTargetY => _baseY + _tower.length * blockSize;

  Stream<TowerTrialsEvent> get events => _events.stream;
  final StreamController<TowerTrialsEvent> _events =
      StreamController<TowerTrialsEvent>.broadcast();

  // ---- Internals ------------------------------------------------------------

  double _baseX = 0, _baseY = -baseDrop, _baseZ = -towerDistance;
  ArNode? _ghostNode;
  Timer? _animTimer;
  Timer? _collapseTimer;
  double _animClock = 0;
  double _collapseStartClock = 0;
  bool _started = false;
  bool _disposed = false;

  double _levelY(int level) => _baseY + level * blockSize;
  double get _previewY => _baseY + _tower.length * blockSize + hoverGap;

  // ---- Lifecycle ------------------------------------------------------------

  /// Bring up the AR session. Safe to call once; the AR view must be in the
  /// tree (the engine awaits its creation internally).
  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    try {
      await engine.initSession();
    } catch (_) {
      // Capability is gated upstream; a bring-up failure just means the base
      // spawns blind at the session-origin fallback position.
    }
    _safeNotify();
  }

  /// Lock in the roster (2+ names) and start round 1. Names are used as given;
  /// the view trims/validates. No-op outside [TowerTrialsPhase.setup].
  void startGame(List<String> names) {
    if (_disposed || phase != TowerTrialsPhase.setup || names.length < 2) {
      return;
    }
    _players.clear();
    for (var i = 0; i < names.length; i++) {
      _players.add(TowerPlayer(names[i], playerModels[i % playerModels.length]));
    }
    _turnIndex = 0;
    round = 1;
    phase = TowerTrialsPhase.handoff;
    _emit(const TowerTrialsEvent(TowerTrialsEventType.roundStart));
    _startAnim();
    _spawnBase();
    _safeNotify();
  }

  /// Spawn the round's anchor base in front of the camera. Camera-relative
  /// like the other games (no plane-tap dependency); falls back to the session
  /// origin when tracking hasn't locked yet.
  Future<void> _spawnBase() async {
    ArVector3? cam;
    try {
      cam = await engine.cameraPosition();
    } catch (_) {
      cam = null;
    }
    if (_disposed) return;
    _baseX = cam?.x ?? 0;
    _baseY = (cam?.y ?? 0) - baseDrop;
    _baseZ = (cam?.z ?? 0) - towerDistance;
    final base =
        TowerBlock(level: 0, x: _baseX, z: _baseZ, modelRef: baseModelRef);
    _tower.add(base);
    _safeNotify();
    base.node =
        await _trySpawn(baseModelRef, ArVector3(_baseX, _baseY, _baseZ));
    // One ghost per round, hovering where the next block would land; aiming
    // just moves it.
    _ghostNode =
        await _trySpawn(ghostModelRef, ArVector3(_baseX, _previewY, _baseZ));
  }

  Future<ArNode?> _trySpawn(String modelRef, ArVector3 position) async {
    try {
      final node = await engine.spawn(modelRef: modelRef, position: position);
      if (_disposed) {
        await engine.remove(node);
        return null;
      }
      return node;
    } catch (_) {
      // A failed placement must not kill the game — the logic runs regardless;
      // only the visual is missing.
      return null;
    }
  }

  // ---- Turns ----------------------------------------------------------------

  /// Dismiss the handoff card: the current player's turn goes live.
  void beginTurn() {
    if (_disposed || phase != TowerTrialsPhase.handoff || !baseReady) return;
    collapsedBy = null;
    _aim = null;
    phase = TowerTrialsPhase.aiming;
    _emit(TowerTrialsEvent(
      TowerTrialsEventType.turnStart,
      playerName: currentPlayerName,
    ));
    _safeNotify();
  }

  /// The screen's aim source: the camera-ray offset from the tower top, in
  /// metres. Clamped to [maxAim]; moves the ghost preview.
  void updateAim(double dx, double dz) {
    if (_disposed || phase != TowerTrialsPhase.aiming) return;
    final a = clampAim(dx, dz);
    _aim = a;
    final ghost = _ghostNode;
    if (ghost != null && _tower.isNotEmpty) {
      engine.move(
        ghost,
        ArVector3(_tower.last.x + a.dx, _previewY, _tower.last.z + a.dz),
      );
    }
    _safeNotify();
  }

  /// The camera isn't pointing at the landing plane — no drop possible.
  void clearAim() {
    if (_disposed || phase != TowerTrialsPhase.aiming || _aim == null) return;
    _aim = null;
    _safeNotify();
  }

  /// Drop the block at the current aim. Placement quality is a pure function
  /// of the aim offset at drop time; offsets accumulate into instability and
  /// near-zero offsets refund some of it.
  void dropBlock() {
    final a = _aim;
    if (_disposed || phase != TowerTrialsPhase.aiming || a == null) return;

    final offset = min(a.length, maxAim);
    final top = _tower.last;
    final block = TowerBlock(
      level: _tower.length,
      x: top.x + a.dx,
      z: top.z + a.dz,
      modelRef: _players[_turnIndex].blockModelRef,
    );
    _tower.add(block);
    _placeNode(block);
    // The ghost climbs to the new landing spot for the next turn.
    final ghost = _ghostNode;
    if (ghost != null) {
      engine.move(ghost, ArVector3(block.x, _previewY, block.z));
    }

    driftX += a.dx;
    driftZ += a.dz;
    lastOffset = offset;
    lastWasPerfect = isPerfect(offset);
    final before = instability;
    instability = max(0.0, instability + instabilityDelta(offset));
    _aim = null;

    if (lastWasPerfect) {
      _emit(TowerTrialsEvent(
        TowerTrialsEventType.perfect,
        offset: offset,
        playerName: currentPlayerName,
      ));
    } else {
      _emit(TowerTrialsEvent(
        TowerTrialsEventType.place,
        offset: offset,
        playerName: currentPlayerName,
      ));
    }

    if (instability >= collapseThreshold) {
      _beginCollapse();
    } else {
      if (before < warnThreshold && instability >= warnThreshold) {
        _emit(const TowerTrialsEvent(TowerTrialsEventType.warning));
      }
      _advanceTurn();
      phase = TowerTrialsPhase.handoff;
    }
    _safeNotify();
  }

  Future<void> _placeNode(TowerBlock block) async {
    final node = await _trySpawn(
      block.modelRef,
      ArVector3(block.x, _levelY(block.level), block.z),
    );
    // The round may have collapsed-and-reset while the spawn was in flight;
    // a node for a block that's no longer in the tower must not linger.
    if (node != null && !_tower.contains(block)) {
      engine.remove(node);
      return;
    }
    block.node = node;
  }

  void _advanceTurn() {
    for (var i = 1; i <= _players.length; i++) {
      final idx = (_turnIndex + i) % _players.length;
      if (!_players[idx].eliminated) {
        _turnIndex = idx;
        return;
      }
    }
  }

  // ---- Collapse / rounds / winner -------------------------------------------

  void _beginCollapse() {
    final loser = _players[_turnIndex];
    loser.eliminated = true;
    collapsedBy = loser.name;
    eliminationOrder.add(loser.name);
    phase = TowerTrialsPhase.collapsing;
    _collapseStartClock = _animClock;
    _emit(TowerTrialsEvent(
      TowerTrialsEventType.collapse,
      playerName: loser.name,
    ));
    // The ghost has no business hovering over rubble.
    final ghost = _ghostNode;
    _ghostNode = null;
    if (ghost != null) engine.remove(ghost);
    _collapseTimer?.cancel();
    _collapseTimer = Timer(collapseDuration, _finishCollapse);
  }

  void _finishCollapse() {
    if (_disposed) return;
    for (final block in _tower) {
      final node = block.node;
      if (node != null) engine.remove(node);
    }
    _tower.clear();
    instability = 0;
    driftX = 0;
    driftZ = 0;
    lastOffset = null;
    lastWasPerfect = false;

    final active = _players.where((p) => !p.eliminated).toList();
    if (active.length <= 1) {
      phase = TowerTrialsPhase.results;
      _stopAnim();
      _emit(TowerTrialsEvent(
        TowerTrialsEventType.winner,
        playerName: active.isEmpty ? null : active.single.name,
      ));
    } else {
      round++;
      _advanceTurn(); // the seat after the freshly-eliminated builder starts
      phase = TowerTrialsPhase.handoff;
      _emit(const TowerTrialsEvent(TowerTrialsEventType.roundStart));
      _spawnBase();
    }
    _safeNotify();
  }

  /// Final standings: winner first, then the eliminated in reverse knock-out
  /// order (last out = closest to winning).
  List<String> get finishOrder {
    final order = <String>[];
    final w = winnerName;
    if (w != null && phase == TowerTrialsPhase.results) order.add(w);
    order.addAll(eliminationOrder.reversed);
    return order;
  }

  // ---- Animation (deterministic, no physics) --------------------------------

  void _startAnim() {
    _animTimer ??= Timer.periodic(animTick, (_) => _onAnim());
  }

  void _stopAnim() {
    _animTimer?.cancel();
    _animTimer = null;
  }

  void _onAnim() {
    if (_disposed) return;
    _animClock += animTick.inMilliseconds / 1000.0;
    if (phase == TowerTrialsPhase.collapsing) {
      final t = (_animClock - _collapseStartClock) /
          (collapseDuration.inMilliseconds / 1000.0);
      for (final block in _tower) {
        final node = block.node;
        if (node == null) continue;
        final off = collapseOffset(level: block.level, t: t);
        engine.move(
          node,
          ArVector3(
            block.x + off.x,
            _levelY(block.level) + off.y,
            block.z + off.z,
          ),
        );
      }
      return;
    }
    if (phase != TowerTrialsPhase.handoff && phase != TowerTrialsPhase.aiming) {
      return;
    }
    for (final block in _tower) {
      final node = block.node;
      if (node == null || block.level == 0) continue;
      final off = swayOffset(
        level: block.level,
        instability: instability,
        driftX: driftX,
        driftZ: driftZ,
        time: _animClock,
      );
      engine.move(
        node,
        ArVector3(
          block.x + off.x,
          _levelY(block.level) + off.y,
          block.z + off.z,
        ),
      );
    }
  }

  // ---- Plumbing -------------------------------------------------------------

  void _emit(TowerTrialsEvent event) {
    if (!_disposed && !_events.isClosed) _events.add(event);
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _animTimer?.cancel();
    _collapseTimer?.cancel();
    _events.close();
    engine.dispose();
    super.dispose();
  }
}
