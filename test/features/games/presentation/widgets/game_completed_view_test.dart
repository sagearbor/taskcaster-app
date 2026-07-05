import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/models/game.dart';
import 'package:taskcaster_app/core/models/game_settings.dart';
import 'package:taskcaster_app/core/models/player.dart';
import 'package:taskcaster_app/core/models/task.dart';
import 'package:taskcaster_app/features/games/presentation/widgets/game_completed_view.dart';

Game _completedGame() {
  return Game(
    id: 'g1',
    gameName: 'Epic Party',
    creatorId: 'u1',
    judgeId: 'u2',
    status: GameStatus.completed,
    inviteCode: 'ABC234',
    createdAt: DateTime(2026, 7, 1),
    players: const [
      Player(userId: 'u2', displayName: 'Runner-up Rae', totalScore: 9),
      Player(userId: 'u1', displayName: 'Winner Wanda', totalScore: 14),
      Player(userId: 'u3', displayName: 'Third Theo', totalScore: 4),
    ],
    tasks: [
      Task(
        id: 't1',
        title: 'A task',
        description: 'desc',
        taskType: TaskType.video,
        submissions: const [],
      ),
    ],
    settings: GameSettings.quickPlay(),
  );
}

void main() {
  Future<void> pumpView(
    WidgetTester tester, {
    String? currentUserId,
    VoidCallback? onRematch,
  }) async {
    tester.view.physicalSize = const Size(800, 1500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GameCompletedView(
            game: _completedGame(),
            currentUserId: currentUserId,
            onRematch: onRematch,
          ),
        ),
      ),
    );
    // Run the full ceremony (trophy elastic-in, confetti, staggered
    // standings, score count-ups) to its resting state.
    await tester.pumpAndSettle();
  }

  testWidgets('reveals the winner with trophy and final score',
      (tester) async {
    await pumpView(tester, currentUserId: 'u1');

    expect(find.text('🎉 Winner! 🎉'), findsOneWidget);
    // Winner card + her standings row.
    expect(find.text('Winner Wanda'), findsNWidgets(2));
    // Score count-up has finished at the real total.
    expect(find.text('14 points'), findsOneWidget);
    expect(find.byIcon(Icons.emoji_events), findsWidgets);
    // The winner sees a personal cheer, not a placement.
    expect(find.text('That\'s you! 🎉'), findsOneWidget);
  });

  testWidgets('shows full standings sorted by score with counted-up totals',
      (tester) async {
    await pumpView(tester, currentUserId: 'u2');

    expect(find.text('Final Standings'), findsOneWidget);
    expect(find.text('Winner Wanda'), findsWidgets);
    expect(find.text('Runner-up Rae'), findsOneWidget);
    expect(find.text('Third Theo'), findsOneWidget);
    expect(find.text('14 pts'), findsOneWidget);
    expect(find.text('9 pts'), findsOneWidget);
    expect(find.text('4 pts'), findsOneWidget);
    // Ranks are ordered by score, and the viewer's row is marked.
    expect(find.text('Rank #2 · You'), findsOneWidget);
    expect(find.text('Rank #3'), findsOneWidget);
  });

  testWidgets('non-winner sees "You placed #N"', (tester) async {
    await pumpView(tester, currentUserId: 'u3');
    expect(find.text('You placed #3'), findsOneWidget);
  });

  testWidgets('rematch button fires the callback', (tester) async {
    var rematches = 0;
    await pumpView(tester, currentUserId: 'u2', onRematch: () => rematches++);

    final button = find.text('Rematch — same crew');
    expect(button, findsOneWidget);
    await tester.tap(button);
    expect(rematches, 1);
  });

  testWidgets('rematch button is hidden without a handler', (tester) async {
    await pumpView(tester, currentUserId: 'u2');
    expect(find.text('Rematch — same crew'), findsNothing);
  });
}
