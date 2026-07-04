import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/features/telephone/presentation/widgets/drawing_canvas.dart';

/// Two strokes, 4 + 2 = 6 points total. Colours are ARGB ints, the same
/// format [DrawingController.toJson] writes.
const _drawingJson =
    '[{"c":4278190080,"p":[0.1,0.1,0.2,0.2,0.3,0.3,0.4,0.4]},'
    '{"c":4294901760,"p":[0.5,0.5,0.6,0.6]}]';

StrokePlaybackPainter _painter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((w) => w.painter)
    .whereType<StrokePlaybackPainter>()
    .single;

void main() {
  group('AnimatedDrawingView', () {
    testWidgets('starts partial and reaches the full drawing at animation end',
        (tester) async {
      final totalPoints = totalStrokePoints(parseStrokes(_drawingJson));
      expect(totalPoints, 6, reason: 'fixture sanity check');

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AnimatedDrawingView(json: _drawingJson, size: 200),
          ),
        ),
      );

      // First frame: nothing (or almost nothing) is drawn yet.
      expect(_painter(tester).pointBudget, lessThan(totalPoints));

      // Mid-animation (duration is >= 1.6s): still progressive.
      await tester.pump(const Duration(milliseconds: 300));
      expect(_painter(tester).pointBudget, lessThan(totalPoints));

      // Run to completion: every recorded point is visible.
      await tester.pumpAndSettle();
      expect(_painter(tester).pointBudget, totalPoints);
    });

    testWidgets('respects an explicit duration override', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AnimatedDrawingView(
              json: _drawingJson,
              size: 200,
              duration: Duration(milliseconds: 100),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 150));
      expect(_painter(tester).pointBudget, 6);
    });

    testWidgets('tolerates empty / malformed drawing JSON', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AnimatedDrawingView(json: 'not json')),
        ),
      );
      await tester.pumpAndSettle();
      expect(_painter(tester).pointBudget, 0);
      expect(tester.takeException(), isNull);
    });
  });
}
