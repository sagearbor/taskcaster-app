import 'dart:convert';
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';

/// One pen stroke. Points are stored NORMALISED to 0..1 of the canvas so a
/// drawing renders identically at any size / on any device.
class DrawingStroke {
  final int color;
  final List<Offset> points;

  DrawingStroke(this.color, this.points);

  Map<String, dynamic> toJson() => {
        'c': color,
        'p': [for (final pt in points) ...[pt.dx, pt.dy]],
      };

  factory DrawingStroke.fromJson(Map<String, dynamic> map) {
    final flat = (map['p'] as List).cast<num>();
    final pts = <Offset>[];
    for (var i = 0; i + 1 < flat.length; i += 2) {
      pts.add(Offset(flat[i].toDouble(), flat[i + 1].toDouble()));
    }
    return DrawingStroke((map['c'] as num).toInt(), pts);
  }
}

/// Decode the JSON produced by [DrawingController.toJson]. Tolerant of empty /
/// malformed input (returns an empty list) so a bad document never crashes the
/// reveal.
List<DrawingStroke> parseStrokes(String json) {
  if (json.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(json);
    if (decoded is! List) return const [];
    return decoded
        .map((e) => DrawingStroke.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  } catch (_) {
    return const [];
  }
}

/// Holds the in-progress drawing for [DrawingCanvas].
class DrawingController extends ChangeNotifier {
  final List<DrawingStroke> _strokes = [];
  Color color = Colors.black;

  List<DrawingStroke> get strokes => List.unmodifiable(_strokes);

  bool get isEmpty => _strokes.every((s) => s.points.isEmpty);

  void selectColor(Color c) {
    color = c;
    notifyListeners();
  }

  void startStroke(Offset normalized) {
    _strokes.add(DrawingStroke(color.value, [normalized]));
    notifyListeners();
  }

  void appendPoint(Offset normalized) {
    if (_strokes.isNotEmpty) {
      _strokes.last.points.add(normalized);
      notifyListeners();
    }
  }

  void undo() {
    if (_strokes.isNotEmpty) {
      _strokes.removeLast();
      notifyListeners();
    }
  }

  void clear() {
    _strokes.clear();
    notifyListeners();
  }

  String toJson() => jsonEncode([for (final s in _strokes) s.toJson()]);
}

const List<Color> kPenColors = [
  Colors.black,
  Color(0xFFE53935), // red
  Color(0xFF1E88E5), // blue
  Color(0xFF43A047), // green
  Color(0xFFFB8C00), // orange
  Color(0xFF8E24AA), // purple
];

/// An editable freehand canvas. Square, normalised, web-friendly (uses pan
/// gestures — no platform-specific pointer APIs).
class DrawingCanvas extends StatelessWidget {
  final DrawingController controller;

  const DrawingCanvas({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final side = constraints.maxWidth;
              Offset normalize(Offset local) => Offset(
                    (local.dx / side).clamp(0.0, 1.0),
                    (local.dy / side).clamp(0.0, 1.0),
                  );
              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.black26, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (d) =>
                      controller.startStroke(normalize(d.localPosition)),
                  onPanUpdate: (d) =>
                      controller.appendPoint(normalize(d.localPosition)),
                  child: AnimatedBuilder(
                    animation: controller,
                    builder: (context, _) => CustomPaint(
                      painter: StrokePlaybackPainter(controller.strokes),
                      size: Size(side, side),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        _Toolbar(controller: controller),
      ],
    );
  }
}

class _Toolbar extends StatelessWidget {
  final DrawingController controller;
  const _Toolbar({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Row(
        children: [
          for (final c in kPenColors)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => controller.selectColor(c),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: controller.color == c
                          ? Colors.amber
                          : Colors.black26,
                      width: controller.color == c ? 3 : 1,
                    ),
                  ),
                ),
              ),
            ),
          const Spacer(),
          IconButton(
            tooltip: 'Undo',
            onPressed: controller.undo,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: 'Clear',
            onPressed: controller.clear,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}

/// Read-only renderer for a stored drawing (used by the guess step and the
/// reveal). Always square.
class DrawingView extends StatelessWidget {
  final String json;
  final double? size;

  const DrawingView({super.key, required this.json, this.size});

  @override
  Widget build(BuildContext context) {
    final strokes = parseStrokes(json);
    final canvas = AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.black12),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: CustomPaint(
          painter: StrokePlaybackPainter(strokes),
          child: const SizedBox.expand(),
        ),
      ),
    );
    if (size != null) {
      return SizedBox(width: size, height: size, child: canvas);
    }
    return canvas;
  }
}

