import 'dart:convert';
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';

/// Background colour of the drawing canvas. Also the colour the eraser
/// "paints" with — erasing is just overdrawing with the background, the
/// simplest correct approach given strokes are additive (drawn in order,
/// never deleted from the middle of the list).
const Color kCanvasBackgroundColor = Colors.white;

/// Stroke width used before brush sizes existed, and the fallback for
/// strokes whose serialized form has no `w` field (see [DrawingStroke]).
const double kLegacyStrokeWidth = 3.5;

/// The 3 selectable brush sizes.
enum BrushSize { thin, medium, thick }

const Map<BrushSize, double> kBrushWidths = {
  BrushSize.thin: 3.0,
  BrushSize.medium: 6.0,
  BrushSize.thick: 12.0,
};

/// Deliberately fatter than the largest brush so an eraser stroke reliably
/// covers whatever it's overdrawing.
const double kEraserWidth = 22.0;

/// One pen stroke. Points are stored NORMALISED to 0..1 of the canvas so a
/// drawing renders identically at any size / on any device.
///
/// [width] is an ADDITIVE, backward-compatible field on the wire format: the
/// core shape (`{'c': colorInt, 'p': [x,y,...]}`) is unchanged, 'w' is new
/// and optional. A drawing serialized by an older build simply has no 'w'
/// key, and [DrawingStroke.fromJson] falls back to [kLegacyStrokeWidth] for
/// it, so old offline-peer drawings keep parsing and rendering exactly as
/// they did before. A newer build's drawing sent to an older peer still
/// parses fine too — the older `fromJson` only reads 'c' and 'p' and ignores
/// unknown keys. Nothing about submission/serialization structurally changes.
class DrawingStroke {
  final int color;
  final List<Offset> points;
  final double width;

  DrawingStroke(this.color, this.points, {double? width})
      : width = width ?? kLegacyStrokeWidth;

  Map<String, dynamic> toJson() => {
        'c': color,
        'p': [for (final pt in points) ...[pt.dx, pt.dy]],
        'w': width,
      };

