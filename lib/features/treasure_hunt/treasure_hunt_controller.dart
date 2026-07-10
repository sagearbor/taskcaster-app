import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../core/services/ar/ar_engine.dart';

/// The life-cycle of a pass-the-phone Treasure Hunt (internally "Geiger Hunt").
///
/// hiding → handoff → countdown → hunting → (trackingLost ⇄ hunting) →
/// betweenTurns → (handoff → … next seeker …) → results
enum TreasureHuntPhase {
  /// The hider walks the room storing 1–5 invisible treasure spots.
  hiding,

  /// Full-screen "hand the phone to the seeker" card; spots stay hidden and
  /// tracking survives because the camera keeps pointing at the room.
  handoff,

  /// The 3-2-1 pre-roll before a hunt turn starts.
  countdown,

  /// The live 90-second hunt: hot/cold geiger + reveal-on-approach.
  hunting,

  /// Camera pose is unavailable/stale — timer + geiger are frozen and a coaching
  /// overlay is shown until the pose returns.
  trackingLost,

  /// A turn just ended; leaderboard shown with "Next seeker" / "Finish".
  betweenTurns,

  /// The game is over — final leaderboard.
  results,
}

/// How hot the geiger is, used to pick the haptic strength (light→medium→heavy).
enum GeigerHeat { silent, cold, warm, hot }

/// Discrete moments the view turns into sound / haptics / FX.
enum TreasureHuntEventType {
  /// A treasure spot was stored during the hide phase.
  hideStored,

  /// A 3-2-1 countdown digit changed.
  countdownTick,

  /// The countdown finished — the hunt turn is live.
  go,

  /// One geiger tick fired ([TreasureHuntEvent.heat] drives the haptic).
  geigerTick,

  /// The seeker got within reveal range — the gem spawned in front of them.
  reveal,

  /// The revealed gem was collected (tapped).
  collect,

  /// Every treasure was found this turn (win + time bonus).
  allFound,

  /// The 90-second clock ran out with treasures still hidden.
  timeUp,

  /// Camera pose was lost — hunt paused.
  trackingLost,

  /// Camera pose returned — hunt resumed.
  trackingRegained,
}

class TreasureHuntEvent {
  final TreasureHuntEventType type;
  final GeigerHeat heat;
  const TreasureHuntEvent(this.type, {this.heat = GeigerHeat.silent});
}

/// One seeker's result, shown on the leaderboard.
class TreasureHuntTurnResult {
  final String seekerName;
  final int treasuresFound;
  final int totalTreasures;

  /// Seconds spent hunting (lower is better; finishing early beats the clock).
  final int timeUsedSeconds;

  /// Whether the seeker found every treasure before time ran out.
  final bool allFound;

  const TreasureHuntTurnResult({
    required this.seekerName,
    required this.treasuresFound,
    required this.totalTreasures,
    required this.timeUsedSeconds,
    required this.allFound,
  });
}

class _Treasure {
  final ArVector3 spot;
  bool found = false;
  _Treasure(this.spot);
}

/// Pure-Dart controller for Treasure Hunt: no Flutter services, no AR plugin —
/// it talks ONLY to the plugin-agnostic [ArEngine], so every rule (hide storage,
/// the distance→tick mapping, reveal-at-1m, retargeting, tracking-loss pause, the
/// turn/leaderboard flow) is unit-testable with a fake engine + `fake_async`.
///
/// It is the style cousin of ArMinigameController but a different shape: there is
/// no shared-race sync, objects are invisible until revealed, and the loop is
/// driven by polling the camera POSE rather than by tapping spawned nodes.
class TreasureHuntController extends ChangeNotifier {
  final ArEngine engine;

  /// The gem model spawned at the reveal moment.
  final String gemModelRef;

  /// Hunt length per turn.
  final Duration huntDuration;

  /// Max treasures a hider may place.
  final int maxTreasures;

  TreasureHuntController({
    required this.engine,
    this.gemModelRef = 'assets/ar/gem.glb',
    this.huntDuration = const Duration(seconds: 90),
    this.maxTreasures = 5,
    String firstSeekerName = 'Seeker 1',
  }) : _seekerName = firstSeekerName;

  // ---- Tuning (all pure) ----------------------------------------------------

  /// Beyond this distance the geiger is silent.
  static const double silenceRange = 6.0;

  /// At/under this distance the geiger is frantic.
  static const double franticRange = 1.0;

  /// Coming within this distance of an unfound treasure reveals it.
  static const double revealDistance = 1.0;

