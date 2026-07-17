import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/di/service_locator.dart';
import '../../core/services/ar/ar_capability_service.dart';
import '../../core/services/ar/ar_engine.dart';
import '../../core/services/sfx/game_sfx.dart';
import '../../core/widgets/ar_fx.dart';
import '../games/presentation/widgets/ar_unsupported_view.dart';
import 'tower_trials_controller.dart';

/// Tower Trials: the first AR-VERSUS game — turn-based tower stacking,
/// pass-the-phone, one device, 2+ players. A ghost block hovers where your
/// next block would land, offset by where your camera is AIMING; line it up
/// over the tower top and drop. Sloppy drops accumulate wobble; cross the
/// line and the tower collapses on YOUR turn — you're out. Last builder
/// standing wins.
///
/// Offline / local: no Firestore game doc — it owns a [TowerTrialsController]
/// over a fresh [ArEngine], modelled on Treasure Hunt.
///
/// DEVICE-ONLY: the camera + 3D blocks need a real ARCore/ARKit device. The
/// widget builds and the phase/HUD flow is testable with a fake engine, but
/// the AR surface itself cannot be verified off-device.
class TowerTrialsScreen extends StatefulWidget {
  const TowerTrialsScreen({super.key});

  @override
  State<TowerTrialsScreen> createState() => _TowerTrialsScreenState();
}

enum _Prep { checking, unsupported, ready }

class _TowerTrialsScreenState extends State<TowerTrialsScreen> {
  final ArCapabilityService _capability = sl<ArCapabilityService>();

  _Prep _prep = _Prep.checking;
  ArSupport _reason = ArSupport.unknownError;

  ArEngine? _engine;
  GameSfx? _sfx;
  TowerTrialsController? _controller;
  StreamSubscription<TowerTrialsEvent>? _eventSub;
  Timer? _aimTimer;
  bool _pollingAim = false;

  bool _showGo = false;
  Timer? _goTimer;
  int _shakeTrigger = 0;
  final List<int> _bursts = [];
  final List<int> _bombBursts = [];
  final List<int> _perfects = [];
  int _fxSeq = 0;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    var support = await _capability.check();
    if (support == ArSupport.cameraDenied) {
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
    final controller = TowerTrialsController(engine: engine);
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
    // The aim source: poll the camera pose and feed the controller pure
    // numbers (ray ∩ landing plane). Only does work during the aiming phase.
    _aimTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _pollAim(),
    );
  }

  Future<void> _pollAim() async {
    final c = _controller;
    final engine = _engine;
    if (c == null || engine == null || _pollingAim) return;
    if (c.phase != TowerTrialsPhase.aiming || !c.baseReady) return;
    _pollingAim = true;
    try {
      final pose = await engine.cameraPose();
      if (!mounted || c.phase != TowerTrialsPhase.aiming) return;
      if (pose == null) {
        c.clearAim(); // tracking lost — no drop until it returns
        return;
      }
      final aim = TowerTrialsController.aimFromPose(
        pose: pose,
        targetX: c.aimTargetX,
        targetY: c.aimTargetY,
        targetZ: c.aimTargetZ,
      );
      if (aim == null) {
        c.clearAim();
      } else {
        c.updateAim(aim.dx, aim.dz);
      }
    } finally {
      _pollingAim = false;
    }
  }

  @override
  void dispose() {
    _aimTimer?.cancel();
    _goTimer?.cancel();
    _eventSub?.cancel();
    _controller?.removeListener(_onControllerChanged);
    _controller?.dispose();
    super.dispose();
  }

  // ---- Feel layer -----------------------------------------------------------

  void _onEvent(TowerTrialsEvent event) {
    if (!mounted) return;
    final sfx = _sfx;
    switch (event.type) {
      case TowerTrialsEventType.roundStart:
        HapticFeedback.lightImpact();
        break;
      case TowerTrialsEventType.turnStart:
        sfx?.go();
        HapticFeedback.mediumImpact();
        setState(() => _showGo = true);
        _goTimer?.cancel();
        _goTimer = Timer(const Duration(milliseconds: 700), () {
          if (mounted) setState(() => _showGo = false);
        });
        break;
      case TowerTrialsEventType.place:
        // Cleaner drops sound snappier.
        final quality =
            1.0 - (event.offset / TowerTrialsController.maxAim).clamp(0.0, 1.0);
        sfx?.pop(pitch: 0.9 + 0.3 * quality);
        HapticFeedback.mediumImpact();
        setState(() => _bursts.add(_fxSeq++));
        break;
      case TowerTrialsEventType.perfect:
        sfx?.pop(pitch: 1.4);
        HapticFeedback.heavyImpact();
        setState(() {
          _bursts.add(_fxSeq++);
          _perfects.add(_fxSeq++);
        });
        break;
      case TowerTrialsEventType.warning:
        sfx?.tick();
        HapticFeedback.heavyImpact();
        setState(() => _shakeTrigger++);
        break;
      case TowerTrialsEventType.collapse:
        sfx?.boom();
        sfx?.whoosh();
        HapticFeedback.vibrate();
        setState(() {
          _shakeTrigger++;
          _bombBursts.add(_fxSeq++);
        });
        break;
      case TowerTrialsEventType.winner:
        sfx?.fanfare();
        HapticFeedback.mediumImpact();
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
        appBar: AppBar(title: const Text('Tower Trials')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_prep == _Prep.unsupported) {
      return Scaffold(
        appBar: AppBar(title: const Text('Tower Trials')),
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
    final center = MediaQuery.of(context).size.center(Offset.zero);
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          _engine!.buildView(),
          SafeArea(child: _phaseOverlay(controller)),
          for (final id in _bursts)
            PopBurst(
              key: ValueKey('tt-burst-$id'),
              center: center,
              color: arFxColorFor('blue'),
              onDone: () => setState(() => _bursts.remove(id)),
            ),
          for (final id in _bombBursts)
            PopBurst(
              key: ValueKey('tt-boom-$id'),
              center: center,
              color: arFxColorFor('bomb'),
              isBomb: true,
              label: '💥',
              onDone: () => setState(() => _bombBursts.remove(id)),
            ),
          for (final id in _perfects)
            _PerfectFlash(
              key: ValueKey('tt-perfect-$id'),
              onDone: () => setState(() => _perfects.remove(id)),
            ),
          if (_showGo) const GoCountdownOverlay(digit: 0, showGo: true),
        ],
      ),
    );
  }

  Widget _phaseOverlay(TowerTrialsController c) {
    switch (c.phase) {
      case TowerTrialsPhase.setup:
        return _SetupOverlay(onStart: c.startGame);
      case TowerTrialsPhase.handoff:
        return _HandoffOverlay(controller: c, onStart: c.beginTurn);
      case TowerTrialsPhase.aiming:
        return _AimingOverlay(controller: c, shakeTrigger: _shakeTrigger);
      case TowerTrialsPhase.collapsing:
        return const _CollapsingOverlay();
      case TowerTrialsPhase.results:
        return _ResultsOverlay(
          controller: c,
          onDone: () => Navigator.of(context).maybePop(),
        );
    }
  }
}

