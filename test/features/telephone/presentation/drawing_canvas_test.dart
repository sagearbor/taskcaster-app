import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/features/telephone/presentation/widgets/drawing_canvas.dart';

void main() {
  group('smoothingSegments (midpoint math)', () {
    test('3 points produces exactly 1 segment through the midpoint', () {
      const points = [Offset(0, 0), Offset(10, 0), Offset(10, 10)];
      final segments = smoothingSegments(points);

      expect(segments, hasLength(1));
      expect(segments.single.control, const Offset(10, 0));
      expect(segments.single.end, const Offset(10, 5)); // midpoint of p1, p2
    });

    test('n points produces n-2 segments, each anchored at the midpoint of '
        'consecutive raw points', () {
      const points = [
        Offset(0, 0),
        Offset(2, 0),
        Offset(4, 4),
        Offset(8, 8),
        Offset(10, 0),
      ];
      final segments = smoothingSegments(points);

      expect(segments, hasLength(points.length - 2));
      expect(segments[0].control, const Offset(2, 0));
      expect(segments[0].end, const Offset(3, 2)); // mid(p1, p2)
      expect(segments[1].control, const Offset(4, 4));
      expect(segments[1].end, const Offset(6, 6)); // mid(p2, p3)
      expect(segments[2].control, const Offset(8, 8));
      expect(segments[2].end, const Offset(9, 4)); // mid(p3, p4)
    });

    test('asserts when given fewer than 3 points', () {
      expect(() => smoothingSegments(const [Offset(0, 0), Offset(1, 1)]),
          throwsA(isA<AssertionError>()));
    });
  });

  group('smoothStrokePath degenerate cases', () {
    test('0 points -> empty path (no subpaths)', () {
      final path = smoothStrokePath(const []);
      expect(path.computeMetrics(), isEmpty);
    });

    test('1 point -> a zero-length path sitting at that point', () {
      final path = smoothStrokePath(const [Offset(5, 5)]);
      // A single point yields a degenerate (zero-area) path anchored at that
      // point. (The painter never draws 1-point strokes via smoothStrokePath —
      // it renders a round dot instead — but the path must still be sane.)
      expect(path.getBounds(), const Rect.fromLTWH(5, 5, 0, 0));
      final totalLength =
          path.computeMetrics().fold<double>(0, (n, m) => n + m.length);
      expect(totalLength, 0);
    });

    test('2 points -> a straight line between them', () {
      final path = smoothStrokePath(const [Offset(0, 0), Offset(10, 0)]);
      final metrics = path.computeMetrics().toList();
      expect(metrics, hasLength(1));
      expect(metrics.single.length, closeTo(10, 0.001));
    });

    test('3+ points -> a single continuous curve reaching the last point',
        () {
      const points = [
        Offset(0, 0),
        Offset(10, 0),
        Offset(10, 10),
        Offset(0, 10),
      ];
      final path = smoothStrokePath(points);
      final metrics = path.computeMetrics().toList();
      expect(metrics, hasLength(1));
      // A curved path anchored near each raw point must be at least as long
      // as the straight-line polyline distance it's smoothing.
      expect(metrics.single.length, greaterThan(20));
      final tangent = metrics.single.getTangentForOffset(metrics.single.length);
      expect(tangent!.position.dx, closeTo(0, 0.5));
      expect(tangent.position.dy, closeTo(10, 0.5));
    });
  });

  group('DrawingStroke backward compatibility', () {
    test('round-trips width through toJson/fromJson', () {
      final stroke = DrawingStroke(0xFF000000, [const Offset(0.1, 0.2)],
          width: 12.0);
      final decoded = DrawingStroke.fromJson(stroke.toJson());
      expect(decoded.width, 12.0);
      expect(decoded.color, 0xFF000000);
    });

    test('legacy JSON with no "w" key falls back to kLegacyStrokeWidth', () {
      final legacyJson = {
        'c': 0xFFE53935,
        'p': [0.1, 0.1, 0.2, 0.2],
      };
      final decoded = DrawingStroke.fromJson(legacyJson);
      expect(decoded.width, kLegacyStrokeWidth);
      expect(decoded.points, [const Offset(0.1, 0.1), const Offset(0.2, 0.2)]);
    });

    test('parseStrokes still parses a legacy (no width) drawing document',
        () {
      const legacyDrawing =
          '[{"c":4278190080,"p":[0.1,0.1,0.2,0.2,0.3,0.3,0.4,0.4]}]';
      final strokes = parseStrokes(legacyDrawing);
      expect(strokes, hasLength(1));
      expect(strokes.single.width, kLegacyStrokeWidth);
      expect(strokes.single.color, 4278190080);
    });

    test('toJson always includes a "w" key alongside the unchanged "c"/"p" '
        'shape', () {
      final stroke = DrawingStroke(0xFF000000, [const Offset(0, 0)]);
      final json = stroke.toJson();
      expect(json.keys, containsAll(['c', 'p', 'w']));
    });
  });

  group('DrawingController brush size & eraser', () {
    test('new strokes use the selected brush size, past strokes unaffected',
        () {
      final controller = DrawingController();
      controller.startStroke(const Offset(0.1, 0.1));
      expect(controller.strokes.single.width, kBrushWidths[BrushSize.medium]);

      controller.selectBrushSize(BrushSize.thick);
      controller.startStroke(const Offset(0.2, 0.2));

      expect(controller.strokes[0].width, kBrushWidths[BrushSize.medium]);
      expect(controller.strokes[1].width, kBrushWidths[BrushSize.thick]);
    });

    test('eraser strokes use the background colour and eraser width', () {
      final controller = DrawingController()..selectColor(Colors.red);
      controller.toggleEraser();
      controller.startStroke(const Offset(0.5, 0.5));

      final stroke = controller.strokes.single;
      expect(stroke.color, kCanvasBackgroundColor.value);
      expect(stroke.width, kEraserWidth);
    });

    test('selecting a colour turns the eraser back off', () {
      final controller = DrawingController()..toggleEraser();
      expect(controller.eraserActive, isTrue);
      controller.selectColor(Colors.blue);
      expect(controller.eraserActive, isFalse);
    });

    test('undo removes only the last stroke', () {
      final controller = DrawingController()
        ..startStroke(const Offset(0, 0))
        ..startStroke(const Offset(1, 1));
      expect(controller.strokes, hasLength(2));
      controller.undo();
      expect(controller.strokes, hasLength(1));
      expect(controller.strokes.single.points, [const Offset(0, 0)]);
    });
  });

  group('hasVisibleInk (the "Draw something first!" submit guard)', () {
    test('a fresh canvas has no visible ink', () {
      expect(DrawingController().hasVisibleInk, isFalse);
    });

    test('an eraser-only scribble on a blank canvas is NOT visible ink', () {
      // The bug: eraser strokes have points + a (background) colour, so the
      // old isEmpty-based guard treated an eraser-only canvas as "drawn on"
      // and let a blank submission through.
      final controller = DrawingController()..toggleEraser();
      controller.startStroke(const Offset(0.4, 0.4));
      controller.appendPoint(const Offset(0.5, 0.5));

      expect(controller.eraserActive, isTrue);
      expect(controller.isEmpty, isFalse,
          reason: 'the eraser stroke has points');
      expect(controller.hasVisibleInk, isFalse,
          reason: 'but an eraser leaves no ink on a blank canvas');
    });

    test('a single pen stroke IS visible ink', () {
      final controller = DrawingController();
      controller.startStroke(const Offset(0.2, 0.2));
      expect(controller.hasVisibleInk, isTrue);
    });

    test('pen ink under later eraser strokes still counts as visible', () {
      final controller = DrawingController();
      controller.startStroke(const Offset(0.2, 0.2)); // pen
      controller.toggleEraser();
      controller.startStroke(const Offset(0.3, 0.3)); // eraser over it
      expect(controller.hasVisibleInk, isTrue);
    });

    test('the eraser flag is authoring-only — never serialized', () {
      final controller = DrawingController()..toggleEraser();
      controller.startStroke(const Offset(0.1, 0.1));
      final json = controller.toJson();
      // Round-trips as an ordinary background-coloured stroke; nothing marks it
      // as an eraser on the wire, and a re-parsed stroke is not an eraser.
      final parsed = parseStrokes(json).single;
      expect(parsed.isEraser, isFalse);
      expect(parsed.color, kCanvasBackgroundColor.value);
      expect(parsed.width, kEraserWidth);
    });
  });

  group('DrawingCanvas widget toolbar', () {
    Future<DrawingController> pumpCanvas(WidgetTester tester) async {
      final controller = DrawingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 700,
              child: SingleChildScrollView(
                child: DrawingCanvas(controller: controller),
              ),
            ),
          ),
        ),
      );
      return controller;
    }

    Future<void> drawStroke(WidgetTester tester) async {
      final canvasCenter = tester.getCenter(
        find
            .descendant(
              of: find.byType(DrawingCanvas),
              matching: find.byType(CustomPaint),
            )
            .first,
      );
      final gesture = await tester.startGesture(canvasCenter);
      await gesture.moveBy(const Offset(40, 10));
      await gesture.moveBy(const Offset(10, 40));
      await gesture.up();
      await tester.pump();
    }

    testWidgets(
        'tapping the thick brush affects new strokes only, not existing ones',
        (tester) async {
      final controller = await pumpCanvas(tester);

      await drawStroke(tester);
      expect(controller.strokes, hasLength(1));
      expect(controller.strokes[0].width, kBrushWidths[BrushSize.medium]);

      await tester.tap(find.byTooltip('Thick brush'));
      await tester.pump();
      await drawStroke(tester);

      expect(controller.strokes, hasLength(2));
      // Old stroke untouched, new stroke thick.
      expect(controller.strokes[0].width, kBrushWidths[BrushSize.medium]);
      expect(controller.strokes[1].width, kBrushWidths[BrushSize.thick]);
    });

    testWidgets(
        'toggling the eraser affects new strokes only, and colours turn it off',
        (tester) async {
      final controller = await pumpCanvas(tester);

      await drawStroke(tester);
      expect(controller.strokes[0].color, Colors.black.value);

      await tester.tap(find.byTooltip('Eraser'));
      await tester.pump();
      await drawStroke(tester);

      expect(controller.strokes, hasLength(2));
      expect(controller.strokes[0].color, Colors.black.value,
          reason: 'existing stroke keeps its pen colour');
      expect(controller.strokes[1].color, kCanvasBackgroundColor.value);
      expect(controller.strokes[1].width, kEraserWidth);

      // Picking a colour switches back to pen mode.
      await tester.tap(find.byTooltip('Undo')); // remove eraser stroke
      await tester.pump();
      expect(controller.eraserActive, isTrue);
      controller.selectColor(Colors.black);
      await tester.pump();
      await drawStroke(tester);
      expect(controller.strokes.last.color, Colors.black.value);
      expect(controller.strokes.last.width, kBrushWidths[BrushSize.medium]);
    });

    testWidgets('undo button removes the last stroke', (tester) async {
      final controller = await pumpCanvas(tester);
      await drawStroke(tester);
      await drawStroke(tester);
      expect(controller.strokes, hasLength(2));

      await tester.tap(find.byTooltip('Undo'));
      await tester.pump();
      expect(controller.strokes, hasLength(1));
    });

    testWidgets('brush size and eraser buttons meet the 44px tap target',
        (tester) async {
      await pumpCanvas(tester);
      for (final tooltip in ['Thin brush', 'Medium brush', 'Thick brush', 'Eraser']) {
        final size = tester.getSize(
          find.descendant(
            of: find.byTooltip(tooltip),
            matching: find.byType(Container),
          ).first,
        );
        expect(size.width, greaterThanOrEqualTo(44), reason: tooltip);
        expect(size.height, greaterThanOrEqualTo(44), reason: tooltip);
      }
    });
  });
}
