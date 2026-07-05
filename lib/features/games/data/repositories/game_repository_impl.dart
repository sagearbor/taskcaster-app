import 'dart:math';

import 'package:uuid/uuid.dart';

import '../../../../core/models/game.dart';
import '../../../../core/models/player.dart';
import '../../../../core/models/player_task_status.dart';
import '../../../../core/models/submission.dart';
import '../../../../core/models/task.dart';
import '../../../tasks/data/datasources/prebuilt_tasks_data.dart';
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
    try {
      final data = await remoteDataSource.getGameStream(template.id).first;
      if (data != null) {
        final current = Game.fromMap({...data, 'id': template.id});
        await updateGame(
          template.id,
          current.copyWith(cloneCount: current.cloneCount + 1),
        );
      }
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
    final gameData = {
      'id': _uuid.v4(),
      'gameName': gameName,
      'creatorId': creatorId,
      'judgeId': judgeId,
      'status': GameStatus.lobby.name,
      'inviteCode': _generateInviteCode(),
      'createdAt': DateTime.now().toIso8601String(),
      'players': [
        {
          'userId': creatorId,
          'displayName': 'Creator', // Will be updated with actual name
          'totalScore': 0,
        }
      ],
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

  @override
  Future<String> joinGame(String inviteCode, String userId, String displayName) async {
    final gameId = await remoteDataSource.joinGame(inviteCode, userId);

    // Add the player to the roster if not already present. Idempotent: if the
    // data source (e.g. Firestore) already added the player, this is a no-op,
    // which avoids double-adding across the mock and real implementations.
    final data = await remoteDataSource.getGameStream(gameId).first;
    if (data != null) {
      final game = Game.fromMap({...data, 'id': gameId});
      final alreadyJoined = game.players.any((p) => p.userId == userId);
      if (!alreadyJoined) {
        final updated = game.copyWith(players: [
          ...game.players,
          Player(userId: userId, displayName: displayName, totalScore: 0),
        ]);
        await updateGame(gameId, updated);
      }
    }

    return gameId;
  }

  @override
  Future<void> leaveGame(String gameId, String userId) async {
    final data = await remoteDataSource.getGameStream(gameId).first;
    if (data == null) {
      throw Exception('Game not found');
    }
    final game = Game.fromMap({...data, 'id': gameId});

    final remaining =
        game.players.where((p) => p.userId != userId).toList();
    // No-op if the player wasn't on the roster.
    if (remaining.length == game.players.length) return;

    await updateGame(gameId, game.copyWith(players: remaining));
  }

  @override
  Future<void> startGame(String gameId) async {
    // Load the current game state
    final game = await remoteDataSource.getGameStream(gameId).first;

    if (game == null) {
      throw Exception('Game not found');
    }

    // Convert from map to Game object
    final gameObj = Game.fromMap({...game, 'id': gameId});

    // Validate game can be started
    if (gameObj.players.length < 2) {
      throw Exception('Need at least 2 players to start');
    }

    if (gameObj.tasks.isEmpty) {
      throw Exception('Need at least 1 task to start');
    }

    // Initialize playerStatuses for all tasks
    final updatedTasks = gameObj.tasks.map((task) {
      final playerStatuses = <String, PlayerTaskStatus>{};

      for (final player in gameObj.players) {
        playerStatuses[player.userId] = PlayerTaskStatus(
          playerId: player.userId,
          state: TaskPlayerState.not_started,
        );
      }

      return task.copyWith(
        playerStatuses: playerStatuses,
        status: TaskStatus.waiting_for_submissions,
      );
    }).toList();

    // Calculate deadline for first task (if settings specify)
    DateTime? firstTaskDeadline;
    if (gameObj.settings.taskDeadline != null) {
      firstTaskDeadline = DateTime.now().add(gameObj.settings.taskDeadline!);
    }

    // Update first task with deadline
    if (updatedTasks.isNotEmpty && firstTaskDeadline != null) {
      updatedTasks[0] = updatedTasks[0].copyWith(deadline: firstTaskDeadline);
    }

    // Update game to in-progress with initialized tasks
    final updatedGame = gameObj.copyWith(
      status: GameStatus.inProgress,
      tasks: updatedTasks,
      currentTaskIndex: 0,
    );

    await updateGame(gameId, updatedGame);
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
        for (final player in game.players)
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
    final data = await remoteDataSource.getGameStream(gameId).first;
    if (data == null) {
      throw Exception('Game not found');
    }
    final game = Game.fromMap({...data, 'id': gameId});

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

    final updatedTasks = List<Task>.from(game.tasks);
    var updatedTask = task.copyWith(
      submissions: [...task.submissions, submission],
      playerStatuses: statuses,
    );

    // Advance the task to ready_to_judge once every player has submitted.
    if (updatedTask.allPlayersSubmitted &&
        updatedTask.status == TaskStatus.waiting_for_submissions) {
      updatedTask = updatedTask.copyWith(status: TaskStatus.ready_to_judge);
    }

    updatedTasks[taskIndex] = updatedTask;

    await updateGame(gameId, game.copyWith(tasks: updatedTasks));
  }

  @override
  Future<void> judgeSubmission(String gameId, int taskIndex, String playerId, int score) async {
    // Load current game
    final game = await remoteDataSource.getGameStream(gameId).first;
    if (game == null) {
      throw Exception('Game not found');
    }

    final gameObj = Game.fromMap({...game, 'id': gameId});

    if (taskIndex >= gameObj.tasks.length) {
      throw Exception('Task not found');
    }

    // Update the task's player status with the score
    final updatedTasks = List<Task>.from(gameObj.tasks);
    final task = updatedTasks[taskIndex];

    final updatedPlayerStatuses = Map<String, PlayerTaskStatus>.from(task.playerStatuses);
    // Tolerate a missing status (e.g. a player added mid-game) by treating it
    // as a fresh, not-started status instead of throwing.
    final playerStatus = updatedPlayerStatuses[playerId] ??
        PlayerTaskStatus(
          playerId: playerId,
          state: TaskPlayerState.not_started,
        );

    // Update player status with score.
    updatedPlayerStatuses[playerId] = playerStatus.copyWith(
      score: score,
      state: TaskPlayerState.judged,
      scoredAt: DateTime.now(),
    );

    // Keystone: keep the dual submission model in sync. Scoring writes the
    // per-player status above; here we also stamp the matching entry in
    // task.submissions so completion/scoreboard logic (which reads
    // submissions[].isJudged/score) agrees. If no submission row exists yet
    // (the task-execution flow only writes playerStatuses), create one from
    // the player's status so the task can actually complete.
    final updatedSubmissions = List<Submission>.from(task.submissions);
    final subIndex =
        updatedSubmissions.indexWhere((s) => s.userId == playerId);
    if (subIndex != -1) {
      updatedSubmissions[subIndex] = updatedSubmissions[subIndex].copyWith(
        score: score,
        isJudged: true,
      );
    } else {
      updatedSubmissions.add(Submission(
        id: _uuid.v4(),
        userId: playerId,
        videoUrl: playerStatus.submissionUrl,
        score: score,
        isJudged: true,
        submittedAt: playerStatus.submittedAt ?? DateTime.now(),
      ));
    }

    // Update task with new player statuses + submissions, then advance status.
    var updatedTask = task.copyWith(
      playerStatuses: updatedPlayerStatuses,
      submissions: updatedSubmissions,
    );

    if (updatedTask.allPlayersJudged) {
      updatedTask = updatedTask.copyWith(status: TaskStatus.completed);
    } else if (updatedTask.allPlayersSubmitted) {
      updatedTask = updatedTask.copyWith(status: TaskStatus.ready_to_judge);
    }

    updatedTasks[taskIndex] = updatedTask;

    // Update player's total score.
    final updatedPlayers = gameObj.players.map((player) {
      if (player.userId == playerId) {
        return player.copyWith(
          totalScore: player.totalScore + score,
        );
      }
      return player;
    }).toList();

    // Update game with new tasks and players. When every task is completed,
    // the whole game is completed.
    var updatedGame = gameObj.copyWith(
      tasks: updatedTasks,
      players: updatedPlayers,
    );

    if (updatedGame.tasks.isNotEmpty &&
        updatedGame.tasks.every((t) => t.status == TaskStatus.completed)) {
      updatedGame = updatedGame.copyWith(status: GameStatus.completed);
    }

    await updateGame(gameId, updatedGame);
  }

  @override
  Future<void> submitArResult(
    String gameId,
    int taskIndex,
    String playerId,
    int score, {
    int? rawResult,
  }) async {
    // Load current game.
    final game = await remoteDataSource.getGameStream(gameId).first;
    if (game == null) {
      throw Exception('Game not found');
    }

    final gameObj = Game.fromMap({...game, 'id': gameId});

    if (taskIndex >= gameObj.tasks.length) {
      throw Exception('Task not found');
    }

    final updatedTasks = List<Task>.from(gameObj.tasks);
    final task = updatedTasks[taskIndex];

    // AR is an instant self-judge: stamp the player's status straight to
    // judged (mirroring judgeSubmission), tolerating a missing status.
    final updatedPlayerStatuses =
        Map<String, PlayerTaskStatus>.from(task.playerStatuses);
    final playerStatus = updatedPlayerStatuses[playerId] ??
        PlayerTaskStatus(
          playerId: playerId,
          state: TaskPlayerState.not_started,
        );

    updatedPlayerStatuses[playerId] = playerStatus.copyWith(
      score: score,
      state: TaskPlayerState.judged,
      submittedAt: playerStatus.submittedAt ?? DateTime.now(),
      scoredAt: DateTime.now(),
    );

    // Keep the dual submission model in sync, exactly like judgeSubmission:
    // stamp the matching submission row, or synthesize one if none exists
    // (AR players never go through the video-submission flow).
    final updatedSubmissions = List<Submission>.from(task.submissions);
    final subIndex =
        updatedSubmissions.indexWhere((s) => s.userId == playerId);
    if (subIndex != -1) {
      updatedSubmissions[subIndex] = updatedSubmissions[subIndex].copyWith(
        score: score,
        isJudged: true,
      );
    } else {
      updatedSubmissions.add(Submission(
        id: _uuid.v4(),
        userId: playerId,
        videoUrl: playerStatus.submissionUrl,
        score: score,
        isJudged: true,
        submittedAt: playerStatus.submittedAt ?? DateTime.now(),
      ));
    }

    var updatedTask = task.copyWith(
      playerStatuses: updatedPlayerStatuses,
      submissions: updatedSubmissions,
      // Record the raw AR gameplay result for display/analytics.
      arResult: rawResult ?? task.arResult,
    );

    if (updatedTask.allPlayersJudged) {
      updatedTask = updatedTask.copyWith(status: TaskStatus.completed);
    } else if (updatedTask.allPlayersSubmitted) {
      updatedTask = updatedTask.copyWith(status: TaskStatus.ready_to_judge);
    }

    updatedTasks[taskIndex] = updatedTask;

    // Bump the player's total score.
    final updatedPlayers = gameObj.players.map((player) {
      if (player.userId == playerId) {
        return player.copyWith(totalScore: player.totalScore + score);
      }
      return player;
    }).toList();

    var updatedGame = gameObj.copyWith(
      tasks: updatedTasks,
      players: updatedPlayers,
    );

    if (updatedGame.tasks.isNotEmpty &&
        updatedGame.tasks.every((t) => t.status == TaskStatus.completed)) {
      updatedGame = updatedGame.copyWith(status: GameStatus.completed);
    }

    await updateGame(gameId, updatedGame);
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