  /// Fastest tick interval (~8 ticks/sec) at [franticRange].
  static const int franticIntervalMs = 125;

  /// Slowest audible tick interval, at [silenceRange].
  static const int slowestIntervalMs = 900;

  /// How often the camera pose is polled.
  static const Duration pollInterval = Duration(milliseconds: 150);

  /// While silent (or on a reveal), re-check the geiger this often.
  static const Duration _silentRecheck = Duration(milliseconds: 200);

  /// Cadence of the 3-2-1 countdown digits.
  static const Duration countdownTickInterval = Duration(milliseconds: 700);

  /// Euclidean distance (metres) between two AR world points.
  static double distanceBetween(ArVector3 a, ArVector3 b) {
    final dx = a.x - b.x, dy = a.y - b.y, dz = a.z - b.z;
    return sqrt(dx * dx + dy * dy + dz * dz);
  }

  /// PURE distance→tick-interval mapping (the geiger's core). Returns null when
  /// silent (no target, or farther than [silenceRange]); otherwise a tick
  /// interval in ms that shortens smoothly to [franticIntervalMs] at 1 m.
  static int? tickIntervalMsForDistance(double? distance) {
    if (distance == null || distance > silenceRange) return null;
    if (distance <= franticRange) return franticIntervalMs;
    final t = (distance - franticRange) / (silenceRange - franticRange);
    return (franticIntervalMs + t * (slowestIntervalMs - franticIntervalMs))
        .round();
  }

  /// PURE distance→haptic-heat mapping.
  static GeigerHeat heatForDistance(double? distance) {
    if (distance == null || distance > silenceRange) return GeigerHeat.silent;
    if (distance <= 1.5) return GeigerHeat.hot;
    if (distance <= 3.5) return GeigerHeat.warm;
    return GeigerHeat.cold;
  }

  // ---- Observable state -----------------------------------------------------

  TreasureHuntPhase phase = TreasureHuntPhase.hiding;

  final List<_Treasure> _treasures = [];
  int get treasureCount => _treasures.length;
  bool get canHideMore => _treasures.length < maxTreasures;

  int secondsRemaining = 0;
  int countdownValue = 0; // 3,2,1 during the pre-roll; 0 otherwise
  int foundThisTurn = 0;
  int get totalTreasures => _treasures.length;

  /// Live geiger read-outs (also power the debug HUD).
  double? distanceToNearest;
  int? tickIntervalMs;
  GeigerHeat heat = GeigerHeat.silent;
  bool get trackingLost => phase == TreasureHuntPhase.trackingLost;

  /// True while a gem is revealed and awaiting its collecting tap.
  bool revealPending = false;
  int? revealedIndex;
  ArNode? _revealedNode;

  String _seekerName;
  String get currentSeekerName => _seekerName;

  final List<TreasureHuntTurnResult> _results = [];

  /// Leaderboard: most treasures first, then fastest time.
  List<TreasureHuntTurnResult> get leaderboard {
    final sorted = List<TreasureHuntTurnResult>.of(_results);
    sorted.sort((a, b) {
      if (a.treasuresFound != b.treasuresFound) {
        return b.treasuresFound.compareTo(a.treasuresFound);
      }
      return a.timeUsedSeconds.compareTo(b.timeUsedSeconds);
    });
    return sorted;
  }

  Stream<TreasureHuntEvent> get events => _events.stream;
  final StreamController<TreasureHuntEvent> _events =
      StreamController<TreasureHuntEvent>.broadcast();

  // ---- Internals ------------------------------------------------------------

  StreamSubscription<ArTap>? _tapSub;
  Timer? _countdownTimer;
  Timer? _huntTimer;
  Timer? _pollTimer;
  Timer? _tickTimer;
  bool _polling = false;
  bool _started = false;
  bool _disposed = false;

  // ---- Lifecycle ------------------------------------------------------------

