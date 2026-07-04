import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/services/ar/ar_engine.dart';
import '../../../../core/services/ar/ar_games.dart';
import '../../../../core/services/ar/ar_minigame_controller.dart';
import '../../../../core/services/sfx/game_sfx.dart';
import '../../../../core/widgets/ar_fx.dart';

/// The live balloon-popping surface for one phone during a Blitz round.
///
/// It reuses the EXISTING solo gameplay engine verbatim — an [ArMinigameController]
/// driving the [ArEngine] with the shared [ArGameConfig.balloonPop] — and simply
/// taps its [ChangeNotifier] to stream the player's live score out on every pop
/// ([onScoreChanged]) and to signal time-up ([onFinished]). No AR or scoring
/// logic is duplicated here.
///
/// The screen-space feel layer (pop bursts, boom + shake, 3-2-1-GO, escape
/// toasts, timer urgency) is the same shared kit the solo game uses
/// (core/widgets/ar_fx.dart), so both games feel identical to play.
///
/// DEVICE-ONLY: the camera + 3D balloon rendering need a physical ARCore phone.
/// The widget builds and the score/finish callbacks are exercised in tests via a
/// fake [ArEngine], but the AR surface itself can only be verified on a device.
class BlitzPlayView extends StatefulWidget {
  /// Called with the new score each time it changes (i.e. on every pop).
  final void Function(int score) onScoreChanged;

  /// Called once when the local round's timer runs out.
  final VoidCallback onFinished;

  const BlitzPlayView({
    super.key,
    required this.onScoreChanged,
    required this.onFinished,
  });

  @override
  State<BlitzPlayView> createState() => _BlitzPlayViewState();
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

class _BlitzPlayViewState extends State<BlitzPlayView>
    with WidgetsBindingObserver {
  static const ArGameConfig _config = ArGameConfig.balloonPop;

  late final ArEngine _engine;
  late final ArMinigameController _controller;
  late final GameSfx _sfx;
  StreamSubscription<ArGameEvent>? _eventSub;
  int _lastReported = 0;
  bool _finishedNotified = false;

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _engine = sl<ArEngine>();
    _sfx = sl<GameSfx>();
    _controller = ArMinigameController(engine: _engine, config: _config);
    _eventSub = _controller.events.listen(_onGameEvent);
    _controller.addListener(_onControllerChanged);
    _controller.start();
  }

  void _onControllerChanged() {
    final score = _controller.liveScore;
    if (score != _lastReported) {
      _lastReported = score;
      widget.onScoreChanged(score);
    }
    if (_controller.finished && !_finishedNotified) {
      _finishedNotified = true;
      widget.onFinished();
    }
    // Tick sound + haptic for the last 5 seconds of the local round.
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
        _sfx.pop(pitch: 0.95 + 0.05 * event.value);
        event.value >= 4
            ? HapticFeedback.mediumImpact()
            : HapticFeedback.lightImpact();
        _addBurst(
          color: arFxColorFor(event.modelRef),
          label: event.value >= 4 ? '+${event.value} ✨' : '+${event.value}',
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
      case ArGameEventType.timeUp:
        _sfx.fanfare();
        HapticFeedback.mediumImpact();
        break;
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _controller.pause();
    } else if (state == AppLifecycleState.resumed) {
      _controller.resume();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _goTimer?.cancel();
    _eventSub?.cancel();
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // The platform AR camera view fills the screen; the Listener records
        // the touch point so pop FX land where the finger did.
        Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (e) {
            _lastTouch = e.localPosition;
            _lastTouchAt = DateTime.now();
          },
          child: _engine.buildView(),
        ),

        // Local timer + own score + scanning hint, reacting to the controller.
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            if (_controller.error != null && !_controller.hasLiveObjects) {
              return _CenterCard(
                icon: Icons.error_outline,
                text: "Couldn't start AR.\n${_controller.error}",
              );
            }
            if (!_controller.objectsSpawned && !_controller.finished) {
              return const _CenterCard(
                icon: Icons.center_focus_strong,
                text: 'Point at a well-lit floor or table and move your phone '
                    'slowly to find balloons.',
              );
            }
            final s = _controller.secondsRemaining;
            final timerColor = s <= 5
                ? Colors.red[700]
                : (s <= 10 ? Colors.amber[800] : null);
            return SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: ShakeOnTrigger(
                    trigger: _shakeTrigger,
                    child: ArHudPill(
                      icon: Icons.timer,
                      label: '${s}s  ·  You ${_controller.liveScore}',
                      color: timerColor,
                      punchKey: _controller.liveScore,
                    ),
                  ),
                ),
              ),
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

        // 3-2-1-GO pre-roll (every phone gets a clean, fair start moment).
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

class _CenterCard extends StatelessWidget {
  final IconData icon;
  final String text;

  const _CenterCard({required this.icon, required this.text});

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
            Icon(icon, color: Colors.white, size: 28),
            const SizedBox(height: 10),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, height: 1.3)),
          ],
        ),
      ),
    );
  }
}
