// WP-02: game writes are transactional and touch only the caller's entries.
// Runs the real GameRepositoryImpl + FirestoreGameDataSource against
// fake_cloud_firestore, so these exercise the code that ships.
import 'dart:async';
import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/models/game.dart';
import 'package:taskcaster_app/core/models/game_settings.dart';
import 'package:taskcaster_app/core/models/player.dart';
import 'package:taskcaster_app/core/models/player_task_status.dart';
import 'package:taskcaster_app/core/models/task.dart';
import 'package:taskcaster_app/core/services/video/video_capture.dart';
import 'package:taskcaster_app/core/services/video/video_uploader.dart';
import 'package:taskcaster_app/features/games/data/datasources/firestore_game_data_source.dart';
import 'package:taskcaster_app/features/games/data/datasources/mock_game_data_source.dart';
import 'package:taskcaster_app/features/games/data/repositories/game_repository_impl.dart';
import 'package:taskcaster_app/features/games/domain/repositories/game_repository.dart';
import 'package:taskcaster_app/features/games/presentation/bloc/judging_bloc.dart';
import 'package:taskcaster_app/features/games/presentation/bloc/judging_event.dart';
import 'package:taskcaster_app/features/games/presentation/bloc/judging_state.dart';
import 'package:taskcaster_app/features/games/presentation/bloc/task_execution_bloc.dart';
import 'package:taskcaster_app/features/games/presentation/bloc/task_execution_event.dart';
import 'package:taskcaster_app/features/games/presentation/bloc/task_execution_state.dart';

const creator = 'creator';
const judge = 'judge';
const alice = 'alice';
const bob = 'bob';

PlayerTaskStatus _status(String id, TaskPlayerState state, {int? score}) =>
    PlayerTaskStatus(playerId: id, state: state, score: score);

Task _task(String id, Map<String, PlayerTaskStatus> statuses,
        {TaskStatus status = TaskStatus.waiting_for_submissions}) =>
    Task(
      id: id,
      title: 'Task $id',
      description: 'Do it',
      taskType: TaskType.video,
      submissions: const [],
      playerStatuses: statuses,
      status: status,
    );

Game _game({
  String id = 'g1',
  GameStatus status = GameStatus.inProgress,
  List<String> playerIds = const [creator, alice, bob],
  List<Task>? tasks,
  GameSettings settings = const GameSettings(),
  String? gameKind,
  String inviteCode = 'ABC234',
  DateTime? createdAt,
  int currentTaskIndex = 0,
}) =>
    Game(
      id: id,
      gameName: 'Game Night',
      creatorId: creator,
      judgeId: judge,
      status: status,
      inviteCode: inviteCode,
      createdAt: createdAt ?? DateTime(2026, 11, 5),
      players: [
        for (final p in playerIds)
          Player(userId: p, displayName: p, totalScore: 0),
      ],
      tasks: tasks ??
          [
            _task('t1', {
              for (final p in playerIds)
                p: _status(p, TaskPlayerState.not_started),
            }),
            _task('t2', {
              for (final p in playerIds)
                p: _status(p, TaskPlayerState.not_started),
            }),
          ],
      settings: settings,
      gameKind: gameKind,
      currentTaskIndex: currentTaskIndex,
    );

/// A video uploader that holds every upload until [release] is called: the
/// "slow submit" of the concurrency test.
class _GatedUploader implements VideoUploader {
  final Completer<void> _gate = Completer<void>();
  final Completer<void> started = Completer<void>();

  void release() => _gate.complete();

  @override
  Future<VideoUploadResult> upload({
    required String userId,
    required Uint8List bytes,
    required String contentType,
    required DateTime when,
    Map<String, String>? metadata,
    void Function(double fraction)? onProgress,
  }) async {
    started.complete();
    await _gate.future;
    return VideoUploadResult(
      downloadUrl: 'https://example.test/$userId.mp4',
      storagePath: 'submissions/$userId/20261105/0',
      bytes: bytes.length,
    );
  }
}

