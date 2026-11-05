import 'dart:math';

import 'package:uuid/uuid.dart';

import '../../../../core/models/game.dart';
import '../../../../core/models/player.dart';
import '../../../../core/models/player_task_status.dart';
import '../../../../core/models/submission.dart';
import '../../../../core/models/task.dart';
import '../../../../core/models/game_settings.dart';
import '../../../../core/models/user.dart';
import '../../../tasks/data/datasources/prebuilt_tasks_data.dart';
import '../../../tasks/data/datasources/starter_pack_data.dart';
import '../../domain/repositories/game_repository.dart';
import '../datasources/game_remote_data_source.dart';

class GameRepositoryImpl implements GameRepository {
  final GameRemoteDataSource remoteDataSource;
  final Uuid _uuid = const Uuid();
  final Random _rng = Random();

  GameRepositoryImpl(this.remoteDataSource);

  @override
  Stream<List<Game>> getGamesStream() {
    return remoteDataSource.getGamesStream().map(
      (gameDataList) => gameDataList.map((data) => Game.fromMap(data)).toList(),
    );
  }

  @override
  Stream<List<Game>> getPublicGamesStream() {
    return remoteDataSource.getPublicGamesStream().map((list) {
      final games = list.map((data) => Game.fromMap(data)).toList();
      // Most-cloned ("popular") first, then newest.
      games.sort((a, b) {
        final byPopularity = b.cloneCount.compareTo(a.cloneCount);
        if (byPopularity != 0) return byPopularity;
        return b.createdAt.compareTo(a.createdAt);
      });
      return games;
    });
  }

  @override
  Stream<List<Game>> getInvitedGamesStream(String email) {
    final normalized = email.toLowerCase();
    return remoteDataSource.getInvitedGamesStream(normalized).map((list) {
      final games = list
          .map((data) => Game.fromMap(data))
          // Only surface games you can still join (lobby). Belt-and-suspenders:
          // re-check the email is actually in invitedEmails in case a data
          // source returns a looser result set.
          .where((g) =>
              g.status == GameStatus.lobby &&
              g.invitedEmails.contains(normalized))
          .toList();
      // Newest invited first (createdAt is our invite-recency proxy).
      games.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return games;
    });
  }

  @override
  Future<String> cloneGame(
      Game template, String creatorId, String displayName) async {
    // New game is private and owned by the cloner; creator is judge by default.
    final gameId = await createGame(template.gameName, creatorId, creatorId);

    // Copy tasks as fresh, unsubmitted tasks (new ids, no submissions/statuses).
    final freshTasks = template.tasks
        .map((t) => Task(
              id: _uuid.v4(),
              title: t.title,
              description: t.description,
              taskType: t.taskType,
              puzzleAnswer: t.puzzleAnswer,
              submissions: const [],
            ))
        .toList();
    await addTasksToGame(gameId, freshTasks);

    // Bump the template's clone counter (popularity signal). Best-effort:
    // never fail a clone if the counter update is rejected.
    // Only the counter is written: firestore.rules lets a non-member bump
    // cloneCount by exactly one on a public game, and nothing else.
    try {
      await _transact(template.id,
          (current, raw) => {'cloneCount': current.cloneCount + 1});
    } catch (_) {}

    return gameId;
  }

  @override
  Future<String> rematchGame(Game source) async {
    // New game doc: same creator, same judge. createGame() starts it in the
    // lobby with a fresh invite code and the creator as the only player.
    final gameId = await createGame(
      _rematchName(source.gameName),
      source.creatorId,
      source.judgeId,
    );

    final data = await remoteDataSource.getGameStream(gameId).first;
    if (data == null) {
      throw Exception('Rematch game not found after creation');
    }
    final fresh = Game.fromMap({...data, 'id': gameId});

    // Same crew, scores wiped. Display names are carried over so nobody shows
    // up as "Creator".
    final players = source.players
        .map((p) => Player(
              userId: p.userId,
              displayName: p.displayName,
              totalScore: 0,
            ))
        .toList();

    // Same task COUNT, freshly-shuffled tasks from the prebuilt catalog (new
    // ids, no submissions/statuses). Fall back to recycling the source's own
    // tasks (as fresh copies) if the catalog is somehow smaller than needed.
    final tasks = _freshShuffledTasks(source);

    await updateGame(gameId, fresh.copyWith(players: players, tasks: tasks));
    return gameId;
  }

