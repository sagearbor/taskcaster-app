import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/services/ar/ar_engine.dart';
import '../../../../core/services/ar/ar_games.dart';
import '../../../../core/services/ar/ar_minigame_controller.dart';
import '../../../../core/services/sfx/game_sfx.dart';
import '../../../../core/widgets/ar_fx.dart';

/// Hosts a live AR mini-game: the platform AR camera view + a score/timer HUD,
/// driven entirely by [ArMinigameController] over the [ArEngine] abstraction.
///
/// The feel layer is all screen-space (the native AR scene can't host
/// particles): pop bursts + floating "+N" at the tap point, bomb shake/boom,
/// a 3-2-1-GO pre-roll, escape toasts, timer urgency, and a celebratory
/// results card whose score counts up under confetti.
///
/// Scores can never be lost: the round result is submitted on "Continue", by a
/// failsafe timer a few seconds after time-up, and in [deactivate] if the
/// player navigates away first — all guarded by the same idempotent flag.
///
/// DEVICE-ONLY: the actual camera + 3D rendering needs a physical ARCore/ARKit
/// device. The widget builds and the HUD/score flow is testable, but the AR
/// surface itself cannot be verified off-device.
class ArMinigameView extends StatefulWidget {
  final ArGameConfig config;
  final void Function(int score, int rawResult) onFinished;
  final VoidCallback onSkip;

  const ArMinigameView({
    super.key,
    required this.config,
    required this.onFinished,
    required this.onSkip,
  });

  @override
  State<ArMinigameView> createState() => _ArMinigameViewState();
}

class _FxEntry {
  final int id;
  final Offset center;
  final Color color;
  final String? label;
  final bool isBomb;

  const _FxEntry({
    required this.id,
    required this.center,
    required this.color,
    this.label,
    this.isBomb = false,
  });
}