/// Total number of recorded points across [strokes]. The unit the playback
/// animation works in.
int totalStrokePoints(List<DrawingStroke> strokes) =>
    strokes.fold(0, (n, s) => n + s.points.length);

/// Replays a stored drawing stroke-by-stroke, exactly as it was drawn: one
/// animation drives a cumulative point budget and the painter renders complete
/// strokes up to the cutoff plus a partial polyline for the stroke in flight.
///
/// Used in the reveal (each drawing "draws itself" as it appears) and on the
/// guess step. Thumbnails / static recaps keep using [DrawingView].
class AnimatedDrawingView extends StatefulWidget {
  final String json;
  final double? size;

  /// Optional fixed duration (mainly for tests). When null the duration is
  /// scaled by the drawing's total point count within ~1.6–2.2s.
  final Duration? duration;

  const AnimatedDrawingView({
    super.key,
    required this.json,
    this.size,
    this.duration,
  });

  @override
  State<AnimatedDrawingView> createState() => _AnimatedDrawingViewState();
}

class _AnimatedDrawingViewState extends State<AnimatedDrawingView>
    with SingleTickerProviderStateMixin {
  late List<DrawingStroke> _strokes;
  late int _totalPoints;
  late final AnimationController _controller;
  late final Animation<double> _progress;

  static Duration _durationFor(int points) {
    // Small doodles get the floor; dense drawings stretch toward the cap so
    // playback never drags.
    final ms = (1600 + points * 2).clamp(1600, 2200);
    return Duration(milliseconds: ms);
  }

  void _load() {
    _strokes = parseStrokes(widget.json);
    _totalPoints = totalStrokePoints(_strokes);
  }

  @override
  void initState() {
    super.initState();
    _load();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration ?? _durationFor(_totalPoints),
    );
    _progress = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubic,
    );
    _controller.forward();
  }

  @override
  void didUpdateWidget(AnimatedDrawingView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.json != widget.json) {
      _load();
      _controller.duration = widget.duration ?? _durationFor(_totalPoints);
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canvas = AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.black12),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: AnimatedBuilder(
          animation: _progress,
          builder: (context, _) => CustomPaint(
            painter: StrokePlaybackPainter(
              _strokes,
              pointBudget: (_progress.value * _totalPoints).ceil(),
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    if (widget.size != null) {
      return SizedBox(width: widget.size, height: widget.size, child: canvas);
    }
    return canvas;
  }
}

/// Paints stored strokes. When [pointBudget] is non-null only the first
/// [pointBudget] points — cumulative across strokes, in draw order — are
/// rendered: complete strokes up to the cutoff, then a partial polyline for
/// the one in flight. A null budget draws everything (static rendering).
class StrokePlaybackPainter extends CustomPainter {
  final List<DrawingStroke> strokes;
  final int? pointBudget;

  StrokePlaybackPainter(this.strokes, {this.pointBudget});

  @override
  void paint(Canvas canvas, Size size) {
    var remaining = pointBudget;
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;

      var points = stroke.points;
      if (remaining != null) {
        if (remaining <= 0) break;
        if (points.length > remaining) points = points.sublist(0, remaining);
        remaining -= points.length;
      }

      final paint = Paint()
        ..color = Color(stroke.color)
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      Offset denorm(Offset p) => Offset(p.dx * size.width, p.dy * size.height);

      if (points.length == 1) {
        // A single tap → a dot.
        canvas.drawPoints(
          PointMode.points,
          [denorm(points.first)],
          paint..strokeCap = StrokeCap.round,
        );
        continue;
      }
      final path = Path()
        ..moveTo(denorm(points.first).dx, denorm(points.first).dy);
      for (var i = 1; i < points.length; i++) {
        final p = denorm(points[i]);
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(StrokePlaybackPainter oldDelegate) =>
      oldDelegate.strokes != strokes || oldDelegate.pointBudget != pointBudget;
}