  /// "Game Night" → "Game Night — Rematch"; an existing rematch gets a round
  /// counter ("Game Night — Rematch 2") instead of stacking suffixes.
  String _rematchName(String name) {
    final match = RegExp(r'^(.*?) — Rematch(?: (\d+))?$').firstMatch(name);
    if (match == null) return '$name — Rematch';
    final base = match.group(1)!;
    final round = int.tryParse(match.group(2) ?? '1') ?? 1;
    return '$base — Rematch ${round + 1}';
  }

  List<Task> _freshShuffledTasks(Game source) {
    final count = source.tasks.length;
    if (count <= 0) return const [];

    final pool = List<Task>.from(PrebuiltTasksData.getAllTasks())
      ..shuffle(_rng);
    // Avoid handing the crew the exact tasks they just played when the pool
    // has enough alternatives.
    final playedTitles = source.tasks.map((t) => t.title).toSet();
    final unplayed =
        pool.where((t) => !playedTitles.contains(t.title)).toList();
    final picked = (unplayed.length >= count ? unplayed : pool).take(count);

    final fresh = picked
        .map((t) => Task(
              id: _uuid.v4(),
              title: t.title,
              description: t.description,
              taskType: t.taskType,
              puzzleAnswer: t.puzzleAnswer,
              submissions: const [],
            ))
        .toList();
    if (fresh.length >= count) return fresh;

    // Catalog smaller than the source game — top up with fresh copies of the
    // source's own tasks so the rematch still has the same length.
    final recycled = source.tasks.take(count - fresh.length).map((t) => Task(
          id: _uuid.v4(),
          title: t.title,
          description: t.description,
          taskType: t.taskType,
          puzzleAnswer: t.puzzleAnswer,
          submissions: const [],
        ));
    return [...fresh, ...recycled];
  }

  Task _starterTask(String title, String description) => Task(
        id: _uuid.v4(),
        title: title,
        description: description,
        taskType: TaskType.video,
        submissions: const [],
      );

  @override
  Future<void> seedStarterPublicGames(String ownerId, String displayName) async {
    final templates = <MapEntry<String, List<Task>>>[
      MapEntry('Kitchen Chaos', [
        _starterTask('Make the most magnificent sandwich',
            'Use only what is in your kitchen right now. Points for creativity, presentation, and explaining your choices.'),
        _starterTask('The fastest egg',
            'Eat a hard-boiled egg as quickly as possible. Time starts the moment you touch it.'),
        _starterTask('Drink of the gods',
            'Invent and name a new drink using at least three ingredients. Sell it to us.'),
      ]),
      MapEntry('Living Room Olympics', [
        _starterTask('Tallest free-standing tower',
            'Build the tallest tower you can from anything in the room. It must stand on its own for 10 seconds.'),
        _starterTask('Most dramatic slow-motion entrance',
            'Film the most cinematic entrance into a room you can manage.'),
        _starterTask('Invent a sport in 60 seconds',
            'Make up the rules to a brand-new sport and demonstrate one round of play.'),
      ]),
      MapEntry('Creative Genius', [
        _starterTask('Self-portrait from junk',
            'Create a recognizable self-portrait using only random objects you can find.'),
        _starterTask('Four-line poem about a household item',
            'Write it, then perform it with maximum emotion.'),
        _starterTask('The most convincing fake phone call',
            'Hold a one-sided conversation so believable we forget no one is on the line.'),
      ]),
    ];

    for (final entry in templates) {
      final gameId = await createGame(entry.key, ownerId, ownerId);
      await addTasksToGame(gameId, entry.value);
      final data = await remoteDataSource.getGameStream(gameId).first;
      if (data != null) {
        final game = Game.fromMap({...data, 'id': gameId});
        await updateGame(gameId, game.copyWith(isPublic: true));
      }
    }
  }

