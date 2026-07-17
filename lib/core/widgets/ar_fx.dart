import 'dart:math';

import 'package:flutter/material.dart';

/// Screen-space juice for the AR games (Balloon Pop solo + Balloon Blitz).
///
/// The native AR scene can't host particle effects, so every piece of feedback
/// here is a Flutter overlay painted ABOVE the camera view: pop bursts at the
/// tap point, the 3-2-1-GO pre-roll, escape toasts, HUD shake, and the
/// results-screen confetti. All widgets are self-driving one-shots that call
/// [onDone] (or simply complete) so the host view can drop them from its list.

/// Maps an AR model ref to the FX color used for its burst.
Color arFxColorFor(String? modelRef) {
  final ref = modelRef ?? '';
  if (ref.contains('bomb')) return const Color(0xFFFF7A00); // explosion orange
  if (ref.contains('red')) return const Color(0xFFFF5252);
  if (ref.contains('orange')) return const Color(0xFFFFA726);
  if (ref.contains('yellow')) return const Color(0xFFFFEE58);
  if (ref.contains('green')) return const Color(0xFF66BB6A);
  if (ref.contains('blue')) return const Color(0xFF42A5F5);
  if (ref.contains('pink')) return const Color(0xFFF06292);
  if (ref.contains('gem')) return const Color(0xFF4DD0E1);
  return const Color(0xFFB388FF);
}

/// One pop/explosion burst at [center]: shards fly outward with a little
/// gravity, a ring expands, and a score label ("+3" / "−3") floats away.
class PopBurst extends StatefulWidget {
  final Offset center;
  final Color color;
  final String? label;
  final bool isBomb;
  final VoidCallback onDone;

  const PopBurst({
    super.key,
    required this.center,
    required this.color,
    required this.onDone,
    this.label,
    this.isBomb = false,
  });

  @override
  State<PopBurst> createState() => _PopBurstState();
}

class _PopBurstState extends State<PopBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.isBomb ? 800 : 650),
    )
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
        builder: (context, _) => CustomPaint(
          size: Size.infinite,
          painter: _BurstPainter(
            t: _c.value,
            center: widget.center,
            color: widget.color,
            isBomb: widget.isBomb,
            label: widget.label,
            labelStyle: TextStyle(
              color: widget.isBomb ? Colors.redAccent : Colors.white,
              fontSize: widget.isBomb ? 26 : 24,
              fontWeight: FontWeight.w900,
              shadows: const [Shadow(blurRadius: 6, color: Colors.black87)],
            ),
          ),
        ),
      ),
    );
  }
}

class _BurstPainter extends CustomPainter {
  final double t; // 0..1
  final Offset center;
  final Color color;
  final bool isBomb;
  final String? label;
  final TextStyle labelStyle;

  _BurstPainter({
    required this.t,
    required this.center,
    required this.color,
    required this.isBomb,
    required this.label,
    required this.labelStyle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(center.dx.round() * 31 + center.dy.round());
    final shardCount = isBomb ? 16 : 11;
    final fade = (1 - t).clamp(0.0, 1.0);

    // Expanding ring.
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5 * fade + 0.5
      ..color = color.withOpacity(0.8 * fade);
    canvas.drawCircle(center, (isBomb ? 90 : 55) * Curves.easeOut.transform(t),
        ringPaint);

    // Shards with slight gravity.
    final decel = t * (1 - 0.30 * t);
    for (var i = 0; i < shardCount; i++) {
      final angle = (i / shardCount) * 2 * pi + rng.nextDouble() * 0.5;
      final speed = (isBomb ? 95 : 70) * (0.7 + rng.nextDouble() * 0.6);
      final pos = center +
          Offset(cos(angle), sin(angle)) * speed * decel +
          Offset(0, 60 * t * t); // gravity
      final radius = (isBomb ? 5.0 : 4.0) * (0.6 + rng.nextDouble() * 0.6);
      final shardColor = isBomb
          ? (i.isEven ? const Color(0xFF212121) : color)
          : (i % 3 == 0 ? Colors.white : color);
      canvas.drawCircle(
        pos,
        radius * fade,
        Paint()..color = shardColor.withOpacity(fade),
      );
    }

    // Floating score label: up for pops, down for bombs.
    if (label != null) {
      final labelT = Curves.easeOut.transform(t);
      final dy = (isBomb ? 42.0 : -52.0) * labelT;
      final labelFade = t < 0.15 ? t / 0.15 : (1 - t).clamp(0.0, 1.0) / 0.85;
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: labelStyle.copyWith(
            color: labelStyle.color!.withOpacity(labelFade.clamp(0.0, 1.0)),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        center + Offset(-painter.width / 2, dy - painter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.t != t;
}

/// A rival took a balloon: a flame burn-up at [center] — flame tongues licking
/// upward, bright embers rising with a sway, and a soft smoke puff drifting
/// off — plus a floating label ("🔥 Dad +3"). Same lightweight one-shot
/// CustomPaint style as [PopBurst]; positioned by projecting the balloon's
/// local world position to screen (ar_projection.dart). [accent] tints the
/// embers toward the balloon's color so the burn still reads as THAT balloon.
class FlameBurst extends StatefulWidget {
  final Offset center;
  final Color accent;
  final String? label;
  final VoidCallback onDone;

  const FlameBurst({
    super.key,
    required this.center,
    required this.accent,
    required this.onDone,
    this.label,
  });

  @override
  State<FlameBurst> createState() => _FlameBurstState();
}

class _FlameBurstState extends State<FlameBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )
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
        builder: (context, _) => CustomPaint(
          size: Size.infinite,
          painter: _FlamePainter(
            t: _c.value,
            center: widget.center,
            accent: widget.accent,
            label: widget.label,
          ),
        ),
      ),
    );
  }
}

