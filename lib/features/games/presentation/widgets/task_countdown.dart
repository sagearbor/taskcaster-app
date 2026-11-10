import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/services/sfx/game_sfx.dart';
import '../../../../core/theme/app_theme.dart';
import 'countdown_display.dart';

/// Owns the real clock for the task screen's countdown hero: a Timer ticking
/// once a second, computing elapsed time from [startedAt] and handing the
/// result to the pure [CountdownDisplay]. Kept separate from CountdownDisplay
/// so the display itself stays trivially testable with fixed values.
///
/// The juice (WP-8):
/// - a [GameSfx.tick] for each of the last [tickSeconds] seconds;
/// - at zero, a [GameSfx.fanfare] and one coral flash over the whole screen
///   (skipped when the platform asks for reduced motion).
/// Both only fire when the clock crosses into them while this widget is on
/// screen, never on a rebuild that lands mid-countdown, and the sounds stay
/// quiet while the app is in the background (the camera app is open and may
/// be recording).
class TaskCountdown extends StatefulWidget {
  final DateTime startedAt;
  final int durationSeconds;

  /// Grace period past the timer before an entry is flagged LATE. Mirrors
  /// `AutoEdit.graceSeconds` — never blocks submission, just changes the
  /// display.
  final int graceSeconds;

  /// The wall clock, injectable so tests are deterministic.
  final DateTime Function() now;

  /// Sound effects. Null means silent.
  final GameSfx? sfx;

  /// Called once, the moment the clock crosses zero while on screen (the
  /// gather stage uses it to reveal the real task).
  final VoidCallback? onExpired;

  /// How many final seconds tick audibly.
  static const int tickSeconds = 5;

  const TaskCountdown({
    super.key,
    required this.startedAt,
    required this.durationSeconds,
    this.graceSeconds = 30,
    this.now = DateTime.now,
    this.sfx,
    this.onExpired,
  });

  @override
  State<TaskCountdown> createState() => _TaskCountdownState();
}

class _TaskCountdownState extends State<TaskCountdown>
    with SingleTickerProviderStateMixin {
  Timer? _timer;
  late int _elapsed;
  late final AnimationController _flash;
  OverlayEntry? _flashEntry;

  int get _remaining => widget.durationSeconds - _elapsed;

  @override
  void initState() {
    super.initState();
    _flash = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) _removeFlash();
      });
    _elapsed = _computeElapsed();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final before = _remaining;
      setState(() => _elapsed = _computeElapsed());
      _onSecond(before, _remaining);
    });
  }

  int _computeElapsed() =>
      widget.now().difference(widget.startedAt).inSeconds;

  bool get _inForeground {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  void _onSecond(int before, int after) {
    if (after == before) return;
    final sfx = widget.sfx;
    if (before > 0 && after <= 0) {
      if (_inForeground) sfx?.fanfare();
      _showFlash();
      widget.onExpired?.call();
    } else if (after > 0 && after <= TaskCountdown.tickSeconds) {
      if (_inForeground) sfx?.tick();
    }
  }

  void _showFlash() {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
    final overlay = Overlay.maybeOf(context);
    if (overlay == null || _flashEntry != null) return;
    _flashEntry = OverlayEntry(
      builder: (_) => Positioned.fill(
        child: IgnorePointer(
          child: FadeTransition(
            opacity: Tween<double>(begin: 0.45, end: 0.0).animate(
              CurvedAnimation(parent: _flash, curve: Curves.easeOut),
            ),
            child: const ColoredBox(
              key: Key('countdown-time-up-flash'),
              color: AppTheme.coral,
            ),
          ),
        ),
      ),
    );
    overlay.insert(_flashEntry!);
    _flash.forward(from: 0);
  }

  void _removeFlash() {
    _flashEntry?.remove();
    _flashEntry = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _removeFlash();
    _flash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLate = _elapsed > widget.durationSeconds + widget.graceSeconds;
    return CountdownDisplay(
      remainingSeconds: _remaining,
      isLate: isLate,
      graceSeconds: widget.graceSeconds,
    );
  }
}