  @override
  Future<String> createGame(String gameName, String creatorId, String judgeId) async {
    final inviteCode = await _uniqueInviteCode();
    final gameData = {
      'id': _uuid.v4(),
      'gameName': gameName,
      'creatorId': creatorId,
      'judgeId': judgeId,
      'status': GameStatus.lobby.name,
      'inviteCode': inviteCode,
      'createdAt': DateTime.now().toIso8601String(),
      'players': [
        {
          'userId': creatorId,
          'displayName': 'Creator', // Will be updated with actual name
          'totalScore': 0,
        }
      ],
      // Flat participant-id list kept alongside players[] for security rules.
      'playerIds': [creatorId],
      'tasks': [],
      // Add missing required fields
      'mode': GameMode.async.name,
      'settings': {
        'taskDeadlineHours': null,
        'autoAdvanceEnabled': true,
        'allowLateSubmissions': false,
        'taskDeadline': null,
      },
      'currentTaskIndex': 0,
    };

    return await remoteDataSource.createGame(gameData);
  }

  @override
  Future<String> createStarterGame(User user) async {
    final gameId = _uuid.v4();
    final inviteCode = await _uniqueInviteCode();

    final tasks = StarterPackData.tasks()
        .map((task) => task.copyWith(
              status: TaskStatus.waiting_for_submissions,
              playerStatuses: {
                user.id: PlayerTaskStatus(
                  playerId: user.id,
                  state: TaskPlayerState.not_started,
                ),
              },
            ))
        .toList();

    final game = Game(
      id: gameId,
      gameName: StarterPackData.gameName,
      creatorId: user.id,
      // Nominally the creator, but the real judge is the crowd — see
      // GameSettings.crowdJudged and CrowdScoreApplier.
      judgeId: user.id,
      status: GameStatus.inProgress,
      inviteCode: inviteCode,
      createdAt: DateTime.now(),
      players: [
        Player(
          userId: user.id,
          displayName: user.displayName,
          totalScore: 0,
        ),
      ],
      tasks: tasks,
      currentTaskIndex: 0,
      mode: GameMode.async,
      // No per-task deadline: the clock is per player, from the moment they
      // tap Start.
      settings: const GameSettings(
        taskDeadline: null,
        autoAdvanceTasks: true,
        allowSkips: true,
        crowdJudged: true,
        shareToArena: true,
      ),
      gameKind: Game.kindStarter,
    );

    return await remoteDataSource.createGame(game.toMap());
  }

  @override
  Future<void> updateGame(String gameId, Game game) async {
    await remoteDataSource.updateGame(gameId, game.toMap());
  }

  @override
  Future<void> deleteGame(String gameId) async {
    await remoteDataSource.deleteGame(gameId);
  }

  @override
  Stream<Game?> getGameStream(String gameId) {
    return remoteDataSource.getGameStream(gameId).map(
      (data) => data != null ? Game.fromMap(data) : null,
    );
  }

  // ---- Atomic writes ------------------------------------------------------
  //
  // Every write a player (not just the owner) can trigger goes through
  // [_transact]: the game is re-read inside a transaction, the change is
  // applied to THAT copy, and only the touched fields are written. Before
  // this, writers read the game, did slow work, then set(merge) whole arrays
  // back, so concurrent players silently erased each other.

  /// Run [mutate] against the freshest copy of [gameId] inside a transaction.
  /// [mutate] gets both the parsed game and the raw document (the raw lists
  /// are what firestore.rules compares, so roster edits splice those rather
  /// than re-encoding them). Returns the fields to update, or null for none.
  Future<void> _transact(
    String gameId,
    Map<String, dynamic>? Function(Game game, Map<String, dynamic> raw) mutate,
  ) {
    return remoteDataSource.transactGame(gameId, (raw) {
      final game = Game.fromMap({...raw, 'id': gameId});
      return mutate(game, raw);
    });
  }

