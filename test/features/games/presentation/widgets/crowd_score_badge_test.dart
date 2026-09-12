import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/features/games/presentation/widgets/crowd_score_badge.dart';

void main() {
  testWidgets('shows "Waiting for the crowd" when ungraded', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: CrowdScoreBadge(crowdPoints: null)),
      ),
    );
    expect(find.text('Waiting for the crowd'), findsOneWidget);
  });

  testWidgets('shows the crowd score once graded', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: CrowdScoreBadge(crowdPoints: 7)),
      ),
    );
    expect(find.text('Crowd score: 7/10'), findsOneWidget);
  });
}
