import 'dart:async';

/// How strong the geiger feel is at a given heat, used to pick the haptic punch.
enum HeatBand { silent, cold, warm, hot }

/// PURE mappings that turn a received heat value (0.0 = ice cold, 1.0 = on top of
/// it) into the seeker's geiger feel: a tick interval and a haptic band. This is
/// the same geiger idea as the Treasure Hunt controller, but driven by the heat
/// the human hider broadcasts instead of a measured AR distance — so it lives in
/// its own pure, unit-tested helper with no device dependency.
class ClueHeat {
  /// Fastest tick interval (~9 ticks/sec) at full heat.
  static const int fastestMs = 110;

  /// Slowest audible tick interval, just above silence.
  static const int slowestMs = 900;

  /// Below this heat the meter is silent (no ticks, no haptics).
  static const double silentBelow = 0.03;

  /// Heat→tick-interval (ms). Returns null when silent; otherwise an interval
  /// that shortens smoothly from [slowestMs] toward [fastestMs] as heat rises.
  static int? tickIntervalMsForHeat(double heat) {
    if (heat < silentBelow) return null;
    final h = heat.clamp(0.0, 1.0);
    return (slowestMs - h * (slowestMs - fastestMs)).round();
  }

  /// Heat→haptic band, for scaling the buzz with the ticking.
  static HeatBand bandForHeat(double heat) {
    if (heat < silentBelow) return HeatBand.silent;
    final h = heat.clamp(0.0, 1.0);
    if (h < 0.34) return HeatBand.cold;
    if (h < 0.67) return HeatBand.warm;
    return HeatBand.hot;
  }
}

/// Drives the seeker's geiger ticking from a live heat value, self-scheduling the
/// next tick from [ClueHeat.tickIntervalMsForHeat].
///
/// The subtle bug this exists to avoid: heat arrives from the hider several times
/// a second (~every 250 ms), but the tick interval for cold/warm heat is much
/// longer (300–900 ms). A naïve "cancel the timer and reschedule a full fresh
/// interval on every heat update" therefore keeps pushing the next tick further
/// out and the geiger goes SILENT exactly while the hider is actively steering.
///
/// Instead this RE-ARMS: on a heat change it keeps the pending deadline unless
/// the new interval would fire sooner —
///   nextFire = min(currentDeadline, now + newInterval)
/// — so a steady stream of updates at constant heat still ticks at the expected
/// cadence. The timer is only cancelled when heat drops to silence. [clock] is
/// injectable (epoch ms) so the scheduling is deterministic under `fakeAsync`.
class GeigerTicker {
  GeigerTicker({required this.onTick, int Function()? clock})
      : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  /// Called once per geiger tick. The owner plays the sound/haptic here.
  final void Function() onTick;
  final int Function() _clock;

  Timer? _timer;
  int? _deadlineMs;
  double _heat = 0.0;

  double get heat => _heat;

  /// Whether a tick is currently scheduled (false when silent). For tests.
  bool get isTicking => _timer != null;

  /// Seed the initial heat and arm the first tick.
  void start(double heat) {
    _heat = heat;
    _rearm();
  }

  /// Apply a new heat value and re-arm (see class docs — this does NOT blow away
  /// a pending tick unless the new interval fires sooner or heat went silent).
  void setHeat(double heat) {
    _heat = heat;
    _rearm();
  }

  void _rearm() {
    final interval = ClueHeat.tickIntervalMsForHeat(_heat);
    if (interval == null) {
      // Silence: stop ticking entirely.
      _cancel();
      return;
    }
    final now = _clock();
    final proposed = now + interval;
    final current = _deadlineMs;
    // Keep the existing (earlier) deadline; only pull it in if the new interval
    // is shorter than what's already pending.
    final nextFire = (current != null && _timer != null && current < proposed)
        ? current
        : proposed;
    if (_timer != null && _deadlineMs == nextFire) {
      return; // Deadline unchanged — let the running timer keep counting down.
    }
    _timer?.cancel();
    _deadlineMs = nextFire;
    final delay = nextFire - now;
    _timer = Timer(Duration(milliseconds: delay < 0 ? 0 : delay), _fire);
  }

  void _fire() {
    _timer = null;
    _deadlineMs = null;
    onTick();
    _rearm(); // Schedule the next tick at the current heat.
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
    _deadlineMs = null;
  }

  void dispose() => _cancel();
}