// ===========================================================================
// Phase overlays
// ===========================================================================

/// Start card: 2–6 player names (like Treasure Hunt's turn prompts, but all up
/// front — versus needs the full roster before the first drop).
class _SetupOverlay extends StatefulWidget {
  final void Function(List<String> names) onStart;

  const _SetupOverlay({required this.onStart});

  @override
  State<_SetupOverlay> createState() => _SetupOverlayState();
}

class _SetupOverlayState extends State<_SetupOverlay> {
  static const int maxPlayers = 6;
  final List<TextEditingController> _names = [
    TextEditingController(text: 'Player 1'),
    TextEditingController(text: 'Player 2'),
  ];

  @override
  void dispose() {
    for (final c in _names) {
      c.dispose();
    }
    super.dispose();
  }

  void _start() {
    final names = <String>[];
    for (var i = 0; i < _names.length; i++) {
      final raw = _names[i].text.trim();
      names.add(raw.isEmpty ? 'Player ${i + 1}' : raw);
    }
    widget.onStart(names);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(0.82),
      alignment: Alignment.center,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🗼', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 8),
            const Text(
              'Tower Trials',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Take turns stacking blocks in AR — aim the ghost block over '
              'the tower and drop. Sloppy drops make it wobble; topple it '
              'and you\'re out. Last builder standing wins!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 15),
            ),
            const SizedBox(height: 20),
            for (var i = 0; i < _names.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _names[i],
                        textCapitalization: TextCapitalization.words,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Player ${i + 1}',
                          labelStyle:
                              const TextStyle(color: Colors.white54),
                          enabledBorder: const OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.white24),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.white70),
                          ),
                        ),
                      ),
                    ),
                    if (_names.length > 2)
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline,
                            color: Colors.white54),
                        onPressed: () => setState(() {
                          _names.removeAt(i).dispose();
                        }),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            if (_names.length < maxPlayers)
              TextButton.icon(
                onPressed: () => setState(() {
                  _names.add(TextEditingController(
                      text: 'Player ${_names.length + 1}'));
                }),
                icon: const Icon(Icons.person_add, color: Colors.white70),
                label: const Text('Add player',
                    style: TextStyle(color: Colors.white70)),
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _start,
              icon: const Text('🧱', style: TextStyle(fontSize: 18)),
              label: const Text('Start stacking'),
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HandoffOverlay extends StatelessWidget {
  final TowerTrialsController controller;
  final VoidCallback onStart;

  const _HandoffOverlay({required this.controller, required this.onStart});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final ready = c.baseReady;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: ready ? onStart : null,
      child: Container(
        color: Colors.black.withOpacity(0.82),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (c.collapsedBy != null) ...[
              Text(
                '💥 ${c.collapsedBy} toppled the tower!',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.orangeAccent,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Round ${c.round} — fresh tower.',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 20),
            ],
            const Text('🤝', style: TextStyle(fontSize: 60)),
            const SizedBox(height: 16),
            Text(
              'Hand the phone to ${c.currentPlayerName}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 14),
            _StabilityMeter(stability01: c.stability01),
            const SizedBox(height: 8),
            Text(
              '${c.blocksPlaced} block${c.blocksPlaced == 1 ? '' : 's'} up · '
              '${c.players.where((p) => !p.eliminated).length} builders left',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 26),
            _Pill(
              icon: ready ? Icons.touch_app : Icons.hourglass_top,
              label: ready ? 'Tap anywhere to build' : 'Placing the base…',
            ),
          ],
        ),
      ),
    );
  }
}