  /// Bring up the AR session and begin the hide phase. Safe to call once.
  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    try {
      await engine.initSession();
    } catch (_) {
      // Capability is gated upstream; a bring-up failure just leaves us in the
      // hide phase with no pose (Hide will report tracking-lost).
    }
    if (_disposed) return;
    _tapSub = engine.taps.listen(_onTap);
    _safeNotify();
  }

  // ---- Hide phase -----------------------------------------------------------

  /// Store the current camera position as a hidden treasure. Returns false if the
  /// cap is reached or tracking is unavailable (nothing stored).
  Future<bool> hideHere() async {
    if (_disposed || phase != TreasureHuntPhase.hiding || !canHideMore) {
      return false;
    }
    final pos = await engine.cameraPosition();
    if (pos == null) return false; // tracking lost — can't store a real spot
    _treasures.add(_Treasure(pos));
    _emit(const TreasureHuntEvent(TreasureHuntEventType.hideStored));
    _safeNotify();
    return true;
  }

  /// Finish hiding and move to the hand-off card. No-op unless ≥1 spot exists.
  void doneHiding() {
    if (phase != TreasureHuntPhase.hiding || _treasures.isEmpty) return;
    phase = TreasureHuntPhase.handoff;
    _safeNotify();
  }

  // ---- Countdown → hunt -----------------------------------------------------

  /// Tap-to-start from the hand-off card: run the 3-2-1, then start the hunt.
  void beginCountdown() {
    if (phase != TreasureHuntPhase.handoff &&
        phase != TreasureHuntPhase.betweenTurns) {
      return;
    }
    phase = TreasureHuntPhase.countdown;
    countdownValue = 3;
    _emit(const TreasureHuntEvent(TreasureHuntEventType.countdownTick));
    _safeNotify();
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(countdownTickInterval, (t) {
      countdownValue--;
      if (countdownValue <= 0) {
        countdownValue = 0;
        t.cancel();
        _beginHunt();
      } else {
        _emit(const TreasureHuntEvent(TreasureHuntEventType.countdownTick));
        _safeNotify();
      }
    });
  }

  void _beginHunt() {
    // Same layout, fresh run: reset every found flag and the clock.
    for (final tr in _treasures) {
      tr.found = false;
    }
    foundThisTurn = 0;
    revealPending = false;
    revealedIndex = null;
    _revealedNode = null;
    distanceToNearest = null;
    tickIntervalMs = null;
    heat = GeigerHeat.silent;
    secondsRemaining = huntDuration.inSeconds;
    phase = TreasureHuntPhase.hunting;
    _emit(const TreasureHuntEvent(TreasureHuntEventType.go));
    _startHuntTimer();
    _startPolling();
    _scheduleGeigerTick();
    _safeNotify();
  }

  void _startHuntTimer() {
    _huntTimer?.cancel();
    _huntTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (phase != TreasureHuntPhase.hunting) return;
      secondsRemaining--;
      if (secondsRemaining <= 0) {
        secondsRemaining = 0;
        _endTurn(allFound: false);
      } else {
        _safeNotify();
      }
    });
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(pollInterval, (_) => _poll());
  }

  // ---- Geiger poll ----------------------------------------------------------

  Future<void> _poll() async {
    if (_disposed || _polling) return;
    if (phase != TreasureHuntPhase.hunting &&
        phase != TreasureHuntPhase.trackingLost) {
      return;
    }
    _polling = true;
    try {
      final pos = await engine.cameraPosition();
      if (_disposed) return;

      if (pos == null) {
        _onTrackingLost();
        return;
      }
      if (phase == TreasureHuntPhase.trackingLost) {
        _onTrackingRegained();
      }
      if (phase != TreasureHuntPhase.hunting) return;

      // Nearest UNFOUND treasure drives the geiger.
      double? nearest;
      int? nearestIdx;
      for (var i = 0; i < _treasures.length; i++) {
        if (_treasures[i].found) continue;
        final d = distanceBetween(pos, _treasures[i].spot);
        if (nearest == null || d < nearest) {
          nearest = d;
          nearestIdx = i;
        }
      }
      distanceToNearest = nearest;
      // While a gem is revealed we hush the geiger until it's collected.
      if (revealPending) {
        tickIntervalMs = null;
        heat = GeigerHeat.silent;
      } else {
        tickIntervalMs = tickIntervalMsForDistance(nearest);
        heat = heatForDistance(nearest);
        if (nearest != null &&
            nearestIdx != null &&
            nearest <= revealDistance) {
          await _reveal(nearestIdx);
        }
      }
      _safeNotify();
    } finally {
      _polling = false;
    }
  }

  void _onTrackingLost() {
    if (phase == TreasureHuntPhase.trackingLost) return;
    phase = TreasureHuntPhase.trackingLost;
    _huntTimer?.cancel(); // freeze the clock
    _huntTimer = null;
    _tickTimer?.cancel(); // freeze the geiger
    _tickTimer = null;
    tickIntervalMs = null;
    heat = GeigerHeat.silent;
    _emit(const TreasureHuntEvent(TreasureHuntEventType.trackingLost));
    _safeNotify();
  }

  void _onTrackingRegained() {
    phase = TreasureHuntPhase.hunting;
    _startHuntTimer(); // resume the clock
    _scheduleGeigerTick(); // resume the geiger
    _emit(const TreasureHuntEvent(TreasureHuntEventType.trackingRegained));
    _safeNotify();
  }

  // ---- Geiger ticking -------------------------------------------------------

  void _scheduleGeigerTick() {
    _tickTimer?.cancel();
    if (phase != TreasureHuntPhase.hunting) return;
    final interval = revealPending ? null : tickIntervalMs;
    final delay = interval ?? _silentRecheck.inMilliseconds;
    _tickTimer = Timer(Duration(milliseconds: delay), _fireGeigerTick);
  }

  void _fireGeigerTick() {
    if (_disposed || phase != TreasureHuntPhase.hunting) return;
    if (!revealPending && tickIntervalMs != null) {
      _emit(TreasureHuntEvent(TreasureHuntEventType.geigerTick, heat: heat));
    }
    _scheduleGeigerTick();
  }

  // ---- Reveal / collect -----------------------------------------------------

  Future<void> _reveal(int index) async {
    if (revealPending) return;
    revealPending = true;
    revealedIndex = index;
    tickIntervalMs = null;
    heat = GeigerHeat.silent;
    _emit(const TreasureHuntEvent(TreasureHuntEventType.reveal));
    _safeNotify();
    // Camera-relative spawn so the gem is always in view despite AR drift. A
    // null node (no pose / placement failed) is fine — the banner tap still
    // collects it.
    _revealedNode = await engine.spawnInFrontOfCamera(modelRef: gemModelRef);
  }

  void _onTap(ArTap tap) {
    if (!revealPending) return;
    if (_revealedNode != null && tap.nodeId == _revealedNode!.id) {
      collectRevealed();
    }
  }

  /// Collect the currently-revealed gem (tapping the gem OR the FOUND banner).
  void collectRevealed() {
    if (_disposed || !revealPending) return;
    final idx = revealedIndex;
    revealPending = false;
    revealedIndex = null;
    final node = _revealedNode;
    _revealedNode = null;
    if (node != null) engine.remove(node);

    if (idx != null && idx >= 0 && idx < _treasures.length) {
      _treasures[idx].found = true;
      foundThisTurn++;
    }
    _emit(const TreasureHuntEvent(TreasureHuntEventType.collect));
    _safeNotify();

    if (_treasures.every((t) => t.found)) {
      _endTurn(allFound: true);
    } else {
      _scheduleGeigerTick(); // retarget the next nearest
    }
  }

  // ---- Turn / game end ------------------------------------------------------

  void _endTurn({required bool allFound}) {
    _huntTimer?.cancel();
    _huntTimer = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    _tickTimer?.cancel();
    _tickTimer = null;

    final timeUsed = huntDuration.inSeconds - secondsRemaining;
    _results.add(TreasureHuntTurnResult(
      seekerName: _seekerName,
      treasuresFound: foundThisTurn,
      totalTreasures: _treasures.length,
      timeUsedSeconds: allFound ? timeUsed : huntDuration.inSeconds,
      allFound: allFound,
    ));
    _emit(TreasureHuntEvent(
      allFound ? TreasureHuntEventType.allFound : TreasureHuntEventType.timeUp,
    ));
    phase = TreasureHuntPhase.betweenTurns;
    _safeNotify();
  }

  /// Hand off to the next seeker, replaying the SAME hidden layout. Returns to a
  /// hand-off card; [beginCountdown] then starts their own timed run.
  void nextSeeker(String name) {
    if (phase != TreasureHuntPhase.betweenTurns) return;
    _seekerName = name;
    phase = TreasureHuntPhase.handoff;
    _safeNotify();
  }

  /// End the game and show the final leaderboard.
  void finishGame() {
    if (phase != TreasureHuntPhase.betweenTurns) return;
    phase = TreasureHuntPhase.results;
    _safeNotify();
  }

  // ---- Plumbing -------------------------------------------------------------

  void _emit(TreasureHuntEvent event) {
    if (!_disposed && !_events.isClosed) _events.add(event);
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _countdownTimer?.cancel();
    _huntTimer?.cancel();
    _pollTimer?.cancel();
    _tickTimer?.cancel();
    _tapSub?.cancel();
    _events.close();
    engine.dispose();
    super.dispose();
  }
}