  static List<Map<String, dynamic>> _encodeTasks(List<Task> tasks) =>
      tasks.map((t) => t.toMap()).toList();

  static List<Map<String, dynamic>> _encodePlayers(List<Player> players) =>
      players.map((p) => p.toMap()).toList();

  static bool _isOwner(Game game, String uid) =>
      uid == game.creatorId || uid == game.judgeId;

  /// Kinds that are created already in progress and still take new players.
  static bool _joinableAfterLobby(Game game) =>
      game.gameKind == Game.kindQuick || game.gameKind == Game.kindStarter;

  @override
  Future<String> joinGame(
      String inviteCode, String userId, String displayName) async {
    final gameId = await remoteDataSource.findGameIdByInviteCode(inviteCode);
    if (gameId == null) {
      throw Exception('Game not found with invite code: $inviteCode');
    }

    await _transact(gameId, (game, raw) {
      // Already in: nothing to do (and nothing to race).
      if (game.players.any((p) => p.userId == userId)) return null;

      if (game.status != GameStatus.lobby && !_joinableAfterLobby(game)) {
        throw const GameJoinException(
            'That game has already started. Ask the host for a rematch.');
      }
      final maxPlayers = game.settings.maxPlayers;
      if (maxPlayers != null && game.players.length >= maxPlayers) {
        throw const GameJoinException('That game is full.');
      }

      // Append to the stored lists untouched: the rules let a non-member
      // add exactly themselves (score 0) and change nothing else.
      final players = List<dynamic>.from(raw['players'] as List? ?? const []);
      final playerIds =
          List<dynamic>.from(raw['playerIds'] as List? ?? game.playerIds);
      players.add(Player(
        userId: userId,
        displayName: displayName,
        totalScore: 0,
      ).toMap());
      playerIds.add(userId);
      return {'players': players, 'playerIds': playerIds};
    });

    return gameId;
  }

  @override
  Future<void> leaveGame(String gameId, String userId) async {
    await _transact(gameId, (game, raw) {
      // No-op if the player wasn't on the roster.
      if (!game.players.any((p) => p.userId == userId)) return null;

      final players = (raw['players'] as List? ?? const [])
          .where((p) => (p as Map)['userId'] != userId)
          .toList();
      final playerIds =
          List<dynamic>.from(raw['playerIds'] as List? ?? game.playerIds)
            ..remove(userId);

      // Drop the leaver from every task, so nobody waits on (or tries to
      // judge) a player who is gone. A task they were the last holdout on
      // moves forward.
      final tasks = game.tasks.map((task) {
        if (!task.playerStatuses.containsKey(userId)) return task;
        var updated = task.copyWith(
          playerStatuses: Map.of(task.playerStatuses)..remove(userId),
        );
        if (updated.status != TaskStatus.completed) {
          if (updated.allPlayersJudged) {
            updated = updated.copyWith(status: TaskStatus.completed);
          } else if (updated.allPlayersSubmitted) {
            updated = updated.copyWith(status: TaskStatus.ready_to_judge);
          }
        }
        return updated;
      }).toList();

      return {
        'players': players,
        'playerIds': playerIds,
        'tasks': _encodeTasks(tasks),
      };
    });
  }

  @override
  Future<void> startGame(String gameId) async {
    await _transact(gameId, (gameObj, raw) {
      // Only a lobby game starts. A second tap (or a second device) must not
      // re-seed statuses over submissions already made.
      if (gameObj.status != GameStatus.lobby) return null;

      if (gameObj.players.length < 2) {
        throw Exception('Need at least 2 players to start');
      }
      if (gameObj.tasks.isEmpty) {
        throw Exception('Need at least 1 task to start');
      }

      // Initialize playerStatuses for all tasks. When the judge doesn't play
      // (settings.judgePlays == false, e.g. House Hunt where the hider only
      // judges), skip the judge: a seeded status they never fulfil would
      // keep allPlayersJudged false forever. Guard: only skip when someone
      // else is actually playing, so a solo judge-is-the-player game works.
      final contestants = _contestantsOf(gameObj);
      final updatedTasks = gameObj.tasks.map((task) {
        final playerStatuses = <String, PlayerTaskStatus>{
          for (final player in contestants)
            player.userId: PlayerTaskStatus(
              playerId: player.userId,
              state: TaskPlayerState.not_started,
            ),
        };
        return task.copyWith(
          playerStatuses: playerStatuses,
          status: TaskStatus.waiting_for_submissions,
        );
      }).toList();

      // Deadline for the first task (if settings specify one).
      final taskDeadline = gameObj.settings.taskDeadline;
      if (taskDeadline != null) {
        updatedTasks[0] = updatedTasks[0]
            .copyWith(deadline: DateTime.now().add(taskDeadline));
      }

      return {
        'status': GameStatus.inProgress.name,
        'tasks': _encodeTasks(updatedTasks),
        'currentTaskIndex': 0,
      };
    });
  }

