import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/di/service_locator.dart';
import '../../core/services/ar/ar_capability_service.dart';
import '../../core/services/ar/ar_engine.dart';
import '../../core/services/sfx/game_sfx.dart';
import '../../core/widgets/ar_fx.dart';
import '../games/presentation/widgets/ar_unsupported_view.dart';
import 'treasure_hunt_controller.dart';

/// Treasure Hunt (internally "Geiger Hunt"): a co-located, one-device, pass-the-
/// phone AR hide-and-seek. The hider stores invisible spots; the seeker hunts
/// them with a hot/cold geiger, and each treasure REVEALS as a tappable gem in
/// front of the camera when they get within a metre (drift-immune by design).
///
/// Offline / local: no Firestore game doc — it owns a [TreasureHuntController]
/// over a fresh [ArEngine], modelled on the offline solo modes.
///
/// DEVICE-ONLY: the camera + 3D reveal need a real ARCore/ARKit device. The
/// widget builds and the phase/HUD flow is testable with a fake engine, but the
/// AR surface itself cannot be verified off-device.
class TreasureHuntScreen extends StatefulWidget {
  const TreasureHuntScreen({super.key});

  @override
  State<TreasureHuntScreen> createState() => _TreasureHuntScreenState();
}

enum _Prep { checking, unsupported, ready }

class _TreasureHuntScreenState extends State<TreasureHuntScreen>
    with WidgetsBindingObserver {
  final ArCapabilityService _capability = sl<ArCapabilityService>();

  _Prep _prep = _Prep.checking;
  ArSupport _reason = ArSupport.unknownError;

  ArEngine? _engine;
  GameSfx? _sfx;
  TreasureHuntController? _controller;
  StreamSubscription<TreasureHuntEvent>? _eventSub;

  bool _debug = false;
  bool _showGo = false;
  Timer? _goTimer;
  final List<int> _bursts = [];
  int _burstSeq = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _prepare();
  }

  Future<void> _prepare() async {
    var support = await _capability.check();
    if (support == ArSupport.cameraDenied) {
      // Give the OS prompt a chance before falling back.
      final granted = await _capability.requestCamera();
      if (granted) support = await _capability.check();
    }
    if (!mounted) return;
    if (support != ArSupport.supported) {
      setState(() {
        _prep = _Prep.unsupported;
        _reason = support;
      });
      return;
    }

    final engine = sl<ArEngine>();
    final controller = TreasureHuntController(engine: engine);
    _eventSub = controller.events.listen(_onEvent);
    controller.addListener(_onControllerChanged);
    setState(() {
      _engine = engine;
      _sfx = sl<GameSfx>();
      _controller = controller;
      _prep = _Prep.ready;
    });
    // The AR view is now in the tree; start() awaits its creation internally.
    controller.start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _goTimer?.cancel();
    _eventSub?.cancel();
    _controller?.removeListener(_onControllerChanged);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Backgrounding drops tracking; the controller's poll will flip to
    // trackingLost on its own, and regain when the app + pose return.
  }

  // ---- Feel layer -----------------------------------------------------------

  void _onEvent(TreasureHuntEvent event) {
    if (!mounted) return;
    final sfx = _sfx;
    switch (event.type) {
      case TreasureHuntEventType.hideStored:
        HapticFeedback.mediumImpact();
        break;
      case TreasureHuntEventType.countdownTick:
        sfx?.tick();
        break;
      case TreasureHuntEventType.go:
        sfx?.go();
        HapticFeedback.mediumImpact();
        setState(() => _showGo = true);
        _goTimer?.cancel();
        _goTimer = Timer(const Duration(milliseconds: 750), () {
          if (mounted) setState(() => _showGo = false);
        });
        break;
      case TreasureHuntEventType.geigerTick:
        sfx?.tick();
        switch (event.heat) {
          case GeigerHeat.hot:
            HapticFeedback.heavyImpact();
            break;
          case GeigerHeat.warm:
            HapticFeedback.mediumImpact();
            break;
          case GeigerHeat.cold:
            HapticFeedback.lightImpact();
            break;
          case GeigerHeat.silent:
            break;
        }
        break;
      case TreasureHuntEventType.reveal:
        HapticFeedback.heavyImpact();
        break;
      case TreasureHuntEventType.collect:
        sfx?.pop();
        HapticFeedback.mediumImpact();
        setState(() => _bursts.add(_burstSeq++));
        break;
      case TreasureHuntEventType.allFound:
      case TreasureHuntEventType.timeUp:
        sfx?.fanfare();
        HapticFeedback.mediumImpact();
        break;
      case TreasureHuntEventType.trackingLost:
        HapticFeedback.vibrate();
        break;
      case TreasureHuntEventType.trackingRegained:
        HapticFeedback.selectionClick();
        break;
    }
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  // ---- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_prep == _Prep.checking) {
      return Scaffold(
        appBar: AppBar(title: const Text('Treasure Hunt')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_prep == _Prep.unsupported) {
      return Scaffold(
        appBar: AppBar(title: const Text('Treasure Hunt')),
        body: ArUnsupportedView(
          reason: _reason,
          onSkip: () => Navigator.of(context).maybePop(),
          onOpenSettings: _reason == ArSupport.cameraDenied
              ? () => _capability.openSettings()
              : null,
        ),
      );
    }

    final controller = _controller!;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          _engine!.buildView(),
          SafeArea(child: _phaseOverlay(controller)),
          for (final id in _bursts)
            PopBurst(
              key: ValueKey('th-burst-$id'),
              center: MediaQuery.of(context).size.center(Offset.zero),
              color: arFxColorFor('gem'),
              label: '💎',
              onDone: () => setState(() => _bursts.remove(id)),
            ),
          if (controller.phase == TreasureHuntPhase.countdown)
            GoCountdownOverlay(digit: controller.countdownValue),
          if (_showGo) const GoCountdownOverlay(digit: 0, showGo: true),
          if (_debug &&
              (controller.phase == TreasureHuntPhase.hunting ||
                  controller.phase == TreasureHuntPhase.trackingLost ||
                  controller.phase == TreasureHuntPhase.hiding))
            _DebugHud(controller: controller),
        ],
      ),
    );
  }

  Widget _phaseOverlay(TreasureHuntController c) {
    switch (c.phase) {
      case TreasureHuntPhase.hiding:
        return _HideOverlay(
          controller: c,
          debug: _debug,
          onToggleDebug: () => setState(() => _debug = !_debug),
        );
      case TreasureHuntPhase.handoff:
        return _HandoffOverlay(
          seekerName: c.currentSeekerName,
          onStart: c.beginCountdown,
        );
      case TreasureHuntPhase.countdown:
        return const SizedBox.shrink();
      case TreasureHuntPhase.hunting:
        return _HuntOverlay(controller: c);
      case TreasureHuntPhase.trackingLost:
        return const _TrackingLostOverlay();
      case TreasureHuntPhase.betweenTurns:
        return _BetweenTurnsOverlay(
          controller: c,
          onNextSeeker: _promptNextSeeker,
          onFinish: c.finishGame,
        );
      case TreasureHuntPhase.results:
        return _ResultsOverlay(
          controller: c,
          onDone: () => Navigator.of(context).maybePop(),
        );
    }
  }

  Future<void> _promptNextSeeker() async {
    final c = _controller!;
    final defaultName = 'Seeker ${c.leaderboard.length + 1}';
    final ctl = TextEditingController(text: defaultName);
    try {
      final name = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Next seeker'),
          content: TextField(
            controller: ctl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name'),
            onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(ctl.text.trim()),
              child: const Text('Hand off'),
            ),
          ],
        ),
      );
      if (name != null && name.isNotEmpty) {
        c.nextSeeker(name);
      }
    } finally {
      // Dispose the dialog's controller once it closes — one leak per handoff
      // otherwise (FINDING E).
      ctl.dispose();
    }
  }
}

