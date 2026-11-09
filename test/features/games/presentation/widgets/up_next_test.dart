import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/models/game.dart';
import 'package:taskcaster_app/core/models/game_settings.dart';
import 'package:taskcaster_app/core/models/player.dart';
import 'package:taskcaster_app/core/models/player_task_status.dart';
import 'package:taskcaster_app/core/models/task.dart';
import 'package:taskcaster_app/core/theme/app_theme.dart';
import 'package:taskcaster_app/features/games/presentation/bloc/judging_bloc.dart';
import 'package:taskcaster_app/features/games/presentation/widgets/up_next_card.dart';

PlayerTaskStatus _s(String id, TaskPlayerState state, {int? score}) =>
    PlayerTaskStatus(playerId: id, state: state, score: score);

Game _game({
  required Map<String, PlayerTaskStatus> statuses,
  TaskStatus taskStatus = TaskStatus.waiting_for_submissions,
  bool judgePlays = true,
  bool crowdJudged = false,
  List<Player>? players,
  DateTime? deadline,
}) {
  return Game(
    id: 'g1',
    gameName: 'Friday Face-Off',
    creatorId: 'judge',
    judgeId: 'judge',
    status: GameStatus.inProgress,
    inviteCode: 'ABC234',
    createdAt: DateTime(2026, 7, 1),
    players: players ??
        const [
          Player(userId: 'judge', displayName: 'Hank', totalScore: 0),
          Player(userId: 'p1', displayName: 'Sue', totalScore: 0),
          Player(userId: 'p2', displayName: 'Raj', totalScore: 0),
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
        deadline: deadline,
      ),
    ],
    settings: GameSettings(judgePlays: judgePlays, crowdJudged: crowdJudged),
  );
}