  factory DrawingStroke.fromJson(Map<String, dynamic> map) {
    final flat = (map['p'] as List).cast<num>();
    final pts = <Offset>[];
    for (var i = 0; i + 1 < flat.length; i += 2) {
      pts.add(Offset(flat[i].toDouble(), flat[i + 1].toDouble()));
    }
    final w = (map['w'] as num?)?.toDouble();
    return DrawingStroke((map['c'] as num).toInt(), pts, width: w);
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

/// A quadratic Bézier segment: from the current path position, curve through
/// [control] and end at [end].
class QuadSegment {
  final Offset control;
  final Offset end;
  const QuadSegment(this.control, this.end);

  @override
  bool operator ==(Object other) =>
      other is QuadSegment && other.control == control && other.end == end;

  @override
  int get hashCode => Object.hash(control, end);

  @override
  String toString() => 'QuadSegment($control -> $end)';
}

/// The standard "smoothing via midpoints" technique: for a polyline of raw
/// sampled points, curve through each point using the midpoint of it and its
/// successor as the curve's endpoint. This keeps the curve anchored close to
/// every sample while removing the faceted look of point-to-point lines.
///
/// Split out from [smoothStrokePath] so the midpoint math is unit-testable
/// without touching `dart:ui`'s [Path]. Assumes at least 3 points — callers
/// must special-case 0/1/2-point strokes themselves (there aren't enough
/// points to form a meaningful curve in those cases).
List<QuadSegment> smoothingSegments(List<Offset> points) {
  assert(points.length >= 3);
  return [
    for (var i = 1; i < points.length - 1; i++)
      QuadSegment(
        points[i],
        Offset(
          (points[i].dx + points[i + 1].dx) / 2,
          (points[i].dy + points[i + 1].dy) / 2,
        ),
      ),
  ];
}

/// Builds a smooth [Path] through [points] (already in the coordinate space
/// to be painted in — callers denormalise first).
///
/// Degenerate cases:
///  - 0 points: empty path (caller should skip drawing this stroke).
///  - 1 point: a path sitting at that single point (caller draws a dot).
///  - 2 points: a straight line — not enough points to curve.
///  - 3+ points: quadratic Béziers through [smoothingSegments], with a final
///    straight segment to the last raw point so the curve always reaches
///    where the stroke actually ended.
Path smoothStrokePath(List<Offset> points) {
  final path = Path();
  if (points.isEmpty) return path;
  path.moveTo(points.first.dx, points.first.dy);
  if (points.length <= 2) {
    path.lineTo(points.last.dx, points.last.dy);
    return path;
  }
  for (final seg in smoothingSegments(points)) {
    path.quadraticBezierTo(seg.control.dx, seg.control.dy, seg.end.dx, seg.end.dy);
  }
  path.lineTo(points.last.dx, points.last.dy);
  return path;
}

/// Holds the in-progress drawing for [DrawingCanvas].
class DrawingController extends ChangeNotifier {
  final List<DrawingStroke> _strokes = [];
  Color color = Colors.black;
  BrushSize brushSize = BrushSize.medium;
  bool eraserActive = false;

  List<DrawingStroke> get strokes => List.unmodifiable(_strokes);

  bool get isEmpty => _strokes.every((s) => s.points.isEmpty);

  double get _activeWidth =>
      eraserActive ? kEraserWidth : kBrushWidths[brushSize]!;

  int get _activeColor =>
      eraserActive ? kCanvasBackgroundColor.value : color.value;

  void selectColor(Color c) {
    color = c;
    eraserActive = false;
    notifyListeners();
  }

  void selectBrushSize(BrushSize size) {
    brushSize = size;
    notifyListeners();
  }

  void toggleEraser() {
    eraserActive = !eraserActive;
    notifyListeners();
  }

  void startStroke(Offset normalized) {
    _strokes.add(
      DrawingStroke(_activeColor, [normalized], width: _activeWidth),
    );
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
                  color: kCanvasBackgroundColor,
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
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                          color: !controller.eraserActive &&
                                  controller.color == c
                              ? Colors.amber
                              : Colors.black26,
                          width: !controller.eraserActive &&
                                  controller.color == c
                              ? 3
                              : 1,
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
          const SizedBox(height: 10),
          Row(
            children: [
              for (final size in BrushSize.values)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: _BrushSizeButton(
                    size: size,
                    selected:
                        !controller.eraserActive && controller.brushSize == size,
                    onTap: () => controller.selectBrushSize(size),
                  ),
                ),
              const SizedBox(width: 6),
              _EraserButton(
                active: controller.eraserActive,
                onTap: controller.toggleEraser,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A compact, kid-friendly (44x44 tap target) brush-size selector button. The
/// dot inside grows with the brush's stroke width so the size is obvious at a
/// glance.
class _BrushSizeButton extends StatelessWidget {
  final BrushSize size;
  final bool selected;
  final VoidCallback onTap;

  const _BrushSizeButton({
    required this.size,
    required this.selected,
    required this.onTap,
  });

  static const Map<BrushSize, String> _labels = {
    BrushSize.thin: 'Thin brush',
    BrushSize.medium: 'Medium brush',
    BrushSize.thick: 'Thick brush',
  };

  @override
  Widget build(BuildContext context) {
    final dotDiameter = kBrushWidths[size]! + 6;
    return Tooltip(
      message: _labels[size]!,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: selected ? Colors.amber.withOpacity(0.25) : null,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? Colors.amber : Colors.black26,
              width: selected ? 3 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: Container(
            width: dotDiameter,
            height: dotDiameter,
            decoration: const BoxDecoration(
              color: Colors.black87,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

/// Kid-friendly (44x44 tap target) eraser toggle. Mirrors the visual style of
/// [_BrushSizeButton] (circular, amber highlight when active).
class _EraserButton extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;

  const _EraserButton({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Eraser',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: active ? Colors.amber.withOpacity(0.25) : null,
            shape: BoxShape.circle,
            border: Border.all(
              color: active ? Colors.amber : Colors.black26,
              width: active ? 3 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.auto_fix_high,
            color: active ? Colors.amber.shade800 : Colors.black54,
          ),
        ),
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
          color: kCanvasBackgroundColor,
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
          color: kCanvasBackgroundColor,
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
///
/// Each stroke is rendered as a smooth curve (see [smoothStrokePath]) rather
/// than raw point-to-point lines; the underlying [DrawingStroke.points] are
/// untouched; smoothing only ever happens here, at paint time.
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
        ..strokeWidth = stroke.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      Offset denorm(Offset p) => Offset(p.dx * size.width, p.dy * size.height);

      if (points.length == 1) {
        // A single tap → a dot.
        canvas.drawPoints(
          PointMode.points,
          [denorm(points.first)],
          paint,
        );
        continue;
      }
      final path = smoothStrokePath([for (final p in points) denorm(p)]);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(StrokePlaybackPainter oldDelegate) =>
      oldDelegate.strokes != strokes || oldDelegate.pointBudget != pointBudget;
}