// ===========================================================================
// Phase overlays
// ===========================================================================

class _HideOverlay extends StatelessWidget {
  final TreasureHuntController controller;
  final bool debug;
  final VoidCallback onToggleDebug;

  const _HideOverlay({
    required this.controller,
    required this.debug,
    required this.onToggleDebug,
  });

  @override
  Widget build(BuildContext context) {
    final count = controller.treasureCount;
    final canHide = controller.canHideMore;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Options row (holds the debug toggle).
          Row(
            children: [
              const _Pill(icon: Icons.map, label: 'Hide treasures'),
              const Spacer(),
              _Pill(
                icon: debug ? Icons.bug_report : Icons.bug_report_outlined,
                label: 'Debug',
                onTap: onToggleDebug,
                active: debug,
              ),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.55),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              count == 0
                  ? 'Walk the room and tap "Hide here" to stash treasures.'
                  : '$count/${controller.maxTreasures} hidden — hide more or tap Done.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: canHide ? () => controller.hideHere() : null,
                  icon: const Text('🙈', style: TextStyle(fontSize: 18)),
                  label: Text(canHide ? 'Hide here' : 'Max reached'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: count > 0 ? controller.doneHiding : null,
                  icon: const Icon(Icons.check),
                  label: const Text('Done hiding'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white70),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HandoffOverlay extends StatelessWidget {
  final String seekerName;
  final VoidCallback onStart;

  const _HandoffOverlay({required this.seekerName, required this.onStart});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onStart,
      child: Container(
        color: Colors.black.withOpacity(0.82),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🤝', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 20),
            Text(
              'Hand the phone to $seekerName',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Keep it pointed at the room so the treasures stay hidden and '
              'tracking survives.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 15),
            ),
            const SizedBox(height: 28),
            const _Pill(icon: Icons.touch_app, label: 'Tap anywhere to start'),
          ],
        ),
      ),
    );
  }
}

