import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/models/game.dart';
import 'package:taskcaster_app/core/models/game_settings.dart';
import 'package:taskcaster_app/core/models/player.dart';
import 'package:taskcaster_app/core/models/player_task_status.dart';
import 'package:taskcaster_app/core/models/submission.dart';
import 'package:taskcaster_app/core/models/task.dart';
import 'package:taskcaster_app/core/theme/app_theme.dart';
import 'package:taskcaster_app/features/games/presentation/widgets/game_in_progress_view.dart';
import 'package:taskcaster_app/features/games/presentation/widgets/up_next_card.dart';

/// WP-13: in a group-graded game "Grade N entries" is every player's next
/// step once they have posted, and nobody waits on a judge.
/// The real bundled fonts (as the game-screen goldens use): the crew strip
/// is sized for them and overflows with the default test font.
Future<void> _loadFonts() async {
  Future<void> load(String family, Future<ByteData> data) async {
    final loader = FontLoader(family)..addFont(data);
    await loader.load();
  }

  await load('Fredoka', rootBundle.load('assets/fonts/Fredoka.ttf'));
  await load(
      'PlusJakartaSans', rootBundle.load('assets/fonts/PlusJakartaSans.ttf'));
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    final icons = File(
        '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      await load('MaterialIcons',
          Future.value(ByteData.view(icons.readAsBytesSync().buffer)));
    }
  }
}

void main() {
  final at = DateTime(2026, 11, 5, 10);

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
  });

  Game game(
    Map<String, TaskPlayerState> states, {
    Map<String, List<String>> peerGraders = const {},
    TaskStatus taskStatus = TaskStatus.waiting_for_submissions,
    List<Task> extraTasks = const [],
    int currentTaskIndex = 0,
  }) {
    const uids = ['me', 'sue', 'raj'];
    bool posted(String u) =>
        states[u] == TaskPlayerState.submitted ||
        states[u] == TaskPlayerState.judged;
    return Game(
      id: 'g1',
      gameName: 'Friday',
      creatorId: 'me',
      judgeId: '',
      status: GameStatus.inProgress,
      inviteCode: 'ABC234',
      createdAt: at,
      players: const [
        Player(userId: 'me', displayName: 'Me', totalScore: 8),
        Player(userId: 'sue', displayName: 'Sue', totalScore: 6),
        Player(userId: 'raj', displayName: 'Raj', totalScore: 4),
      ],
      tasks: [
        Task(
          id: 't1',
          title: 'Ode to a spoon',
          description: '',
          taskType: TaskType.video,
          status: taskStatus,
          peerGraders: peerGraders,
          submissions: [
            for (final u in uids)
              if (posted(u))
                Submission(
                  id: 's-$u',
                  userId: u,
                  score: 0,
                  isJudged: false,
                  submittedAt: at,
                ),
          ],
          playerStatuses: {
            for (final u in uids)
              u: PlayerTaskStatus(
                playerId: u,
                state: states[u] ?? TaskPlayerState.not_started,
                score: states[u] == TaskPlayerState.judged ? 8 : null,
              ),
          },
        ),
        ...extraTasks,
      ],
      currentTaskIndex: currentTaskIndex,
      settings: const GameSettings(judgingMode: JudgingMode.group),
    );
  }

  UpNext resolve(Game g, {Set<String> alsoGraded = const {}}) =>
      UpNext.resolve(g,
          currentUserId: 'me', isJudge: false, alsoGraded: alsoGraded);

  test('after posting, every player gets "Grade N entries"', () {
    final u = resolve(game({
      'me': TaskPlayerState.submitted,
      'sue': TaskPlayerState.submitted,
      'raj': TaskPlayerState.submitted,
    }));
    expect(u.action, UpNextAction.grade);
    expect(u.buttonLabel, 'Grade 2 entries');
    expect(u.kicker, 'GRADE THE CREW');
  });

  test('entries can be graded as they land, before everyone is in', () {
    final u = resolve(game({
      'me': TaskPlayerState.submitted,
      'sue': TaskPlayerState.submitted,
    }));
    expect(u.action, UpNextAction.grade);
    expect(u.buttonLabel, 'Grade 1 entry');
  });

  test('graded everything so far: waiting for the rest to post', () {
    final u = resolve(
      game({
        'me': TaskPlayerState.submitted,
        'sue': TaskPlayerState.submitted,
      }, peerGraders: {
        'sue': ['me'],
      }),
    );
    expect(u.action, UpNextAction.none);
    expect(u.buttonLabel, 'Waiting for 1 more');
  });

  test('all graded (server echo or this device): waiting for the crew', () {
    final all = {
      'me': TaskPlayerState.submitted,
      'sue': TaskPlayerState.submitted,
      'raj': TaskPlayerState.submitted,
    };
    final u = resolve(game(all), alsoGraded: {'sue', 'raj'});
    expect(u.action, UpNextAction.none);
    expect(u.buttonLabel, 'Waiting for the crew');
    expect(u.detail, contains('24 hours'));
  });

  test('not posted yet: play first (grading is unlocked by posting)', () {
    final u = resolve(game({
      'sue': TaskPlayerState.submitted,
      'raj': TaskPlayerState.submitted,
    }));
    expect(u.action, UpNextAction.play);
  });

  test('a judge-mode game never offers peer grading', () {
    final g = game({
      'me': TaskPlayerState.submitted,
      'sue': TaskPlayerState.submitted,
      'raj': TaskPlayerState.submitted,
    });
    final judged = g.copyWith(settings: const GameSettings());
    expect(resolve(judged).action, isNot(UpNextAction.grade));
  });

  test('a locked task reports the score out of 10', () {
    final u = resolve(game({
      'me': TaskPlayerState.judged,
      'sue': TaskPlayerState.judged,
      'raj': TaskPlayerState.judged,
    }, taskStatus: TaskStatus.completed));
    expect(u.action, UpNextAction.results);
    expect(u.detail, 'You got 8/10.');
  });

  testWidgets('the "scores are in" card appears for everyone once a task locks',
      (tester) async {
    int? opened;
    final g = game(
      {
        'me': TaskPlayerState.judged,
        'sue': TaskPlayerState.judged,
        'raj': TaskPlayerState.judged,
      },
      taskStatus: TaskStatus.completed,
      extraTasks: const [
        Task(
          id: 't2',
          title: 'Next one',
          description: '',
          taskType: TaskType.video,
          submissions: [],
        ),
      ],
      currentTaskIndex: 1,
    );
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: GameInProgressView(
          game: g,
          currentUserId: 'me',
          onViewResults: (i) => opened = i,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Task 1 scores are in'), findsOneWidget);
    expect(find.textContaining('You got 8/10'), findsOneWidget);
    await tester.tap(find.byKey(const Key('scores-in-card')));
    expect(opened, 0);
  });

  testWidgets('judge-mode games show no "scores are in" card', (tester) async {
    final g = game({
      'me': TaskPlayerState.judged,
    }, taskStatus: TaskStatus.completed)
        .copyWith(settings: const GameSettings());
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: GameInProgressView(
          game: g,
          currentUserId: 'me',
          onViewResults: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scores-in-card')), findsNothing);
  });
}