class _AimingOverlay extends StatelessWidget {
  final TowerTrialsController controller;
  final int shakeTrigger;

  const _AimingOverlay({
    required this.controller,
    required this.shakeTrigger,
  });

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ArHudPill(
                icon: Icons.person,
                label: c.currentPlayerName,
                punchKey: c.currentPlayerName,
              ),
              ArHudPill(
                icon: Icons.layers,
                label: '${c.blocksPlaced} stacked',
                punchKey: c.blocksPlaced,
              ),
            ],
          ),
          const SizedBox(height: 10),
          ShakeOnTrigger(
            trigger: shakeTrigger,
            child: _StabilityMeter(stability01: c.stability01),
          ),
          const Spacer(),
          _Pill(
            icon: c.hasAim ? Icons.filter_center_focus : Icons.explore,
            label: c.hasAim
                ? 'Line the ghost block up over the tower'
                : 'Point your camera at the tower top…',
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: c.hasAim ? c.dropBlock : null,
            style: FilledButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 48, vertical: 18),
              textStyle: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            child: const Text('DROP 🧱'),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _CollapsingOverlay extends StatelessWidget {
  const _CollapsingOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Text(
          'TIMBER!',
          style: TextStyle(
            fontSize: 64,
            fontWeight: FontWeight.w900,
            color: Colors.orangeAccent,
            shadows: const [Shadow(blurRadius: 18, color: Colors.black87)],
          ),
        ),
      ),
    );
  }
}

class _ResultsOverlay extends StatelessWidget {
  final TowerTrialsController controller;
  final VoidCallback onDone;

  const _ResultsOverlay({required this.controller, required this.onDone});

  @override
  Widget build(BuildContext context) {
    final order = controller.finishOrder;
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
                  const Text('🏆', style: TextStyle(fontSize: 56)),
                  const SizedBox(height: 8),
                  Text(
                    '${controller.winnerName ?? 'Nobody'} wins!',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Last builder standing.',
                    style: TextStyle(color: Colors.white70, fontSize: 15),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    constraints: const BoxConstraints(maxWidth: 420),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < order.length; i++)
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(vertical: 4),
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
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 16),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    order[i],
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                if (i > 0)
                                  const Text(
                                    'toppled',
                                    style: TextStyle(
                                        color: Colors.white54, fontSize: 12),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
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

// ===========================================================================
// Bits
// ===========================================================================

/// Stability meter: full/green = solid, empty/red = about to topple. Fills
/// toward red as instability accumulates.
class _StabilityMeter extends StatelessWidget {
  final double stability01;

  const _StabilityMeter({required this.stability01});

  @override
  Widget build(BuildContext context) {
    final danger = 1 - stability01;
    final color = Color.lerp(
      const Color(0xFF66BB6A),
      const Color(0xFFE53935),
      Curves.easeIn.transform(danger),
    )!;
    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            danger >= TowerTrialsController.warnThreshold
                ? Icons.warning_amber
                : Icons.foundation,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 8),
          const Text(
            'Stability',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 10,
                child: Stack(
                  children: [
                    Container(color: Colors.white.withOpacity(0.15)),
                    AnimatedFractionallySizedBox(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                      alignment: Alignment.centerLeft,
                      widthFactor: stability01.clamp(0.0, 1.0),
                      child: Container(color: color),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${(stability01 * 100).round()}%',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

/// One-shot "PERFECT!" flash: gold text that elastically punches in, holds a
/// beat, then fades — the payoff for a near-centre drop.
class _PerfectFlash extends StatefulWidget {
  final VoidCallback onDone;

  const _PerfectFlash({super.key, required this.onDone});

  @override
  State<_PerfectFlash> createState() => _PerfectFlashState();
}

class _PerfectFlashState extends State<_PerfectFlash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) widget.onDone();
      })
      ..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          final t = _c.value;
          final scale = 0.4 + Curves.elasticOut.transform(t.clamp(0.0, 0.6) / 0.6) * 0.6;
          final opacity = t < 0.12
              ? t / 0.12
              : (t > 0.7 ? (1 - t) / 0.3 : 1.0);
          return Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Transform.scale(scale: scale, child: child),
          );
        },
        child: const Center(
          child: Text(
            '✨ PERFECT! ✨',
            style: TextStyle(
              fontSize: 44,
              fontWeight: FontWeight.w900,
              color: Color(0xFFFFD54F),
              shadows: [Shadow(blurRadius: 18, color: Colors.black87)],
            ),
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

  const _Pill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