void main() {
  late FakeFirebaseFirestore firestore;
  late GameRepository repo;

  GameRepository repoAs(String uid) => GameRepositoryImpl(
        FirestoreGameDataSource(
          firestore: firestore,
          auth: MockFirebaseAuth(
            signedIn: true,
            mockUser: MockUser(uid: uid, displayName: uid),
          ),
        ),
      );

  Future<void> seed(Game game) async {
    await firestore.collection('games').doc(game.id).set(
          Map.of(game.toMap())..remove('id'),
        );
  }

  // Straight from the document (fake_cloud_firestore's snapshot streams can
  // lag a just-committed transaction; a real get() is what we want anyway).
  Future<Game> read([String id = 'g1']) async {
    final snap = await firestore.collection('games').doc(id).get();
    return Game.fromMap({...snap.data()!, 'id': id});
  }

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = repoAs(creator);
  });

  group('home query', () {
    test('returns only games whose playerIds hold the user, newest first',
        () async {
      await seed(_game(id: 'old', createdAt: DateTime(2026, 1, 1)));
      await seed(_game(id: 'new', createdAt: DateTime(2026, 6, 1)));
      await seed(_game(id: 'theirs', playerIds: const ['x', 'y']));
      // A doc that lists alice in players[] but not playerIds is NOT hers:
      // the scope is the query, not a client-side filter over everything.
      await firestore.collection('games').doc('legacy').set({
        'gameName': 'Legacy',
        'creatorId': 'x',
        'players': [
          {'userId': alice, 'displayName': alice, 'totalScore': 0}
        ],
        'createdAt': DateTime(2026, 9, 1).toIso8601String(),
      });

      final games = await repoAs(alice).getGamesStream().first;

      expect(games.map((g) => g.id), ['new', 'old']);
    });
  });

  group('joinGame', () {
    test('two joins land one after the other without losing either',
        () async {
      await seed(_game(status: GameStatus.lobby, playerIds: const [creator]));

      await repoAs(alice).joinGame('ABC234', alice, 'Alice');
      await repoAs(bob).joinGame('ABC234', bob, 'Bob');

      final raw = (await firestore.collection('games').doc('g1').get()).data()!;
      expect(raw['playerIds'], [creator, alice, bob]);
      expect((raw['players'] as List).map((p) => (p as Map)['userId']),
          [creator, alice, bob]);
    });

    // fake_cloud_firestore does not model transaction contention (two
    // overlapping transactions both commit), so the truly simultaneous case
    // runs against the in-memory data source, whose transactGame honours the
    // same contract: the read and the write are one atomic step.
    test('two simultaneous joins both land (atomic data source)', () async {
      final ds = MockGameDataSource();
      final memRepo = GameRepositoryImpl(ds);
      final id = await memRepo.createGame('Lobby', creator, creator);
      final code = (await memRepo.getGameStream(id).first)!.inviteCode;

      await Future.wait([
        memRepo.joinGame(code, alice, 'Alice'),
        memRepo.joinGame(code, bob, 'Bob'),
      ]);

      final game = (await memRepo.getGameStream(id).first)!;
      expect(game.playerIds.toSet(), {creator, alice, bob});
      ds.dispose();
    });

    test('appends exactly the joiner, at score 0, leaving others untouched',
        () async {
      await seed(_game(status: GameStatus.lobby, playerIds: const [creator]));
      await firestore.collection('games').doc('g1').update({
        'players': [
          {'userId': creator, 'displayName': 'Cat', 'totalScore': 7}
        ],
      });

      await repoAs(alice).joinGame('ABC234', alice, 'Alice');

      final raw = (await firestore.collection('games').doc('g1').get()).data()!;
      expect(raw['players'], [
        {'userId': creator, 'displayName': 'Cat', 'totalScore': 7},
        {'userId': alice, 'displayName': 'Alice', 'totalScore': 0},
      ]);
      expect(raw['playerIds'], [creator, alice]);
    });

    test('is a no-op for a player already in the game', () async {
      await seed(_game(status: GameStatus.lobby));
      await repoAs(alice).joinGame('ABC234', alice, 'Alice');
      expect((await read()).players.length, 3);
    });

    test('refuses an ordinary game that has already started', () async {
      await seed(_game(playerIds: const [creator]));
      await expectLater(
        repoAs(alice).joinGame('ABC234', alice, 'Alice'),
        throwsA(isA<GameJoinException>()),
      );
      expect((await read()).playerIds, [creator]);
    });

    test('lets friends into a Quick Play game already in progress', () async {
      await seed(_game(playerIds: const [creator], gameKind: Game.kindQuick));
      await repoAs(alice).joinGame('ABC234', alice, 'Alice');
      expect((await read()).playerIds, [creator, alice]);
    });

    test('refuses a full game', () async {
      await seed(_game(
        status: GameStatus.lobby,
        playerIds: const [creator, bob],
        settings: const GameSettings(maxPlayers: 2),
      ));
      await expectLater(
        repoAs(alice).joinGame('ABC234', alice, 'Alice'),
        throwsA(isA<GameJoinException>()),
      );
    });

    test('an unknown code is "not found"', () async {
      await expectLater(
        repoAs(alice).joinGame('NOPE00', alice, 'Alice'),
        throwsA(predicate((e) => e.toString().contains('not found'))),
      );
    });
  });

  group('startGame', () {
    test('a second start is a no-op and keeps the submissions', () async {
      await seed(_game(status: GameStatus.lobby, tasks: [
        _task('t1', const {}),
      ]));
      await repo.startGame('g1');

      await repoAs(alice).updateTaskAtomically('g1', 0, (t) {
        return t.copyWith(playerStatuses: {
          ...t.playerStatuses,
          alice: _status(alice, TaskPlayerState.submitted),
        });
      });

      await repo.startGame('g1'); // double tap

      final game = await read();
      expect(game.status, GameStatus.inProgress);
      expect(game.tasks[0].playerStatuses[alice]!.state,
          TaskPlayerState.submitted);
    });
  });

  group('judgeSubmission', () {
    test('re-judging a player leaves totalScore == the latest score',
        () async {
      await seed(_game());
      await repo.judgeSubmission('g1', 0, alice, 7);
      await repo.judgeSubmission('g1', 0, alice, 4);

      final game = await read();
      expect(game.players.firstWhere((p) => p.userId == alice).totalScore, 4);
      expect(game.tasks[0].playerStatuses[alice]!.score, 4);
    });

    test('scores on different tasks still add up', () async {
      await seed(_game());
      await repo.judgeSubmission('g1', 0, alice, 7);
      await repo.judgeSubmission('g1', 1, alice, 3);
      await repo.judgeSubmission('g1', 1, alice, 5);

      final game = await read();
      expect(game.players.firstWhere((p) => p.userId == alice).totalScore, 12);
    });

    test("judging keeps a player's submission that landed meanwhile",
        () async {
      await seed(_game());
      // Alice submits after the judge's screen loaded, before the score saves.
      await repoAs(alice).updateTaskAtomically('g1', 0, (t) {
        return t.copyWith(playerStatuses: {
          ...t.playerStatuses,
          alice: _status(alice, TaskPlayerState.submitted),
        });
      });
      await repo.judgeSubmission('g1', 0, bob, 6);

      final game = await read();
      expect(game.tasks[0].playerStatuses[alice]!.state,
          TaskPlayerState.submitted);
      expect(game.tasks[0].playerStatuses[bob]!.score, 6);
    });
  });

  group('leaveGame', () {
    test('drops the leaver from the roster and every task', () async {
      await seed(_game());
      await repoAs(bob).leaveGame('g1', bob);

      final game = await read();
      expect(game.playerIds, [creator, alice]);
      for (final task in game.tasks) {
        expect(task.playerStatuses.containsKey(bob), isFalse);
      }
    });

    test('a task the leaver was the last holdout on moves to judging',
        () async {
      await seed(_game(tasks: [
        _task('t1', {
          creator: _status(creator, TaskPlayerState.submitted),
          alice: _status(alice, TaskPlayerState.submitted),
          bob: _status(bob, TaskPlayerState.not_started),
        }),
      ]));
      await repoAs(bob).leaveGame('g1', bob);

      expect((await read()).tasks[0].status, TaskStatus.ready_to_judge);
    });

    test('JudgingBloc skips a status whose player is gone instead of failing',
        () async {
      await seed(_game(tasks: [
        _task('t1', {
          alice: _status(alice, TaskPlayerState.submitted),
          'ghost': _status('ghost', TaskPlayerState.submitted),
        }),
      ]));
      final bloc = JudgingBloc(gameRepository: repo)
        ..add(const LoadSubmissions(gameId: 'g1', taskIndex: 0));
      final state = await bloc.stream
          .firstWhere((s) => s is JudgingLoaded || s is JudgingError);
      await bloc.close();

      expect(state, isA<JudgingLoaded>());
      expect((state as JudgingLoaded).submissions.map((s) => s.playerId),
          [alice]);
    });
  });

  group('advance / complete', () {
    test('only the judge or creator advances, forward only, index only',
        () async {
      await seed(_game(tasks: [
        _task('t1', const {}),
        _task('t2', const {}),
        _task('t3', const {}),
      ]));

      await repoAs(alice).advanceToTask('g1', 1, callerId: alice);
      expect((await read()).currentTaskIndex, 0);

      await repoAs(judge).advanceToTask('g1', 2, callerId: judge);
      expect((await read()).currentTaskIndex, 2);

      // A late countdown on another device must not drag it back.
      await repo.advanceToTask('g1', 1, callerId: creator);
      expect((await read()).currentTaskIndex, 2);
    });

    test('advancing writes only currentTaskIndex (no stale tasks)', () async {
      await seed(_game());
      // A player's submission lands; the judge's cached game predates it.
      await repoAs(alice).updateTaskAtomically('g1', 0, (t) {
        return t.copyWith(playerStatuses: {
          ...t.playerStatuses,
          alice: _status(alice, TaskPlayerState.submitted),
        });
      });
      await repo.advanceToTask('g1', 1, callerId: creator);

      final game = await read();
      expect(game.currentTaskIndex, 1);
      expect(game.tasks[0].playerStatuses[alice]!.state,
          TaskPlayerState.submitted);
    });

    test('only the judge or creator completes the game', () async {
      await seed(_game());
      await repoAs(alice).completeGame('g1', callerId: alice);
      expect((await read()).status, GameStatus.inProgress);

      await repo.completeGame('g1', callerId: creator);
      expect((await read()).status, GameStatus.completed);
    });
  });

  group('AR results', () {
    test('a non-judge player records a submission, not a score', () async {
      await seed(_game());
      await repoAs(alice).submitArResult('g1', 0, alice, 8, rawResult: 12);

      final game = await read();
      final status = game.tasks[0].playerStatuses[alice]!;
      expect(status.state, TaskPlayerState.submitted);
      expect(status.score, 8);
      expect(game.tasks[0].arResult, 12);
      expect(game.players.firstWhere((p) => p.userId == alice).totalScore, 0);
    });

    test('the creator self-judges instantly', () async {
      await seed(_game());
      await repo.submitArResult('g1', 0, creator, 8);

      final game = await read();
      expect(game.tasks[0].playerStatuses[creator]!.state,
          TaskPlayerState.judged);
      expect(
          game.players.firstWhere((p) => p.userId == creator).totalScore, 8);
    });
  });

  group('submit (TaskExecutionBloc against the real repository)', () {
    test("A's slow clip upload and B's quick post both survive", () async {
      await seed(_game(settings: const GameSettings(shareToArena: false)));
      final uploader = _GatedUploader();

      final a = TaskExecutionBloc(
        gameRepository: repoAs(alice),
        videoUploader: uploader,
      );
      final b = TaskExecutionBloc(gameRepository: repoAs(bob));
      final aLoaded = a.stream.firstWhere((s) => s is TaskExecutionLoaded);
      final bLoaded = b.stream.firstWhere((s) => s is TaskExecutionLoaded);
      a.add(const LoadTask(gameId: 'g1', taskIndex: 0, userId: alice));
      b.add(const LoadTask(gameId: 'g1', taskIndex: 0, userId: bob));
      await aLoaded;
      await bLoaded;

      // A starts filming-and-posting: the game is read, the upload hangs.
      final aDone = a.stream.firstWhere(
          (s) => s is TaskExecutionSubmitted || s is TaskExecutionError);
      a.add(SubmitTask(
        gameId: 'g1',
        taskIndex: 0,
        userId: alice,
        video: PickedVideo(
          bytes: Uint8List.fromList(List.filled(64, 1)),
          contentType: 'video/mp4',
        ),
      ));
      await uploader.started.future;

      // Meanwhile B posts a link, and the judge scores the creator.
      final bDone = b.stream.firstWhere(
          (s) => s is TaskExecutionSubmitted || s is TaskExecutionError);
      b.add(const SubmitTask(
        gameId: 'g1',
        taskIndex: 0,
        userId: bob,
        videoUrl: 'https://youtu.be/bob',
      ));
      expect(await bDone, isA<TaskExecutionSubmitted>());
      await repo.judgeSubmission('g1', 0, creator, 5);

      // Now A's upload finishes and A's submission is written.
      uploader.release();
      expect(await aDone, isA<TaskExecutionSubmitted>());
      await a.close();
      await b.close();

      final task = (await read()).tasks[0];
      expect(task.playerStatuses[alice]!.state, TaskPlayerState.submitted);
      expect(task.playerStatuses[bob]!.state, TaskPlayerState.submitted);
      expect(task.playerStatuses[creator]!.state, TaskPlayerState.judged);
      expect(task.submissions.map((s) => s.userId).toSet(),
          {alice, bob, creator});
      expect(
          (await read()).players.firstWhere((p) => p.userId == creator)
              .totalScore,
          5);
    });

    test('a double tap on Post it creates one submission', () async {
      await seed(_game(settings: const GameSettings(shareToArena: false)));
      final bloc = TaskExecutionBloc(gameRepository: repoAs(alice));
      bloc.add(const LoadTask(gameId: 'g1', taskIndex: 0, userId: alice));
      await bloc.stream.firstWhere((s) => s is TaskExecutionLoaded);

      final states = <TaskExecutionState>[];
      final sub = bloc.stream.listen(states.add);
      const tap = SubmitTask(
        gameId: 'g1',
        taskIndex: 0,
        userId: alice,
        text: 'My answer',
      );
      bloc
        ..add(tap)
        ..add(tap);
      await bloc.stream.firstWhere((s) => s is TaskExecutionSubmitted);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();
      await bloc.close();

      expect(states.first, isA<TaskExecutionSubmitting>());
      expect(states.whereType<TaskExecutionSubmitted>().length, 1);
      final task = (await read()).tasks[0];
      expect(task.submissions.where((s) => s.userId == alice).length, 1);
    });
  });

  group('invite codes', () {
    test('createGame retries until no other game holds the code', () async {
      final ds = _TakenCodesDataSource(takenFor: 2);
      final repo = GameRepositoryImpl(ds);
      final id = await repo.createGame('Fresh', creator, creator);

      expect(ds.lookups, 3);
      final game = await repo.getGameStream(id).first;
      expect(game!.inviteCode, ds.lastLookedUp);
      ds.dispose();
    });
  });
}

/// Reports the first [takenFor] invite codes as already in use.
class _TakenCodesDataSource extends MockGameDataSource {
  final int takenFor;
  int lookups = 0;
  String? lastLookedUp;

  _TakenCodesDataSource({required this.takenFor});

  @override
  Future<String?> findGameIdByInviteCode(String inviteCode) async {
    lookups++;
    lastLookedUp = inviteCode;
    return lookups <= takenFor ? 'someone-else' : null;
  }
}