class _ArMinigameViewState extends State<ArMinigameView>
    with WidgetsBindingObserver {
  late final ArEngine _engine;
  late final ArMinigameController _controller;
  late final GameSfx _sfx;
  StreamSubscription<ArGameEvent>? _eventSub;

  bool _submitted = false;
  Timer? _submitFailsafe;

  // If we're still scanning (nothing placed) after this long, it's probably too
  // dark or there's no good surface — escalate the on-screen hint.
  Timer? _scanTimer;
  bool _scanTimedOut = false;

  // The native tap callback only carries the node id, so we remember the last
  // touch point ourselves and place the burst there.
  Offset? _lastTouch;
  DateTime _lastTouchAt = DateTime.fromMillisecondsSinceEpoch(0);

  final List<_FxEntry> _bursts = [];
  int _fxSeq = 0;
  String? _toast;
  int _toastSeq = 0;
  int _shakeTrigger = 0;
  bool _showGo = false;
  Timer? _goTimer;
  int _lastTickedSecond = -1;
  bool _pausedForSheet = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _engine = sl<ArEngine>();
    _sfx = sl<GameSfx>();
    _controller = ArMinigameController(engine: _engine, config: widget.config);
    _eventSub = _controller.events.listen(_onGameEvent);
    _controller.addListener(_onControllerChanged);
    // Kick off the session; spawning waits on plane detection internally.
    _controller.start();
    _scanTimer = Timer(const Duration(seconds: 8), () {
      if (mounted && !_controller.objectsSpawned) {
        setState(() => _scanTimedOut = true);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scanTimer?.cancel();
    _goTimer?.cancel();
    _submitFailsafe?.cancel();
    _eventSub?.cancel();
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  void deactivate() {
    // Leaving the screen (back gesture, navigation) must not lose a finished
    // round's score.
    if (_controller.finished) _submit();
    super.deactivate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Backgrounding must not silently burn the round timer.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _controller.pause();
    } else if (state == AppLifecycleState.resumed && !_pausedForSheet) {
      _controller.resume();
    }
  }

  void _submit() {
    if (_submitted) return;
    _submitted = true;
    _submitFailsafe?.cancel();
    widget.onFinished(_controller.finalScore, _controller.hits);
  }

  // ---- Feel layer -----------------------------------------------------------

  void _onGameEvent(ArGameEvent event) {
    if (!mounted) return;
    switch (event.type) {
      case ArGameEventType.surfaceFound:
        HapticFeedback.lightImpact();
        break;
      case ArGameEventType.go:
        _sfx.go();
        HapticFeedback.mediumImpact();
        setState(() => _showGo = true);
        _goTimer?.cancel();
        _goTimer = Timer(const Duration(milliseconds: 750), () {
          if (mounted) setState(() => _showGo = false);
        });
        break;
      case ArGameEventType.pop:
        // Far (high-value) balloons pop slightly higher-pitched and hit harder.
        _sfx.pop(pitch: 0.95 + 0.05 * event.value);
        event.value >= 4
            ? HapticFeedback.mediumImpact()
            : HapticFeedback.lightImpact();
        final hot = _controller.comboActive;
        _addBurst(
          color: arFxColorFor(event.modelRef),
          label: hot
              ? '+${event.value} 🔥'
              : (event.value >= 4 ? '+${event.value} ✨' : '+${event.value}'),
        );
        break;
      case ArGameEventType.bomb:
        _sfx.boom();
        HapticFeedback.heavyImpact();
        _addBurst(
          color: arFxColorFor(event.modelRef),
          label: '−${event.value}',
          isBomb: true,
        );
        setState(() => _shakeTrigger++);
        break;
      case ArGameEventType.escape:
        _sfx.whoosh();
        setState(() {
          _toast = '🎈 One floated away!';
          _toastSeq++;
        });
        break;
      case ArGameEventType.rivalPop:
        // Solo games have no rivals — only the shared Blitz race emits this.
        break;
      case ArGameEventType.timeUp:
        _sfx.fanfare();
        HapticFeedback.mediumImpact();
        // Celebrate, then submit even if the player never taps Continue.
        _submitFailsafe = Timer(const Duration(seconds: 6), _submit);
        break;
    }
  }

  void _onControllerChanged() {
    // Tick sound + haptic for the last 5 seconds of the round.
    final s = _controller.secondsRemaining;
    if (!_controller.finished &&
        !_controller.inPreRoll &&
        _controller.objectsSpawned &&
        s != _lastTickedSecond &&
        s <= 5 &&
        s > 0) {
      _lastTickedSecond = s;
      _sfx.tick();
      HapticFeedback.selectionClick();
    }
  }

  void _addBurst({required Color color, String? label, bool isBomb = false}) {
    final recent =
        DateTime.now().difference(_lastTouchAt) < const Duration(seconds: 1);
    final size = MediaQuery.of(context).size;
    final center = (recent && _lastTouch != null)
        ? _lastTouch!
        : Offset(size.width / 2, size.height / 2);
    setState(() {
      _bursts.add(_FxEntry(
        id: _fxSeq++,
        center: center,
        color: color,
        label: label,
        isBomb: isBomb,
      ));
    });
  }

  void _openPauseSheet() {
    _pausedForSheet = true;
    _controller.pause();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.play_arrow, color: Colors.white),
              title: const Text('Resume',
                  style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.of(sheetContext).pop(),
            ),
            ListTile(
              leading: const Icon(Icons.skip_next, color: Colors.white70),
              title: const Text('Skip this task',
                  style: TextStyle(color: Colors.white70)),
              onTap: () {
                Navigator.of(sheetContext).pop();
                widget.onSkip();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ).whenComplete(() {
      _pausedForSheet = false;
      if (mounted) _controller.resume();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // The platform AR camera view fills the screen. The Listener records
        // where the player touched so pop FX can appear at the right spot (the
        // native tap event that follows only tells us WHICH node was hit).
        Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (e) {
            _lastTouch = e.localPosition;
            _lastTouchAt = DateTime.now();
          },
          child: _engine.buildView(),
        ),

        // HUD + overlays react to controller changes.
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            if (_controller.error != null && !_controller.hasLiveObjects) {
              return _ErrorOverlay(
                message: _controller.error!,
                onSkip: widget.onSkip,
              );
            }
            if (_controller.finished) {
              return _ResultsOverlay(
                config: widget.config,
                hits: _controller.hits,
                score: _controller.finalScore,
                onSubmit: _submit,
              );
            }
            return _Hud(
              config: widget.config,
              controller: _controller,
              onPause: _openPauseSheet,
              scanTimedOut: _scanTimedOut,
              shakeTrigger: _shakeTrigger,
            );
          },
        ),

        // Pop/explosion bursts at the tap point.
        for (final b in _bursts)
          PopBurst(
            key: ValueKey('burst-${b.id}'),
            center: b.center,
            color: b.color,
            label: b.label,
            isBomb: b.isBomb,
            onDone: () => setState(
                () => _bursts.removeWhere((entry) => entry.id == b.id)),
          ),

        // Escape toast.
        if (_toast != null)
          ArToast(
            key: ValueKey('toast-$_toastSeq'),
            text: _toast!,
            onDone: () => setState(() => _toast = null),
          ),

        // 3-2-1-GO pre-roll.
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            if (_controller.inPreRoll) {
              return GoCountdownOverlay(digit: _controller.goCountdown);
            }
            if (_showGo) {
              return const GoCountdownOverlay(digit: 0, showGo: true);
            }
            return const SizedBox.shrink();
          },
        ),

        // Brief red "oops" flash when a bomb is tapped.
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => IgnorePointer(
            child: AnimatedOpacity(
              opacity: _controller.bombFlash ? 1 : 0,
              duration: const Duration(milliseconds: 120),
              child: Container(color: Colors.red.withOpacity(0.35)),
            ),
          ),
        ),
      ],
    );
  }
}