  @override
  Future<void> updateTaskAtomically(
    String gameId,
    int taskIndex,
    Task Function(Task fresh) mutate,
  ) async {
    await _transact(gameId, (game, raw) {
      if (taskIndex < 0 || taskIndex >= game.tasks.length) {
        throw Exception('Task not found');
      }
      final tasks = List<Task>.from(game.tasks);
      tasks[taskIndex] = mutate(tasks[taskIndex]);
      return {'tasks': _encodeTasks(tasks)};
    });
  }

  @override
  Future<void> advanceToTask(String gameId, int taskIndex,
      {required String callerId}) async {
    await _transact(gameId, (game, raw) {
      if (!_isOwner(game, callerId)) return null;
      // Forward only, and never past the end: every viewer's countdown may
      // fire, and a late one must not drag the game backwards.
      if (taskIndex <= game.currentTaskIndex) return null;
      if (taskIndex >= game.tasks.length) return null;
      return {'currentTaskIndex': taskIndex};
    });
  }

  @override
  Future<void> completeGame(String gameId, {required String callerId}) async {
    await _transact(gameId, (game, raw) {
      if (!_isOwner(game, callerId)) return null;
      if (game.status == GameStatus.completed) return null;
      return {'status': GameStatus.completed.name};
    });
  }

  /// The players expected to submit to tasks. Everyone, unless the game says
  /// the judge doesn't play — then the judge is left out, provided at least
  /// one other player exists (a solo creator-judge still plays their own game).
  List<Player> _contestantsOf(Game game) {
    if (game.settings.judgePlays) return game.players;
    final others =
        game.players.where((p) => p.userId != game.judgeId).toList();
    return others.isEmpty ? game.players : others;
  }

  @override
  Future<void> addTasksToGame(String gameId, List<Task> tasks) async {
    if (tasks.isEmpty) return;

    final data = await remoteDataSource.getGameStream(gameId).first;
    if (data == null) {
      throw Exception('Game not found');
    }
    final game = Game.fromMap({...data, 'id': gameId});

    // Skip tasks already on the game (by id) so this is safe to call twice.
    final existingIds = game.tasks.map((t) => t.id).toSet();
    var newTasks = tasks.where((t) => !existingIds.contains(t.id)).toList();
    if (newTasks.isEmpty) return;

    // If the game is already in progress, seed per-player statuses for the new
    // tasks (mirroring startGame). Without this, submitting against a task that
    // was added mid-game fails with "Player status not found".
    if (game.status == GameStatus.inProgress && game.players.isNotEmpty) {
      final seededStatuses = <String, PlayerTaskStatus>{
        for (final player in _contestantsOf(game))
          player.userId: PlayerTaskStatus(
            playerId: player.userId,
            state: TaskPlayerState.not_started,
          ),
      };
      newTasks = newTasks
          .map((t) => t.copyWith(
                playerStatuses: seededStatuses,
                status: TaskStatus.waiting_for_submissions,
              ))
          .toList();
    }

    await updateGame(
      gameId,
      game.copyWith(tasks: [...game.tasks, ...newTasks]),
    );
  }

