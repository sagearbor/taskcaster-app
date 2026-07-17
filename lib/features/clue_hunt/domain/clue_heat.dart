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
