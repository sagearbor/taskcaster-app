import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/features/home/presentation/widgets/arena_entry_button.dart';

void main() {
  Widget wrap(Widget child) =>
      MaterialApp(home: Scaffold(body: Center(child: child)));

  testWidgets('shows the unread count as a badge', (tester) async {
    await tester.pumpWidget(wrap(ArenaEntryButton(onTap: () {}, unreadCount: 4)));

    expect(find.text('Arena — grade the crowd'), findsOneWidget);
    expect(find.text('4 new'), findsOneWidget);
    // Never a filled button: Home has exactly one primary action.
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(OutlinedButton), findsOneWidget);
  });

  testWidgets('a full page reads as N+', (tester) async {
    await tester.pumpWidget(
        wrap(ArenaEntryButton(onTap: () {}, unreadCount: 10, countCap: 10)));
    expect(find.text('10+ new'), findsOneWidget);
  });

  testWidgets('no badge when nothing is waiting or the count is unknown',
      (tester) async {
    await tester.pumpWidget(wrap(ArenaEntryButton(onTap: () {}, unreadCount: 0)));
    expect(find.byKey(const Key('arena-unread-badge')), findsNothing);

    await tester.pumpWidget(wrap(ArenaEntryButton(onTap: () {})));
    expect(find.byKey(const Key('arena-unread-badge')), findsNothing);
  });

  testWidgets('a zero-post viewer gets the tease label', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
        wrap(ArenaEntryButton(onTap: () => tapped = true, tease: true)));

    expect(find.text('Arena — see how others did'), findsOneWidget);
    await tester.tap(find.byType(OutlinedButton));
    expect(tapped, isTrue);
  });
}