  @override
  Future<void> submitTaskAnswer(
      String gameId, String taskId, Submission submission) async {
    await _transact(gameId, (game, raw) {
      final taskIndex = game.tasks.indexWhere((t) => t.id == taskId);
      if (taskIndex == -1) {
        throw Exception('Task not found');
      }
      final task = game.tasks[taskIndex];

      // Record the submission and mark the submitting player's status.
      final statuses = Map<String, PlayerTaskStatus>.from(task.playerStatuses);
      final existing = statuses[submission.userId] ??
          PlayerTaskStatus(
            playerId: submission.userId,
            state: TaskPlayerState.not_started,
          );
      statuses[submission.userId] = existing.copyWith(
        state: TaskPlayerState.submitted,
        submittedAt: DateTime.now(),
        submissionUrl: submission.videoUrl,
      );

      // One submission per player: a resubmission replaces the earlier one.
      final submissions = [
        ...task.submissions.where((s) => s.userId != submission.userId),
        submission,
      ];

      var updatedTask = task.copyWith(
        submissions: submissions,
        playerStatuses: statuses,
      );

      // Advance the task to ready_to_judge once every player has submitted.
      if (updatedTask.allPlayersSubmitted &&
          updatedTask.status == TaskStatus.waiting_for_submissions) {
        updatedTask = updatedTask.copyWith(status: TaskStatus.ready_to_judge);
      }

      final tasks = List<Task>.from(game.tasks);
      tasks[taskIndex] = updatedTask;
      return {'tasks': _encodeTasks(tasks)};
    });
  }

  @override
  Future<void> judgeSubmission(
      String gameId, int taskIndex, String playerId, int score) async {
    await _transact(gameId, (game, raw) {
      if (taskIndex >= game.tasks.length) {
        throw Exception('Task not found');
      }
      return _scoreUpdates(game, taskIndex, playerId, score);
    });
  }

  @override
  Future<void> submitArResult(
    String gameId,
    int taskIndex,
    String playerId,
    int score, {
    int? rawResult,
  }) async {
    await _transact(gameId, (game, raw) {
      if (taskIndex >= game.tasks.length) {
        throw Exception('Task not found');
      }

      // The judge/creator (solo play, Quick Play) self-judges instantly.
      if (_isOwner(game, playerId)) {
        return _scoreUpdates(game, taskIndex, playerId, score,
            rawResult: rawResult);
      }

      // Anyone else may not write scores (firestore.rules: only the judge or
      // creator touches players[].totalScore). Record the AR result as a
      // submission carrying its score; the judge confirms it.
      final task = game.tasks[taskIndex];
      final status = task.playerStatuses[playerId] ??
          PlayerTaskStatus(
            playerId: playerId,
            state: TaskPlayerState.not_started,
          );
      final now = DateTime.now();
      final statuses = Map<String, PlayerTaskStatus>.from(task.playerStatuses)
        ..[playerId] = status.copyWith(
          state: TaskPlayerState.submitted,
          submittedAt: status.submittedAt ?? now,
          score: score,
        );

      final submissions = List<Submission>.from(task.submissions);
      final subIndex = submissions.indexWhere((s) => s.userId == playerId);
      if (subIndex != -1) {
        submissions[subIndex] =
            submissions[subIndex].copyWith(score: score, isJudged: false);
      } else {
        submissions.add(Submission(
          id: _uuid.v4(),
          userId: playerId,
          videoUrl: status.submissionUrl,
          score: score,
          isJudged: false,
          submittedAt: status.submittedAt ?? now,
        ));
      }

      var updatedTask = task.copyWith(
        playerStatuses: statuses,
        submissions: submissions,
        arResult: rawResult ?? task.arResult,
      );
      if (updatedTask.status == TaskStatus.waiting_for_submissions &&
          updatedTask.allPlayersSubmitted) {
        updatedTask = updatedTask.copyWith(status: TaskStatus.ready_to_judge);
      }

      final tasks = List<Task>.from(game.tasks);
      tasks[taskIndex] = updatedTask;
      return {'tasks': _encodeTasks(tasks)};
    });
  }

