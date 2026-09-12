import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/features/games/presentation/widgets/twist_banner.dart';

void main() {
  testWidgets('renders nothing for a null twist', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: TwistBanner(twist: null))),
    );
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('renders nothing for a blank twist', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: TwistBanner(twist: '   '))),
    );
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('shows the twist text once supplied', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: TwistBanner(twist: 'No hands in the photo')),
      ),
    );
    expect(find.text('No hands in the photo'), findsOneWidget);
    expect(find.byIcon(Icons.bolt), findsOneWidget);
  });
}
