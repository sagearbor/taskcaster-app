import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/models/game.dart';
import 'package:taskcaster_app/core/models/game_settings.dart';
import 'package:taskcaster_app/core/models/player.dart';
import 'package:taskcaster_app/core/theme/app_theme.dart';
import 'package:taskcaster_app/features/home/presentation/widgets/game_card.dart';

import '../../../games/presentation/widgets/starter_recap_fixture.dart';

Game _friendGame(int players) => Game(
      id: 'g1',
      gameName: 'Friday Face-Off',
      creatorId: 'a',
      judgeId: 'a',
      status: GameStatus.inProgress,
      inviteCode: 'ABC234',
      createdAt: DateTime(2026, 11, 9),
      players: [
        for (var i = 0; i < players; i++)
          Player(userId: 'p$i', displayName: 'Player $i', totalScore: 0),
      ],
      tasks: const [],
      settings: const GameSettings(),
    );

Future<void> _pump(WidgetTester tester, Game game) async {
  tester.view.physicalSize = const Size(360 * 2, 640 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [GameCard(game: game, onTap: () {})],
      ),
    ),
  ));
}

void main() {
  test('players label pluralizes', () {
    expect(GameCard.playersLabel(1), '1 player');
    expect(GameCard.playersLabel(0), '0 players');
    expect(GameCard.playersLabel(3), '3 players');
  });

  testWidgets('a one-player friend game says "1 player"', (tester) async {
    await _pump(tester, _friendGame(1));
    expect(find.text('1 player'), findsOneWidget);
    expect(find.text('1 players'), findsNothing);
  });

  testWidgets('the starter card shows graded count and points, no Guest chip',
      (tester) async {
    final game = recapFixture().game.copyWith(players: const [
      Player(userId: recapMe, displayName: 'Guest', totalScore: 0),
    ]);
    await _pump(tester, game);
    expect(find.text('3 of 10 graded · 22 pts'), findsOneWidget);
    expect(find.textContaining('players'), findsNothing);
    expect(find.text('Guest'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