class _HuntOverlay extends StatelessWidget {
  final TreasureHuntController controller;

  const _HuntOverlay({required this.controller});

  @override
  Widget build(BuildContext context) {
    final s = controller.secondsRemaining;
    final timerColor = s <= 10 ? Colors.red[700] : null;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ArHudPill(
                icon: Icons.timer,
                label: '${s}s',
                color: timerColor,
                punchKey: s <= 5 ? s : null,
              ),
              ArHudPill(
                icon: Icons.diamond,
                label:
                    '${controller.foundThisTurn}/${controller.totalTreasures}',
                punchKey: controller.foundThisTurn,
              ),
            ],
          ),
          const Spacer(),
          if (controller.revealPending)
            GestureDetector(
              onTap: controller.collectRevealed,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                decoration: BoxDecoration(
                  color: arFxColorFor('gem'),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(blurRadius: 18, color: Colors.black54),
                  ],
                ),
                child: const Text(
                  'FOUND IT! 💎 TAP!',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            )
          else
            const _Pill(icon: Icons.hearing, label: 'Follow the ticking…'),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _TrackingLostOverlay extends StatelessWidget {
  const _TrackingLostOverlay();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(0.75),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.explore_off, color: Colors.white, size: 56),
          SizedBox(height: 16),
          Text(
            'Tracking lost',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Walk to the middle of the room and pan slowly.\n'
            'The hunt resumes automatically.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 15),
          ),
        ],
      ),
    );
  }
}

class _BetweenTurnsOverlay extends StatelessWidget {
  final TreasureHuntController controller;
  final VoidCallback onNextSeeker;
  final VoidCallback onFinish;

  const _BetweenTurnsOverlay({
    required this.controller,
    required this.onNextSeeker,
    required this.onFinish,
  });

  @override
  Widget build(BuildContext context) {
    // Header reflects the turn that JUST ended, not the best-sorted leaderboard
    // row — otherwise a later failed turn shows "All found!" (FINDING D).
    final last = controller.lastTurnResult;
    return Container(
      color: Colors.black.withOpacity(0.82),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            last != null && last.allFound ? '🏆 All found!' : "⏱ Time's up!",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 16),
          _Leaderboard(controller: controller),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onNextSeeker,
            icon: const Icon(Icons.person_add),
            label: const Text('Next seeker (same hides)'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onFinish,
            child: const Text('Finish & see results',
                style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }
}

class _ResultsOverlay extends StatelessWidget {
  final TreasureHuntController controller;
  final VoidCallback onDone;

  const _ResultsOverlay({required this.controller, required this.onDone});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(0.88),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ConfettiBurst(),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🗺️ Results',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                      )),
                  const SizedBox(height: 20),
                  _Leaderboard(controller: controller),
                  const SizedBox(height: 24),
                  FilledButton(onPressed: onDone, child: const Text('Done')),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Leaderboard extends StatelessWidget {
  final TreasureHuntController controller;
  const _Leaderboard({required this.controller});

  @override
  Widget build(BuildContext context) {
    final rows = controller.leaderboard;
    if (rows.isEmpty) {
      return const Text('No runs yet.',
          style: TextStyle(color: Colors.white70));
    }
    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < rows.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      switch (i) {
                        0 => '🥇',
                        1 => '🥈',
                        2 => '🥉',
                        _ => '${i + 1}',
                      },
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      rows[i].seekerName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '${rows[i].treasuresFound}/${rows[i].totalTreasures} · '
                    '${rows[i].timeUsedSeconds}s',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DebugHud extends StatelessWidget {
  final TreasureHuntController controller;
  const _DebugHud({required this.controller});

  @override
  Widget build(BuildContext context) {
    final d = controller.distanceToNearest;
    final tick = controller.tickIntervalMs;
    final track = controller.trackingLost ? 'LOST' : 'ok';
    return Positioned(
      bottom: 12,
      left: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(10),
        ),
        child: DefaultTextStyle(
          style: const TextStyle(
            color: Colors.greenAccent,
            fontSize: 12,
            fontFamily: 'monospace',
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('dist: ${d == null ? '—' : '${d.toStringAsFixed(2)}m'}'),
              Text('tick: ${tick == null ? 'silent' : '${tick}ms'}'),
              Text('track: $track   heat: ${controller.heat.name}'),
              Text('found: ${controller.foundThisTurn}/'
                  '${controller.totalTreasures}'),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small translucent capsule used across the overlays.
class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;

  const _Pill({
    required this.icon,
    required this.label,
    this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: (active ? Colors.tealAccent.shade700 : Colors.black)
            .withOpacity(active ? 0.85 : 0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600)),
        ],
      ),
    );
    if (onTap == null) return pill;
    return GestureDetector(onTap: onTap, child: pill);
  }
}
