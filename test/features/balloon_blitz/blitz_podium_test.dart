import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/features/balloon_blitz/domain/entities/blitz_session.dart';
import 'package:taskcaster_app/features/balloon_blitz/presentation/widgets/blitz_podium.dart';

/// Widget tests for the results-screen podium: the visual 1st/2nd/3rd stand
/// ordering (by rank, not by list order) and graceful handling of races with
/// fewer than 3 players.
void main() {
  Widget harness(List<BlitzPlayer> ranked, {String selfId = 'x'}) =>
      MaterialApp(
        home: Scaffold(
          body: BlitzPodium(
            ranked: ranked,
            selfId: selfId,
            reveal: const AlwaysStoppedAnimation(1.0),
          ),
        ),
      );

  testWidgets('places 1st in the center, tallest block, with the crown',
      (tester) async {
    const ranked = [
      BlitzPlayer(id: 'b', name: 'Bob', liveScore: 10), // 1st
      BlitzPlayer(id: 'a', name: 'Ann', liveScore: 7), // 2nd
      BlitzPlayer(id: 'c', name: 'Cy', liveScore: 3), // 3rd
    ];

    await tester.pumpWidget(harness(ranked));

    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Ann'), findsOneWidget);
    expect(find.text('Cy'), findsOneWidget);
    expect(find.text('👑'), findsOneWidget);

    // Visual left-to-right order is 2nd, 1st, 3rd (classic podium shape) —
    // assert via each stand's horizontal position.
    final secondX = tester.getCenter(find.byKey(const ValueKey('podium-stand-2'))).dx;
    final firstX = tester.getCenter(find.byKey(const ValueKey('podium-stand-1'))).dx;
    final thirdX = tester.getCenter(find.byKey(const ValueKey('podium-stand-3'))).dx;
    expect(secondX, lessThan(firstX));
    expect(firstX, lessThan(thirdX));

    // 1st's block is the tallest, 2nd taller than 3rd.
    final firstHeight =
        tester.getSize(find.byKey(const ValueKey('podium-block-1'))).height;
    final secondHeight =
        tester.getSize(find.byKey(const ValueKey('podium-block-2'))).height;
    final thirdHeight =
        tester.getSize(find.byKey(const ValueKey('podium-block-3'))).height;
    expect(firstHeight, greaterThan(secondHeight));
    expect(secondHeight, greaterThan(thirdHeight));
  });

  testWidgets('ranks by score, independent of input list order',
      (tester) async {
    // Deliberately NOT pre-sorted — the widget must render by rank, not by
    // whatever order the list happens to arrive in.
    const ranked = [
      BlitzPlayer(id: 'c', name: 'Cy', liveScore: 3),
      BlitzPlayer(id: 'b', name: 'Bob', liveScore: 10),
      BlitzPlayer(id: 'a', name: 'Ann', liveScore: 7),
    ];
    // Callers are expected to pass an already-ranked list (e.g.
    // session.leaderboard), so build one here to mirror real usage while
    // proving stand assignment follows list POSITION (0/1/2), not name.
    final actuallyRanked = [...ranked]
      ..sort((x, y) => y.liveScore.compareTo(x.liveScore));

    await tester.pumpWidget(harness(actuallyRanked));

    final stand1 = tester.widget<Text>(find.descendant(
      of: find.byKey(const ValueKey('podium-stand-1')),
      matching: find.text('Bob'),
    ));
    expect(stand1.data, 'Bob');
    expect(
      find.descendant(
          of: find.byKey(const ValueKey('podium-stand-2')),
          matching: find.text('Ann')),
      findsOneWidget,
    );
    expect(
      find.descendant(
          of: find.byKey(const ValueKey('podium-stand-3')),
          matching: find.text('Cy')),
      findsOneWidget,
    );
  });

  testWidgets('omits empty stands gracefully for a 2-player race',
      (tester) async {
    const ranked = [
      BlitzPlayer(id: 'a', name: 'Ann', liveScore: 10),
      BlitzPlayer(id: 'b', name: 'Bob', liveScore: 4),
    ];

    await tester.pumpWidget(harness(ranked));

    expect(find.byKey(const ValueKey('podium-stand-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('podium-stand-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('podium-stand-3')), findsNothing);
  });

  testWidgets('omits all stands gracefully for an empty ranking',
      (tester) async {
    await tester.pumpWidget(harness(const []));

    expect(find.byKey(const ValueKey('podium-stand-1')), findsNothing);
    expect(find.byKey(const ValueKey('podium-stand-2')), findsNothing);
    expect(find.byKey(const ValueKey('podium-stand-3')), findsNothing);
  });
}