void main() {
  group('UpNext.resolve — players', () {
    test('not started: Start, plays the task', () {
      final u = UpNext.resolve(
        _game(statuses: {'p1': _s('p1', TaskPlayerState.not_started)}),
        currentUserId: 'p1',
        isJudge: false,
      );
      expect(u.kicker, 'YOUR TURN');
      expect(u.title, 'Find your oldest book');
      expect(u.buttonLabel, 'Start');
      expect(u.action, UpNextAction.play);
      expect(u.taskIndex, 0);
    });

    test('no personal status yet still plays (never a dead end)', () {
      final u = UpNext.resolve(_game(statuses: const {}),
          currentUserId: 'p1', isJudge: false);
      expect(u.action, UpNextAction.play);
    });

    test('in progress near the deadline is urgent', () {
      final now = DateTime(2026, 7, 1, 12);
      final u = UpNext.resolve(
        _game(
          statuses: {'p1': _s('p1', TaskPlayerState.in_progress)},
          deadline: now.add(const Duration(minutes: 20)),
        ),
        currentUserId: 'p1',
        isJudge: false,
        now: now,
      );
      expect(u.kicker, 'TIME RUNNING OUT');
      expect(u.urgent, isTrue);
      expect(u.action, UpNextAction.play);
    });

    test('submitted, others pending: "Waiting for N more", disabled', () {
      final u = UpNext.resolve(
        _game(statuses: {
          'judge': _s('judge', TaskPlayerState.not_started),
          'p1': _s('p1', TaskPlayerState.submitted),
          'p2': _s('p2', TaskPlayerState.not_started),
        }),
        currentUserId: 'p1',
        isJudge: false,
      );
      expect(u.buttonLabel, 'Waiting for 2 more');
      expect(u.action, UpNextAction.none);
      expect(u.isWaiting, isTrue);
    });

    test('everyone in, the playing judge grades the entries', () {
      final u = UpNext.resolve(
        _game(
          taskStatus: TaskStatus.ready_to_judge,
          statuses: {
            'judge': _s('judge', TaskPlayerState.submitted),
            'p1': _s('p1', TaskPlayerState.submitted),
            'p2': _s('p2', TaskPlayerState.submitted),
          },
        ),
        currentUserId: 'judge',
        isJudge: true,
      );
      expect(u.buttonLabel, 'Grade 3 entries');
      expect(u.action, UpNextAction.judge);
    });

    test('everyone in, a non-judge waits on the judge', () {
      final u = UpNext.resolve(
        _game(
          taskStatus: TaskStatus.judging,
          statuses: {
            'p1': _s('p1', TaskPlayerState.submitted),
            'p2': _s('p2', TaskPlayerState.submitted),
          },
        ),
        currentUserId: 'p1',
        isJudge: false,
      );
      expect(u.kicker, 'JUDGE IS REVIEWING');
      expect(u.action, UpNextAction.none);
    });

    test('crowd-judged games wait for the crowd', () {
      final u = UpNext.resolve(
        _game(
          crowdJudged: true,
          statuses: {'p1': _s('p1', TaskPlayerState.submitted)},
        ),
        currentUserId: 'p1',
        isJudge: false,
      );
      expect(u.buttonLabel, 'Waiting for the crowd');
    });

    test('completed task shows results with the player score', () {
      final u = UpNext.resolve(
        _game(
          taskStatus: TaskStatus.completed,
          statuses: {'p1': _s('p1', TaskPlayerState.judged, score: 4)},
        ),
        currentUserId: 'p1',
        isJudge: false,
      );
      expect(u.action, UpNextAction.results);
      // A judge scores out of 10 (JudgingBloc.maxScore), never out of 5.
      expect(u.detail, 'You got 4/10.');
    });

    test('a judge-mode score uses the judge scale as its max', () {
      final u = UpNext.resolve(
        _game(
          taskStatus: TaskStatus.completed,
          statuses: {'p1': _s('p1', TaskPlayerState.judged, score: 9)},
        ),
        currentUserId: 'p1',
        isJudge: false,
      );
      expect(u.detail, 'You got 9/${JudgingBloc.maxScore}.');
      expect(JudgingBloc.maxScore, 10);
    });
  });

  group('UpNext.resolve — non-playing judge (judgePlays=false)', () {
    test('grades once the seeker has submitted, driven by task state', () {
      final u = UpNext.resolve(
        _game(
          judgePlays: false,
          statuses: {'p1': _s('p1', TaskPlayerState.submitted)},
        ),
        currentUserId: 'judge',
        isJudge: true,
      );
      expect(u.kicker, 'TIME TO JUDGE');
      expect(u.buttonLabel, 'Grade 1 entry');
      expect(u.action, UpNextAction.judge);
    });

    test('before the seeker submits: waits, never routes into the submit UI',
        () {
      final u = UpNext.resolve(
        _game(
          judgePlays: false,
          statuses: {'p1': _s('p1', TaskPlayerState.not_started)},
        ),
        currentUserId: 'judge',
        isJudge: true,
      );
      expect(u.kicker, 'WAITING FOR THE SEEKER');
      expect(u.action, UpNextAction.none);
    });
  });

  testWidgets('UpNextCard shows exactly one filled button and disables it '
      'while waiting', (tester) async {
    var taps = 0;
    Future<void> pump(UpNext u) => tester.pumpWidget(MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: UpNextCard(
              upNext: u,
              taskCount: 5,
              timerSeconds: 30,
              onPressed: () => taps++,
            ),
          ),
        ));

    await pump(const UpNext(
      kicker: 'YOUR TURN',
      title: 'Do a thing',
      buttonLabel: 'Start',
      action: UpNextAction.play,
      taskIndex: 1,
    ));
    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.text('TASK 2 OF 5'), findsOneWidget);
    expect(find.text('⏱ 30 s'), findsOneWidget);
    await tester.tap(find.text('Start'));
    expect(taps, 1);

    await pump(const UpNext(
      kicker: 'SUBMITTED ✓',
      title: 'Do a thing',
      buttonLabel: 'Waiting for 3 more',
      action: UpNextAction.none,
      taskIndex: 1,
    ));
    expect(find.byType(FilledButton), findsOneWidget);
    final button =
        tester.widget<FilledButton>(find.byKey(const Key('up-next-button')));
    expect(button.onPressed, isNull);
    // The timer pill is only for something you can start.
    expect(find.text('⏱ 30 s'), findsNothing);
  });
}