  /// The scoreboard mutation shared by [judgeSubmission] and an owner's AR
  /// self-judge: stamp [playerId] judged with [score] on task [taskIndex],
  /// keep the submission row in step, move the player's total by the CHANGE
  /// in their score for this task, and roll the task / game forward.
  Map<String, dynamic> _scoreUpdates(
    Game game,
    int taskIndex,
    String playerId,
    int score, {
    int? rawResult,
  }) {
    final task = game.tasks[taskIndex];
    final now = DateTime.now();

    // Tolerate a missing status (e.g. a player added mid-game) by treating
    // it as a fresh, not-started status instead of throwing.
    final playerStatus = task.playerStatuses[playerId] ??
        PlayerTaskStatus(
          playerId: playerId,
          state: TaskPlayerState.not_started,
        );

    // Re-judging (re-opened judging, a second device, a crowd score landing
    // twice) replaces the earlier score rather than adding to it.
    final previousScore =
        playerStatus.isJudged ? (playerStatus.score ?? 0) : 0;

    final statuses = Map<String, PlayerTaskStatus>.from(task.playerStatuses)
      ..[playerId] = playerStatus.copyWith(
        score: score,
        state: TaskPlayerState.judged,
        submittedAt: playerStatus.submittedAt ?? now,
        scoredAt: now,
      );

    // Keystone: keep the dual submission model in sync. Scoring writes the
    // per-player status above; here we also stamp the matching entry in
    // task.submissions so completion/scoreboard logic (which reads
    // submissions[].isJudged/score) agrees. If no submission row exists yet
    // (the task-execution flow only writes playerStatuses), create one from
    // the player's status so the task can actually complete.
    final submissions = List<Submission>.from(task.submissions);
    final subIndex = submissions.indexWhere((s) => s.userId == playerId);
    if (subIndex != -1) {
      submissions[subIndex] =
          submissions[subIndex].copyWith(score: score, isJudged: true);
    } else {
      submissions.add(Submission(
        id: _uuid.v4(),
        userId: playerId,
        videoUrl: playerStatus.submissionUrl,
        score: score,
        isJudged: true,
        submittedAt: playerStatus.submittedAt ?? now,
      ));
    }

    var updatedTask = task.copyWith(
      playerStatuses: statuses,
      submissions: submissions,
      arResult: rawResult ?? task.arResult,
    );
    if (updatedTask.allPlayersJudged) {
      updatedTask = updatedTask.copyWith(status: TaskStatus.completed);
    } else if (updatedTask.allPlayersSubmitted) {
      updatedTask = updatedTask.copyWith(status: TaskStatus.ready_to_judge);
    }

    final tasks = List<Task>.from(game.tasks);
    tasks[taskIndex] = updatedTask;

    final delta = score - previousScore;
    final players = game.players
        .map((p) => p.userId == playerId
            ? p.copyWith(totalScore: p.totalScore + delta)
            : p)
        .toList();

    final updates = <String, dynamic>{
      'tasks': _encodeTasks(tasks),
      'players': _encodePlayers(players),
    };
    // When every task is completed, the whole game is completed.
    if (tasks.isNotEmpty &&
        tasks.every((t) => t.status == TaskStatus.completed)) {
      updates['status'] = GameStatus.completed.name;
    }
    return updates;
  }

  /// A fresh invite code no other game is using.
  Future<String> _uniqueInviteCode() async {
    for (var attempt = 0; attempt < 10; attempt++) {
      final code = _generateInviteCode();
      if (await remoteDataSource.findGameIdByInviteCode(code) == null) {
        return code;
      }
    }
    throw Exception('Could not find a free invite code. Please try again.');
  }

  String _generateInviteCode() {
    // 6 random chars. Each position is independently random (the old code
    // computed one modulo and reused it, so every code was 6 identical
    // characters, e.g. "ZZZZZZ"). Ambiguous look-alikes (0/O, 1/I/L) are
    // dropped so codes are easy to read and type.
    const chars = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    return List.generate(6, (_) => chars[_rng.nextInt(chars.length)]).join();
  }
}