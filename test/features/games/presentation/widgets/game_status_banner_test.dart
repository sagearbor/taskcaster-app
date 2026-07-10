import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/models/game.dart';
import 'package:taskcaster_app/core/models/game_settings.dart';
import 'package:taskcaster_app/core/models/player.dart';
import 'package:taskcaster_app/core/models/player_task_status.dart';
import 'package:taskcaster_app/core/models/task.dart';
import 'package:taskcaster_app/features/games/presentation/widgets/game_status_banner.dart';

/// A House Hunt-style game: judgePlays=false, so the judge (the hider) is never
/// seeded a per-task status and only the seeker(s) submit.
Game _hunt({
  required Map<String, PlayerTaskStatus> statuses,
  TaskStatus taskStatus = TaskStatus.waiting_for_submissions,
  List<Player>? players,
}) {
  return Game(
    id: 'g1',
    gameName: "Wanda's House Hunt",
    creatorId: 'judge',
    judgeId: 'judge',
    status: GameStatus.inProgress,
    inviteCode: 'ABC234',
    createdAt: DateTime(2026, 7, 1),
    players: players ??
        const [
          Player(userId: 'judge', displayName: 'Hider Hank', totalScore: 0),
          Player(userId: 'seeker', displayName: 'Seeker Sue', totalScore: 0),
        ],
    tasks: [
      Task(
        id: 't1',
        title: 'Find your oldest book',
        description: 'Hunt!',
        taskType: TaskType.video,
        submissions: const [],
        status: taskStatus,
        playerStatuses: statuses,
      ),
    ],
    settings: const GameSettings(judgePlays: false),
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required Game game,
  required String currentUserId,
  required bool isJudge,
  VoidCallback? onAction,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: GameStatusBanner(
          game: game,
          currentUserId: currentUserId,
          isJudge: isJudge,
          onAction: onAction,
        ),
      ),
    ),
  );
}

void main() {
  group('GameStatusBanner — non-playing judge (judgePlays=false)', () {
    testWidgets(
        'shows "Ready to judge!" once the seeker has submitted, driven by task '
        'state not the judge status', (tester) async {
      var actioned = false;
      final game = _hunt(
        statuses: {
          'seeker': const PlayerTaskStatus(
            playerId: 'seeker',
            state: TaskPlayerState.submitted,
          ),
        },
      );

      await _pump(
        tester,
        game: game,
        currentUserId: 'judge',
        isJudge: true,
        onAction: () => actioned = true,
      );

      expect(find.text('Ready to judge!'), findsOneWidget);
      // The action is present and wired (the ONLY route into JudgingScreen).
      expect(find.text('Judge'), findsOneWidget);
      await tester.tap(find.text('Judge'));
      expect(actioned, isTrue);
    });

    testWidgets('shows a "Waiting for the seeker…" info banner with no action '
        'before the seeker submits', (tester) async {
      final game = _hunt(
        statuses: {
          'seeker': const PlayerTaskStatus(
            playerId: 'seeker',
            state: TaskPlayerState.not_started,
          ),
        },
      );

      await _pump(
        tester,
        game: game,
        currentUserId: 'judge',
        isJudge: true,
      );

      expect(find.textContaining('Waiting for the seeker'), findsOneWidget);
      // No actionable button (must never open the seeker's submit UI).
      expect(find.text('Judge'), findsNothing);
      expect(find.byType(TextButton), findsNothing);
    });
  });

  group('GameStatusBanner — waiting count denominator', () {
    testWidgets(
        'counts expected submitters (playerStatuses), excluding the judge',
        (tester) async {
      // Two seekers expected to submit; the judge is NOT in playerStatuses.
      final game = _hunt(
        players: const [
          Player(userId: 'judge', displayName: 'Hider Hank', totalScore: 0),
          Player(userId: 'seekerA', displayName: 'Seeker A', totalScore: 0),
          Player(userId: 'seekerB', displayName: 'Seeker B', totalScore: 0),
        ],
        statuses: {
          'seekerA': const PlayerTaskStatus(
            playerId: 'seekerA',
            state: TaskPlayerState.submitted,
          ),
          'seekerB': const PlayerTaskStatus(
            playerId: 'seekerB',
            state: TaskPlayerState.not_started,
          ),
        },
      );

      await _pump(
        tester,
        game: game,
        currentUserId: 'seekerA',
        isJudge: false,
      );

      // 1 of 2 expected submitters — NOT 1/3 (players.length would include the
      // judge, making n/n unreachable).
      expect(find.textContaining('1/2 done'), findsOneWidget);
    });
  });
}
