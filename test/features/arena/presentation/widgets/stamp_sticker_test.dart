import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/features/arena/presentation/widgets/stamp_sticker.dart';

void main() {
  testWidgets('renders the stamp text', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: StampSticker('NAILED IT'))),
    );

    expect(find.text('NAILED IT'), findsOneWidget);
  });

  testWidgets('is rotated', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: StampSticker('ART'))),
    );

    expect(
      find.descendant(
        of: find.byType(StampSticker),
        matching: find.byType(Transform),
      ),
      findsOneWidget,
    );
  });
}