class _FlamePainter extends CustomPainter {
  final double t; // 0..1
  final Offset center;
  final Color accent;
  final String? label;

  _FlamePainter({
    required this.t,
    required this.center,
    required this.accent,
    required this.label,
  });

  static const _flameColors = [
    Color(0xFFFF3D00), // deep flame red-orange
    Color(0xFFFF9100), // orange
    Color(0xFFFFC400), // amber
    Color(0xFFFFF176), // hot yellow core
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(center.dx.round() * 31 + center.dy.round());
    final fade = (1 - t).clamp(0.0, 1.0);

    // Flame tongues: teardrop-ish blobs licking UP from the pop point, hottest
    // (yellow) innermost, dying down as the burn completes.
    const tongues = 9;
    for (var i = 0; i < tongues; i++) {
      final jitter = rng.nextDouble();
      final spread = (i / (tongues - 1) - 0.5) * 34; // horizontal fan
      final flicker = sin(t * 22 + i * 1.7) * 3.5;
      final height = (26 + 30 * jitter) * Curves.easeOut.transform(t);
      final pos = center + Offset(spread * (0.4 + 0.6 * t) + flicker, -height);
      final radius = (7.0 - 4.5 * t) * (0.6 + 0.5 * jitter);
      if (radius <= 0) continue;
      final color = _flameColors[i % _flameColors.length];
      canvas.drawCircle(
        pos,
        radius,
        Paint()..color = color.withOpacity(0.85 * fade),
      );
    }

    // Rising embers: small bright sparks swaying upward past the flames, a few
    // tinted with the balloon's own color.
    const embers = 12;
    for (var i = 0; i < embers; i++) {
      final ex = (rng.nextDouble() - 0.5) * 44;
      final speed = 70 + rng.nextDouble() * 60;
      final sway = sin(t * 10 + i) * 6;
      final pos = center + Offset(ex + sway, -speed * t - 6);
      final emberFade = (1 - t * (0.8 + 0.4 * rng.nextDouble())).clamp(0.0, 1.0);
      if (emberFade <= 0) continue;
      final color = i % 3 == 0 ? accent : _flameColors[i % _flameColors.length];
      canvas.drawCircle(
        pos,
        1.8 + rng.nextDouble() * 1.6,
        Paint()..color = color.withOpacity(emberFade),
      );
    }

    // Smoke: soft grey puffs that appear as the flame dies (second half),
    // growing and thinning as they drift up.
    if (t > 0.35) {
      final st = ((t - 0.35) / 0.65).clamp(0.0, 1.0);
      for (var i = 0; i < 4; i++) {
        final sx = (rng.nextDouble() - 0.5) * 26;
        final pos = center + Offset(sx + sin(st * 5 + i) * 5, -30 - 55 * st);
        canvas.drawCircle(
          pos,
          8 + 10 * st,
          Paint()
            ..color = const Color(0xFF9E9E9E).withOpacity(0.28 * (1 - st)),
        );
      }
    }

    // Floating "🔥 Name +N" label, same feel as PopBurst's score flyout.
    if (label != null) {
      final labelT = Curves.easeOut.transform(t);
      final labelFade = t < 0.15 ? t / 0.15 : (1 - t).clamp(0.0, 1.0) / 0.85;
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: Colors.white.withOpacity(labelFade.clamp(0.0, 1.0)),
            fontSize: 18,
            fontWeight: FontWeight.w900,
            shadows: const [Shadow(blurRadius: 6, color: Colors.black87)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        center + Offset(-painter.width / 2, -64 * labelT - painter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(_FlamePainter old) => old.t != t;
}

/// The 3-2-1-GO pre-roll: giant digits that elastically punch in.
/// Show while `controller.inPreRoll`; pass [showGo] for a beat after "GO".
class GoCountdownOverlay extends StatelessWidget {
  final int digit; // 3, 2, 1 — ignored when showGo
  final bool showGo;

  const GoCountdownOverlay({super.key, required this.digit, this.showGo = false});

  @override
  Widget build(BuildContext context) {
    final text = showGo ? 'GO!' : '$digit';
    return IgnorePointer(
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 450),
          switchInCurve: Curves.elasticOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, anim) => ScaleTransition(
            scale: Tween(begin: 0.3, end: 1.0).animate(anim),
            child: FadeTransition(opacity: anim, child: child),
          ),
          child: Text(
            text,
            key: ValueKey(text),
            style: TextStyle(
              fontSize: showGo ? 88 : 110,
              fontWeight: FontWeight.w900,
              color: showGo ? const Color(0xFF69F0AE) : Colors.white,
              shadows: const [Shadow(blurRadius: 18, color: Colors.black87)],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small self-fading banner near the top edge ("🎈 escaped!").
class ArToast extends StatefulWidget {
  final String text;
  final VoidCallback onDone;

  const ArToast({super.key, required this.text, required this.onDone});

  @override
  State<ArToast> createState() => _ArToastState();
}

class _ArToastState extends State<ArToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100))
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
          final opacity =
              t < 0.15 ? t / 0.15 : (t > 0.7 ? (1 - t) / 0.3 : 1.0);
          return Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, -12 * t),
              child: child,
            ),
          );
        },
        child: Align(
          alignment: Alignment.topCenter,
          child: Container(
            margin: const EdgeInsets.only(top: 64),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.65),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              widget.text,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }
}

