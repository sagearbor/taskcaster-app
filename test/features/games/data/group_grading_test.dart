import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/models/game.dart';
import 'package:taskcaster_app/core/models/game_settings.dart';
import 'package:taskcaster_app/core/models/player.dart';
import 'package:taskcaster_app/core/models/player_task_status.dart';
import 'package:taskcaster_app/core/models/submission.dart';
import 'package:taskcaster_app/core/models/task.dart';
import 'package:taskcaster_app/features/games/data/datasources/mock_game_data_source.dart';
import 'package:taskcaster_app/features/games/data/repositories/game_repository_impl.dart';
import 'package:taskcaster_app/features/games/domain/peer_grading.dart';
import 'package:taskcaster_app/features/games/domain/repositories/game_repository.dart';

/// WP-13 friend games, everyone grades everyone: the lock rules and a whole
/// group game played through the real repository against the mock backend
/// (which mirrors firestore.rules + functions/src/peer_grading.js).
void main() {
  final t0 = DateTime.utc(2026, 11, 5, 10);

  Submission entry(String uid, {DateTime? at}) => Submission(
        id: 'sub-$uid',
        userId: uid,
        text: 'entry by $uid',
        mediaType: SubmissionMediaType.text,
        score: 0,
        isJudged: false,
        submittedAt: at ?? t0,
      );

  group('model', () {
    test('games without judgingMode keep judge mode; new field round-trips',
        () {
      expect(GameSettings.fromMap(const {}).judgingMode, JudgingMode.judge);
      expect(
          GameSettings.fromMap(const {'judgingMode': 'nonsense'}).judgingMode,
          JudgingMode.judge);
      const group = GameSettings(judgingMode: JudgingMode.group);
      expect(GameSettings.fromMap(group.toMap()), group);
      expect(group.isGroupJudged, isTrue);
    });

    test('Task.peerGraders round-trips (clients rewrite the tasks array)', () {
      const task = Task(
        id: 't1',
        title: 'x',
        description: '',
        taskType: TaskType.video,
        submissions: [],
        peerGraders: {
          'a': ['b', 'c'],
        },
      );
      final back = Task.fromMap(task.toMap());
      expect(back.peerGraders, {
        'a': ['b', 'c'],
      });
      expect(back.hasPeerGraded('a', 'b'), isTrue);
      expect(back.hasPeerGraded('b', 'a'), isFalse);
      expect(Task.fromMap({...task.toMap()}..remove('peerGraders')).peerGraders,
          isEmpty);
    });
  });

  group('PeerGrading rules', () {
    Game game({
      Map<String, TaskPlayerState> states = const {},
      Map<String, List<String>> peerGraders = const {},
      JudgingMode mode = JudgingMode.group,
    }) {
      const uids = ['a', 'b', 'c'];
      return Game(
        id: 'g',
        gameName: 'Friday',
        creatorId: 'a',
        judgeId: '',
        status: GameStatus.inProgress,
        inviteCode: 'ABC234',
        createdAt: t0,
        players: [
          for (final u in uids)
            Player(userId: u, displayName: u.toUpperCase(), totalScore: 0),
        ],
        tasks: [
          Task(
            id: 't1',
            title: 'Egg race',
            description: '',
            taskType: TaskType.video,
            submissions: [
              for (final e in states.entries)
                if (e.value != TaskPlayerState.not_started &&
                    e.value != TaskPlayerState.skipped)
                  entry(e.key),
            ],
            peerGraders: peerGraders,
            playerStatuses: {
              for (final u in uids)
                u: PlayerTaskStatus(
                  playerId: u,
                  state: states[u] ?? TaskPlayerState.not_started,
                  submittedAt: (states[u] == TaskPlayerState.submitted ||
                          states[u] == TaskPlayerState.judged)
                      ? t0
                      : null,
                ),
            },
          ),
        ],
        settings: GameSettings(judgingMode: mode),
      );
    }

    PeerGrade g(String target, String grader, int score) => PeerGrade(
        taskId: 't1',
        taskIndex: 0,
        targetUid: target,
        graderUid: grader,
        score: score);

    test('points are round(mean x 2), 0..10', () {
      expect(PeerGrading.pointsFor(const []), 0);
      expect(PeerGrading.pointsFor(const [5, 5]), 10);
      expect(PeerGrading.pointsFor(const [3, 4]), 7);
      expect(PeerGrading.pointsFor(const [1]), 2);
    });

    test('the queue is empty until you post, then lists the others', () {
      final before = game(states: {
        'b': TaskPlayerState.submitted,
        'c': TaskPlayerState.submitted,
      });
      expect(PeerGrading.queue(before, 0, 'a'), isEmpty);

      final after = game(states: {
        'a': TaskPlayerState.submitted,
        'b': TaskPlayerState.submitted,
        'c': TaskPlayerState.submitted,
      }, peerGraders: {
        'b': ['a'],
      });
      expect(PeerGrading.queue(after, 0, 'a').map((s) => s.userId), ['c']);
      expect(
          PeerGrading.queue(after, 0, 'a', alsoGraded: {'c'}), isEmpty);
      // Never your own entry; never in judge mode.
      expect(PeerGrading.queue(after, 0, 'b').map((s) => s.userId),
          ['a', 'c']);
      expect(
          PeerGrading.queue(
              game(states: {
                'a': TaskPlayerState.submitted,
                'b': TaskPlayerState.submitted
              }, mode: JudgingMode.judge),
              0,
              'a'),
          isEmpty);
    });

    test('an entry locks only once every other (non-skipped) player graded',
        () {
      final all = game(states: {
        'a': TaskPlayerState.submitted,
        'b': TaskPlayerState.submitted,
        'c': TaskPlayerState.submitted,
      });
      final partial = PeerGrading.settle(
          game: all,
          taskId: 't1',
          grades: [g('a', 'b', 4)],
          locked: const {},
          now: t0)!;
      expect(partial.locks, isEmpty);

      final full = PeerGrading.settle(
          game: all,
          taskId: 't1',
          grades: [g('a', 'b', 4), g('a', 'c', 5), g('a', 'a', 1)],
          locked: const {},
          now: t0)!;
      expect(full.locks,
          [const PeerLock(uid: 'a', points: 9, mean: 4.5, gradeCount: 2)]);
      expect(full.complete, isFalse);

      final skipped = game(states: {
        'a': TaskPlayerState.submitted,
        'b': TaskPlayerState.submitted,
        'c': TaskPlayerState.skipped,
      });
      final out = PeerGrading.settle(
          game: skipped,
          taskId: 't1',
          grades: [g('a', 'b', 2), g('b', 'a', 3)],
          locked: const {},
          now: t0)!;
      expect(out.locks.map((l) => l.uid), ['a', 'b']);
      expect(out.complete, isTrue);
    });

    test('after 24 h everything locks and the task completes', () {
      final two = game(states: {
        'a': TaskPlayerState.submitted,
        'b': TaskPlayerState.submitted,
      });
      final early = PeerGrading.settle(
          game: two,
          taskId: 't1',
          grades: [g('a', 'b', 4)],
          locked: const {},
          now: t0.add(const Duration(hours: 23)))!;
      expect(early.locks, isEmpty);
      final late = PeerGrading.settle(
          game: two,
          taskId: 't1',
          grades: [g('a', 'b', 4)],
          locked: const {},
          now: t0.add(PeerGrading.lockAfter))!;
      expect(late.locks, const [
        PeerLock(uid: 'a', points: 8, mean: 4, gradeCount: 1),
        PeerLock(uid: 'b', points: 0, mean: 0, gradeCount: 0),
      ]);
      expect(late.complete, isTrue, reason: 'c never posted');
    });

    test('a task nobody posts to still expires 24 h after it opened', () {
      final g0 = game();
      final opened = g0.copyWith(
          tasks: [g0.tasks.first.copyWith(openedAt: t0)]);
      final early = PeerGrading.settle(
          game: opened,
          taskId: 't1',
          grades: const [],
          locked: const {},
          now: t0.add(const Duration(hours: 23)))!;
      expect(early.complete, isFalse);
      final late = PeerGrading.settle(
          game: opened,
          taskId: 't1',
          grades: const [],
          locked: const {},
          now: t0.add(PeerGrading.lockAfter))!;
      expect(late.locks, isEmpty);
      expect(late.complete, isTrue, reason: 'nobody posted in 24 h');
    });

    test('an unstamped current task starts its clock when first settled', () {
      final out = PeerGrading.settle(
          game: game(),
          taskId: 't1',
          grades: const [],
          locked: const {},
          now: t0)!;
      expect(out.openedAt, t0);
      expect(out.complete, isFalse);
      final next = PeerGrading.apply(game(), out, totals: const {}, now: t0);
      expect(next.tasks.first.openedAt, t0);
    });

    test('Task.openedAt round-trips', () {
      final task = game().tasks.first.copyWith(openedAt: t0);
      expect(Task.fromMap(task.toMap()).openedAt, t0);
      expect(Task.fromMap(game().tasks.first.toMap()).openedAt, isNull);
    });
  });

  group('a group game through the repository (mock backend)', () {
    late MockGameDataSource ds;
    late GameRepository repo;

    setUp(() {
      ds = MockGameDataSource();
      repo = GameRepositoryImpl(ds);
    });

    tearDown(() => ds.dispose());

    Future<Game> current(String id) async =>
        (await repo.getGameStream(id).first)!;

    Future<String> startGroupGame(List<String> uids, List<String> taskIds) async {
      final id = await repo.createGame('Friday', uids.first, uids.first,
          judgingMode: JudgingMode.group);
      final lobby = await current(id);
      for (final u in uids.skip(1)) {
        await repo.joinGame(lobby.inviteCode, u, u.toUpperCase());
      }
      await repo.addTasksToGame(id, [
        for (final t in taskIds)
          Task(
            id: t,
            title: 'Task $t',
            description: '',
            taskType: TaskType.video,
            submissions: const [],
          ),
      ]);
      await repo.startGame(id);
      return id;
    }

    test('a 3-player group game completes all tasks with no player marked judge',
        () async {
      const uids = ['a', 'b', 'c'];
      final id = await startGroupGame(uids, ['t1', 't2']);
      final started = await current(id);
      expect(started.judgeId, isEmpty, reason: 'nobody is the judge');
      expect(started.isGroupJudged, isTrue);
      for (final u in uids) {
        expect(started.isUserJudge(u), isFalse);
      }

      const scores = {
        't1': {'a': 5, 'b': 3, 'c': 4},
        't2': {'a': 2, 'b': 5, 'c': 5},
      };
      for (final (index, taskId) in [(0, 't1'), (1, 't2')]) {
        expect((await current(id)).currentTaskIndex, index);
        for (final u in uids) {
          await repo.submitTaskAnswer(id, taskId, entry(u));
        }
        for (final grader in uids) {
          // Each player's grade queue is exactly the other two entries.
          final queue = PeerGrading.queue(await current(id), index, grader);
          expect(queue.map((s) => s.userId).toSet(),
              uids.where((u) => u != grader).toSet());
          for (final target in queue.map((s) => s.userId)) {
            await repo.submitPeerGrade(
              gameId: id,
              taskIndex: index,
              taskId: taskId,
              targetUid: target,
              graderUid: grader,
              score: scores[taskId]![target]!,
            );
          }
        }
        final task = (await current(id)).tasks[index];
        expect(task.status, TaskStatus.completed);
        for (final u in uids) {
          expect(task.playerStatuses[u]!.state, TaskPlayerState.judged);
          expect(task.playerStatuses[u]!.score, scores[taskId]![u]! * 2);
        }
      }

      final done = await current(id);
      expect(done.status, GameStatus.completed);
      expect(done.judgeId, isEmpty);
      expect({for (final p in done.players) p.userId: p.totalScore},
          {'a': 14, 'b': 16, 'c': 18});
    });

    test('grading twice, grading yourself, or grading before posting is refused',
        () async {
      final id = await startGroupGame(['a', 'b'], ['t1']);
      await repo.submitTaskAnswer(id, 't1', entry('a'));

      // b has not posted yet: grading is locked.
      await expectLater(
        repo.submitPeerGrade(
            gameId: id,
            taskIndex: 0,
            taskId: 't1',
            targetUid: 'a',
            graderUid: 'b',
            score: 4),
        throwsA(isA<PeerGradeRejected>()),
      );

      await repo.submitTaskAnswer(id, 't1', entry('b'));
      await expectLater(
        repo.submitPeerGrade(
            gameId: id,
            taskIndex: 0,
            taskId: 't1',
            targetUid: 'b',
            graderUid: 'b',
            score: 5),
        throwsA(isA<PeerGradeRejected>()),
      );
      await repo.submitPeerGrade(
          gameId: id,
          taskIndex: 0,
          taskId: 't1',
          targetUid: 'a',
          graderUid: 'b',
          score: 1);
      // a's entry locked (b was the only other player): a second grade is
      // refused either way.
      await expectLater(
        repo.submitPeerGrade(
            gameId: id,
            taskIndex: 0,
            taskId: 't1',
            targetUid: 'a',
            graderUid: 'b',
            score: 5),
        throwsA(isA<PeerGradeRejected>()),
      );
      final game = await current(id);
      expect(game.tasks[0].playerStatuses['a']!.score, 2);
      expect(game.players.firstWhere((p) => p.userId == 'a').totalScore, 2);
    });

    test('the 24 h lock completes a task a player never played', () async {
      final id = await startGroupGame(['a', 'b', 'c'], ['t1', 't2']);
      await repo.submitTaskAnswer(id, 't1', entry('a', at: DateTime.now()));
      await repo.submitTaskAnswer(id, 't1', entry('b', at: DateTime.now()));
      await repo.submitPeerGrade(
          gameId: id,
          taskIndex: 0,
          taskId: 't1',
          targetUid: 'a',
          graderUid: 'b',
          score: 5);
      expect((await current(id)).tasks[0].isCompleted, isFalse,
          reason: 'c may still post and grade');

      ds.clock = () => DateTime.now().add(const Duration(hours: 25));
      ds.settlePeerTask(id, 't1');
      final after = await current(id);
      expect(after.tasks[0].isCompleted, isTrue);
      expect(after.currentTaskIndex, 1, reason: 'the game moves on by itself');
      expect(after.tasks[0].playerStatuses['a']!.score, 10);
      expect(after.tasks[0].playerStatuses['b']!.score, 0,
          reason: 'nobody graded b in time');
    });

    test('starting and advancing a game opens each task, so an empty task expires',
        () async {
      final id = await startGroupGame(['a', 'b'], ['t1', 't2']);
      final started = await current(id);
      expect(started.tasks[0].openedAt, isNotNull,
          reason: 'the first task opens when the game starts');
      expect(started.tasks[1].openedAt, isNull);

      // Nobody posts. 25 h later the sweep still completes the task.
      ds.clock = () => DateTime.now().add(const Duration(hours: 25));
      ds.settlePeerTask(id, 't1');
      final after = await current(id);
      expect(after.tasks[0].isCompleted, isTrue);
      expect(after.currentTaskIndex, 1);
      expect(after.tasks[1].openedAt, isNotNull,
          reason: 'the next task starts its own clock');
    });

    test('Taskmaster mode (and the default) keeps a judge', () async {
      final judged = await repo.createGame('Classic', 'a', 'a');
      final g = await current(judged);
      expect(g.judgeId, 'a');
      expect(g.isGroupJudged, isFalse);
    });
  });
}
