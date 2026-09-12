import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/features/arena/presentation/widgets/post_badge.dart';

void main() {
  testWidgets('renders its label and color', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PostBadge('LATE', Colors.red)),
      ),
    );

    expect(find.text('LATE'), findsOneWidget);
    final container = tester.widget<Container>(find.byType(Container));
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.color, Colors.red);
  });

  testWidgets('HOUSE badge renders', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PostBadge('HOUSE', Colors.grey)),
      ),
    );

    expect(find.text('HOUSE'), findsOneWidget);
  });
}
