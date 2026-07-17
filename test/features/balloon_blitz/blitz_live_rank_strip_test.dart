import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/features/balloon_blitz/domain/entities/blitz_session.dart';
import 'package:taskcaster_app/features/balloon_blitz/presentation/widgets/blitz_live_rank_strip.dart';

/// Widget tests for the always-visible in-race ranked strip: top 3 + you (if
/// you're outside the top 3), and that it updates cleanly when the session's
/// scores change out from under it.
void main() {
  BlitzSession sessionWith(List<BlitzPlayer> players) =>
      BlitzSession(hostId: players.first.id, players: players);

  Widget harness(BlitzSession session, String selfId) => MaterialApp(
        home: Scaffold(
          body: BlitzLiveRankStrip(session: session, selfId: selfId),
        ),
      );

  testWidgets('shows top 3 by score, highest first', (tester) async {
    final session = sessionWith(const [
      BlitzPlayer(id: 'a', name: 'Ann', liveScore: 3),
      BlitzPlayer(id: 'b', name: 'Bob', liveScore: 10),
      BlitzPlayer(id: 'c', name: 'Cy', liveScore: 7),
    ]);

    await tester.pumpWidget(harness(session, 'b'));

    expect(find.text('Ann'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Cy'), findsOneWidget);
    // No "outside top 3" extra chip / divider when self is already top 3.
    expect(find.byKey(const ValueKey('blitz-strip-self')), findsNothing);
  });

  testWidgets('shows top 3 + you when you are outside the top 3',
      (tester) async {
    final session = sessionWith(const [
      BlitzPlayer(id: 'a', name: 'Ann', liveScore: 20),
      BlitzPlayer(id: 'b', name: 'Bob', liveScore: 15),
      BlitzPlayer(id: 'c', name: 'Cy', liveScore: 10),
      BlitzPlayer(id: 'd', name: 'Di', liveScore: 5),
      BlitzPlayer(id: 'me', name: 'Me', liveScore: 1),
    ]);

    await tester.pumpWidget(harness(session, 'me'));

    // Top 3 present.
    expect(find.text('Ann'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Cy'), findsOneWidget);
    // 4th place omitted, self (5th) shown via the dedicated slot.
    expect(find.text('Di'), findsNothing);
    expect(find.text('Me'), findsOneWidget);
    expect(find.byKey(const ValueKey('blitz-strip-self')), findsOneWidget);
    // Self's numeric rank (5th) is rendered on its chip.
    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('updates rankings when the session changes', (tester) async {
    var session = sessionWith(const [
      BlitzPlayer(id: 'a', name: 'Ann', liveScore: 20),
      BlitzPlayer(id: 'b', name: 'Bob', liveScore: 15),
      BlitzPlayer(id: 'c', name: 'Cy', liveScore: 10),
      BlitzPlayer(id: 'd', name: 'Di', liveScore: 5),
      BlitzPlayer(id: 'me', name: 'Me', liveScore: 1),
    ]);

    await tester.pumpWidget(harness(session, 'me'));
    expect(find.byKey(const ValueKey('blitz-strip-self')), findsOneWidget);
    expect(find.text('Cy'), findsOneWidget);

    // "Me" pops a bunch of balloons and rockets into 2nd place — the strip
    // should now show me as part of the top 3 slots, with the extra "you"
    // chip gone, and Cy no longer visible.
    session = sessionWith(const [
      BlitzPlayer(id: 'a', name: 'Ann', liveScore: 20),
      BlitzPlayer(id: 'me', name: 'Me', liveScore: 18),
      BlitzPlayer(id: 'b', name: 'Bob', liveScore: 15),
      BlitzPlayer(id: 'c', name: 'Cy', liveScore: 10),
      BlitzPlayer(id: 'd', name: 'Di', liveScore: 5),
    ]);
    await tester.pumpWidget(harness(session, 'me'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const ValueKey('blitz-strip-self')), findsNothing);
    expect(find.text('Me'), findsOneWidget);
    expect(find.text('Cy'), findsNothing);
  });
}