class _Hud extends StatelessWidget {
  final ArGameConfig config;
  final ArMinigameController controller;
  final VoidCallback onPause;
  final bool scanTimedOut;
  final int shakeTrigger;

  const _Hud({
    required this.config,
    required this.controller,
    required this.onPause,
    this.scanTimedOut = false,
    this.shakeTrigger = 0,
  });

  @override
  Widget build(BuildContext context) {
    final scanning = !controller.objectsSpawned;
    final s = controller.secondsRemaining;
    final timerColor = s <= 5
        ? Colors.red[700]
        : (s <= 10 ? Colors.amber[800] : null);
    // The bomb legend shows through the pre-roll and the opening seconds, then
    // gets out of the way.
    final elapsed = config.duration.inSeconds - s;
    final showLegend = config.bombChance > 0 &&
        !scanning &&
        (controller.inPreRoll || elapsed < 5);

    return SafeArea(
      child: Stack(
        children: [
          // Top bar: timer + score + pause. Rattles when a bomb goes off.
          Positioned(
            top: 8,
            left: 12,
            right: 12,
            child: ShakeOnTrigger(
              trigger: shakeTrigger,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ArHudPill(
                        icon: Icons.timer,
                        label: '${s}s',
                        color: timerColor,
                        punchKey: s <= 5 && !controller.finished ? s : null,
                      ),
                      Row(
                        children: [
                          if (controller.comboActive) ...[
                            const ArHudPill(
                              icon: Icons.local_fire_department,
                              label: '×2',
                              color: Colors.deepOrange,
                            ),
                            const SizedBox(width: 8),
                          ],
                          ArHudPill(
                            icon: config.speedBonus
                                ? Icons.diamond
                                : Icons.celebration,
                            label: config.respawnOnHit
                                ? 'Score ${controller.liveScore}'
                                : '${controller.hits}/${config.objectCount}',
                            punchKey: controller.liveScore,
                          ),
                          const SizedBox(width: 8),
                          _RoundIconButton(
                            icon: Icons.pause,
                            onTap: onPause,
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (showLegend)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.55),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            '🎈 Pop! Far = more points · 💣 Avoid '
                            '(−${config.bombPenalty})',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          if (scanning) _ScanCard(timedOut: scanTimedOut),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _RoundIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.6),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

/// The "point your phone around" card, with a gently sweeping phone icon so
/// the wait reads as "the app is looking" rather than a frozen dialog.
class _ScanCard extends StatefulWidget {
  final bool timedOut;

  const _ScanCard({required this.timedOut});

  @override
  State<_ScanCard> createState() => _ScanCardState();
}

class _ScanCardState extends State<_ScanCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 32),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _c,
              builder: (context, child) => Transform.rotate(
                angle: (widget.timedOut ? 0.0 : (_c.value - 0.5) * 0.5),
                child: child,
              ),
              child: Icon(
                widget.timedOut
                    ? Icons.lightbulb_outline
                    : Icons.phonelink_ring,
                color: Colors.white,
                size: 30,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              widget.timedOut
                  ? "Still can't find a surface — it may be too dark.\n"
                      'AR needs light: move somewhere brighter and point '
                      'at a textured floor or table.'
                  : 'Point at a well-lit floor or table and move your '
                      'phone slowly to scan.\nAR needs light to find a '
                      'surface.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, height: 1.3),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultsOverlay extends StatelessWidget {
  final ArGameConfig config;
  final int hits;
  final int score;
  final VoidCallback onSubmit;

  const _ResultsOverlay({
    required this.config,
    required this.hits,
    required this.score,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = config.speedBonus ? 'gems found' : 'balloons popped';
    return Container(
      color: Colors.black.withOpacity(0.7),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ConfettiBurst(),
          Center(
            child: Card(
              margin: const EdgeInsets.all(32),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.3, end: 1.0),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.elasticOut,
                      builder: (context, v, child) =>
                          Transform.scale(scale: v, child: child),
                      child: Icon(
                        config.speedBonus ? Icons.diamond : Icons.emoji_events,
                        size: 56,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text("TIME'S UP!",
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    Text('$hits $unit', style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 4),
                    // Score counts up from 0 — the little drumroll matters.
                    TweenAnimationBuilder<int>(
                      tween: IntTween(begin: 0, end: score),
                      duration: const Duration(milliseconds: 1100),
                      curve: Curves.easeOutQuart,
                      builder: (context, v, _) => Text(
                        'Score: $v',
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: onSubmit,
                      icon: const Icon(Icons.leaderboard),
                      label: const Text('Continue'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorOverlay extends StatelessWidget {
  final String message;
  final VoidCallback onSkip;

  const _ErrorOverlay({required this.message, required this.onSkip});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(0.7),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.white),
              const SizedBox(height: 12),
              Text(
                "Couldn't start the AR game.\n$message",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 20),
              FilledButton(onPressed: onSkip, child: const Text('Skip task')),
            ],
          ),
        ),
      ),
    );
  }
}