/// Wraps a child and shakes it horizontally (sin decay) whenever [trigger]
/// increments — used to rattle the HUD when a bomb goes off.
class ShakeOnTrigger extends StatefulWidget {
  final int trigger;
  final Widget child;

  const ShakeOnTrigger({super.key, required this.trigger, required this.child});

  @override
  State<ShakeOnTrigger> createState() => _ShakeOnTriggerState();
}

class _ShakeOnTriggerState extends State<ShakeOnTrigger>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 320));
  }

  @override
  void didUpdateWidget(ShakeOnTrigger old) {
    super.didUpdateWidget(old);
    if (widget.trigger != old.trigger) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = _c.value;
        final dx = sin(t * pi * 6) * 9 * (1 - t);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: widget.child,
    );
  }
}

/// HUD pill (timer / score) with built-in juice: a scale punch whenever
/// [punchKey] changes, and an urgency color override.
class ArHudPill extends StatefulWidget {
  final IconData icon;
  final String label;

  /// Change this value to make the pill punch (e.g. pass the score).
  final Object? punchKey;

  /// Background override (e.g. amber/red as the timer runs out).
  final Color? color;

  const ArHudPill({
    super.key,
    required this.icon,
    required this.label,
    this.punchKey,
    this.color,
  });

  @override
  State<ArHudPill> createState() => _ArHudPillState();
}

class _ArHudPillState extends State<ArHudPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      lowerBound: 0,
      upperBound: 1,
    );
  }

  @override
  void didUpdateWidget(ArHudPill old) {
    super.didUpdateWidget(old);
    if (widget.punchKey != old.punchKey) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        // 1.0 → 1.22 → 1.0 punch.
        final scale = 1 + 0.22 * sin(_c.value * pi);
        return Transform.scale(scale: scale, child: child);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: (widget.color ?? Colors.black).withOpacity(0.65),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.icon, color: Colors.white, size: 18),
            const SizedBox(width: 6),
            Text(
              widget.label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One-shot celebratory confetti rain across the whole area (results screen).
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({super.key});

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2200))
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
        builder: (context, _) => CustomPaint(
          size: Size.infinite,
          painter: _ConfettiPainter(t: _c.value),
        ),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  final double t;

  _ConfettiPainter({required this.t});

  static const _colors = [
    Color(0xFFFF5252),
    Color(0xFFFFA726),
    Color(0xFFFFEE58),
    Color(0xFF66BB6A),
    Color(0xFF42A5F5),
    Color(0xFFF06292),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(7);
    final fade = t > 0.75 ? (1 - t) / 0.25 : 1.0;
    for (var i = 0; i < 46; i++) {
      final x0 = rng.nextDouble() * size.width;
      final speed = 0.55 + rng.nextDouble() * 0.7;
      final sway = (rng.nextDouble() - 0.5) * 60;
      final y = -20 + (size.height + 40) * t * speed;
      if (y > size.height) continue;
      final x = x0 + sin(t * 6 + i) * sway * 0.2;
      final angle = t * 8 + i;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(angle);
      canvas.drawRect(
        const Rect.fromLTWH(-4, -2.5, 8, 5),
        Paint()..color = _colors[i % _colors.length].withOpacity(fade),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
