import 'dart:async';

import '../../../../core/models/game.dart';
import '../../../../core/models/player_task_status.dart';
import '../../domain/peer_grading.dart';
import 'game_remote_data_source.dart';

class MockGameDataSource implements GameRemoteDataSource {
  final StreamController<List<Map<String, dynamic>>> _gamesController = 
      StreamController<List<Map<String, dynamic>>>.broadcast();
  
  final Map<String, StreamController<Map<String, dynamic>?>> _gameControllers = {};
  
  final List<Map<String, dynamic>> _games = [];

  MockGameDataSource() {
    _initializeMockGames();
  }

  void _initializeMockGames() {
    final mockGames = [
      {
        'id': 'game_1',
        'gameName': 'Saturday Night Shenanigans',
        'creatorId': 'user_123',
        'judgeId': 'user_456',
        'status': 'lobby',
        'inviteCode': 'PARTY1',
        'createdAt': DateTime.now().subtract(const Duration(hours: 2)).toIso8601String(),
        'players': [
          {'userId': 'user_123', 'displayName': 'Alice the Creator', 'totalScore': 0},
          {'userId': 'user_456', 'displayName': 'Bob the Judge', 'totalScore': 0},
          {'userId': 'user_789', 'displayName': 'Charlie', 'totalScore': 0},
        ],
        'tasks': [
          {
            'id': 'task_1',
            'title': 'Make the most magnificent sandwich',
            'description': 'Create a sandwich using only items you can find in your kitchen right now. Points for creativity, presentation, and explaining your choices.',
            'taskType': 'video',
            'puzzleAnswer': null,
            'submissions': []
          },
          {
            'id': 'task_2',
            'title': 'Wear the most items of clothing',
            'description': 'Put on as many individual items of clothing as possible. Each item must be visible and properly worn.',
            'taskType': 'video',
            'puzzleAnswer': null,
            'submissions': []
          }
        ]
      },
      {
        'id': 'game_2',
        'gameName': 'Family Game Night',
        'creatorId': 'user_789',
        'judgeId': 'user_101',
        'status': 'inProgress',
        'inviteCode': 'FAMILY',
        'createdAt': DateTime.now().subtract(const Duration(hours: 1)).toIso8601String(),
        'players': [
          {'userId': 'user_789', 'displayName': 'Charlie', 'totalScore': 15},
          {'userId': 'user_101', 'displayName': 'Diana the Judge', 'totalScore': 0},
          {'userId': 'user_202', 'displayName': 'Eve', 'totalScore': 12},
          {'userId': 'user_303', 'displayName': 'Frank', 'totalScore': 8},
        ],
        'tasks': [
          {
            'id': 'task_3',
            'title': 'Build the tallest tower',
            'description': 'Using only books, build the tallest possible tower that can stand for at least 10 seconds.',
            'taskType': 'video',
            'puzzleAnswer': null,
            'submissions': [
              {
                'id': 'sub_1',
                'userId': 'user_789',
                'videoUrl': 'https://youtube.com/watch?v=fake1',
                'textAnswer': null,
                'score': 5,
                'isJudged': true,
                'submittedAt': DateTime.now().subtract(const Duration(minutes: 30)).toIso8601String(),
              },
              {
                'id': 'sub_2',
                'userId': 'user_202',
                'videoUrl': 'https://youtube.com/watch?v=fake2',
                'textAnswer': null,
                'score': 4,
                'isJudged': true,
                'submittedAt': DateTime.now().subtract(const Duration(minutes: 25)).toIso8601String(),
              }
            ]
          }
        ]
      },
      {
        'id': 'game_3',
        'gameName': 'Office Competition',
        'creatorId': 'user_404',
        'judgeId': 'user_505',
        'status': 'completed',
        'inviteCode': 'OFFICE',
        'createdAt': DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
        'players': [
          {'userId': 'user_404', 'displayName': 'Grace', 'totalScore': 22},
          {'userId': 'user_505', 'displayName': 'Henry the Judge', 'totalScore': 0},
          {'userId': 'user_606', 'displayName': 'Ivy', 'totalScore': 18},
          {'userId': 'user_707', 'displayName': 'Jack', 'totalScore': 25},
        ],
        'tasks': [
          {
            'id': 'task_4',
            'title': 'Draw a self-portrait using only office supplies',
            'description': 'Create a recognizable self-portrait using only items you can find in an office.',
            'taskType': 'video',
            'puzzleAnswer': null,
            'submissions': []
          }
        ]
      },
      // --- Public template games (discoverable in the gallery) ---
      {
        'id': 'game_public_warriors',
        'gameName': 'Weekend Warriors',
        'creatorId': 'taskcaster_official',
        'judgeId': 'taskcaster_official',
        'status': 'inProgress',
        'inviteCode': 'WARRIOR',
        'isPublic': true,
        'createdAt': DateTime.now().subtract(const Duration(days: 2)).toIso8601String(),
        'players': [
          {'userId': 'taskcaster_official', 'displayName': 'TaskCaster', 'totalScore': 0},
          {'userId': 'demo_player_1', 'displayName': 'Sam', 'totalScore': 0},
        ],
        'tasks': [
          {
            'id': 'task_pw_1',
            'title': 'Build the tallest free-standing structure',
            'description': 'Use anything in the room. It must stand on its own for 10 seconds.',
            'taskType': 'video',
            'puzzleAnswer': null,
            'submissions': []
          },
          {
            'id': 'task_pw_2',
            'title': 'Most dramatic slow-motion entrance',
            'description': 'Film the most cinematic entrance into a room you can manage.',
            'taskType': 'video',
            'puzzleAnswer': null,
            'submissions': []
          }
        ]
      },
      {
        'id': 'game_public_epic',
        'gameName': 'Epic Adventure',
        'creatorId': 'taskcaster_official',
        'judgeId': 'taskcaster_official',
        'status': 'lobby',
        'inviteCode': 'EPIC',
        'isPublic': true,
        'createdAt': DateTime.now().subtract(const Duration(days: 3)).toIso8601String(),
        'players': [
          {'userId': 'taskcaster_official', 'displayName': 'TaskCaster', 'totalScore': 0},
        ],
        'tasks': [
          {
            'id': 'task_pe_1',
            'title': 'Create a treasure map to a hidden object',
            'description': 'Hide something, then draw a map that leads a friend to it.',
            'taskType': 'video',
            'puzzleAnswer': null,
            'submissions': []
          },
          {
            'id': 'task_pe_2',
            'title': 'Invent a new sport in 60 seconds',
            'description': 'Make up the rules and demonstrate one round of play.',
            'taskType': 'video',
            'puzzleAnswer': null,
            'submissions': []
          },
          {
            'id': 'task_pe_3',
            'title': 'The most convincing fake phone call',
            'description': 'Have a one-sided conversation so believable we forget no one is there.',
            'taskType': 'video',
            'puzzleAnswer': null,
            'submissions': []
          }
        ]
      }
    ];

    _games.addAll(mockGames);
    _gamesController.add(_games);
  }

  @override
  Stream<List<Map<String, dynamic>>> getGamesStream() async* {
    // Emit initial data immediately
    yield List.from(_games);
    // Then emit all future updates
    await for (final games in _gamesController.stream) {
      yield games;
    }
  }

  @override
  Stream<List<Map<String, dynamic>>> getPublicGamesStream() async* {
    List<Map<String, dynamic>> publicOnly(List<Map<String, dynamic>> all) =>
        all.where((g) => g['isPublic'] == true).toList();

    yield publicOnly(_games);
    await for (final games in _gamesController.stream) {
      yield publicOnly(games);
    }
  }

  @override
  Stream<List<Map<String, dynamic>>> getInvitedGamesStream(String email) async* {
    final target = email.toLowerCase();
    List<Map<String, dynamic>> invitedOnly(List<Map<String, dynamic>> all) =>
        all.where((g) {
          final invited = (g['invitedEmails'] as List<dynamic>?) ?? const [];
          return invited
              .map((e) => (e as String).toLowerCase())
              .contains(target);
        }).toList();

    yield invitedOnly(_games);
    await for (final games in _gamesController.stream) {
      yield invitedOnly(games);
    }
  }

  @override
  Future<String> createGame(Map<String, dynamic> gameData) async {
    await Future.delayed(const Duration(milliseconds: 500));
    
    _games.add(gameData);
    _gamesController.add(List.from(_games));
    
    return gameData['id'] as String;
  }

  @override
  Future<bool> createGameIfAbsent(
      String gameId, Map<String, dynamic> gameData) async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (_games.any((game) => game['id'] == gameId)) return false;
    _games.add({...gameData, 'id': gameId});
    _gamesController.add(List.from(_games));
    return true;
  }

  @override
  Future<void> updateGame(String gameId, Map<String, dynamic> updates) async {
    await Future.delayed(const Duration(milliseconds: 300));
    
    final gameIndex = _games.indexWhere((game) => game['id'] == gameId);
    if (gameIndex != -1) {
      _games[gameIndex] = {..._games[gameIndex], ...updates};
      _gamesController.add(List.from(_games));
      
      // Update individual game stream if it exists
      if (_gameControllers.containsKey(gameId)) {
        _gameControllers[gameId]!.add(_games[gameIndex]);
      }
    }
  }

  @override
  Future<void> deleteGame(String gameId) async {
    await Future.delayed(const Duration(milliseconds: 300));
    
    _games.removeWhere((game) => game['id'] == gameId);
    _gamesController.add(List.from(_games));
    
    // Close individual game stream if it exists
    if (_gameControllers.containsKey(gameId)) {
      _gameControllers[gameId]!.add(null);
      _gameControllers[gameId]!.close();
      _gameControllers.remove(gameId);
    }
  }

  @override
  Stream<Map<String, dynamic>?> getGameStream(String gameId) async* {
    // Find and emit initial data immediately
    final game = _games.firstWhere(
      (game) => game['id'] == gameId,
      orElse: () => {},
    );

    if (game.isNotEmpty) {
      yield game;
    } else {
      yield null;
    }

    // Set up controller for future updates if not exists
    if (!_gameControllers.containsKey(gameId)) {
      _gameControllers[gameId] = StreamController<Map<String, dynamic>?>.broadcast();
    }

    // Yield all future updates from the controller
    await for (final updatedGame in _gameControllers[gameId]!.stream) {
      yield updatedGame;
    }
  }

  @override
  Future<String?> findGameIdByInviteCode(String inviteCode) async {
    await Future.delayed(const Duration(milliseconds: 100));
    for (final game in _games) {
      if (game['inviteCode'] == inviteCode) return game['id'] as String;
    }
    return null;
  }

  @override
  Future<void> transactGame(String gameId, GameMutation mutate) async {
    // Simulated latency goes BEFORE the read: from read to write there is no
    // await, so (on the single-threaded event loop) the update is atomic,
    // just like a Firestore transaction.
    await Future.delayed(const Duration(milliseconds: 100));

    final gameIndex = _games.indexWhere((game) => game['id'] == gameId);
    if (gameIndex == -1) {
      throw Exception('Game not found');
    }
    final updates = mutate(Map<String, dynamic>.from(_games[gameIndex]));
    if (updates == null || updates.isEmpty) return;

    _games[gameIndex] = {..._games[gameIndex], ...updates};
    _gamesController.add(List.from(_games));
    _gameControllers[gameId]?.add(_games[gameIndex]);
  }

  /// peer_grades per game: gradeId -> grade.
  final Map<String, Map<String, PeerGrade>> _peerGrades = {};

  /// The server's ledger per game: '{taskId}__{uid}' -> locked points.
  final Map<String, Map<String, int>> _peerResults = {};

  /// The clock the mock's settle pass reads (tests move it past 24 h).
  DateTime Function() clock = DateTime.now;

  /// Mirrors firestore.rules (create-only, one per task/entry/grader, never
  /// yourself, only once both have posted) and then the onPeerGradeCreated
  /// Function (functions/src/peer_grading.js), so a group game plays to the
  /// end offline exactly as it does against Firebase.
  @override
  Future<void> createPeerGrade(
      String gameId, String gradeId, Map<String, dynamic> data) async {
    await Future.delayed(const Duration(milliseconds: 100));
    final grades = _peerGrades.putIfAbsent(gameId, () => {});
    if (grades.containsKey(gradeId)) {
      throw StateError('permission-denied: already graded');
    }
    final grade = PeerGrade(
      taskId: data['taskId'] as String,
      taskIndex: data['taskIndex'] as int,
      targetUid: data['targetUid'] as String,
      graderUid: data['graderUid'] as String,
      score: data['score'] as int,
    );
    final index = _games.indexWhere((g) => g['id'] == gameId);
    if (index == -1) throw StateError('permission-denied: no such game');
    final game = Game.fromMap(_games[index]);
    final task = grade.taskIndex >= 0 && grade.taskIndex < game.tasks.length
        ? game.tasks[grade.taskIndex]
        : null;
    final allowed = game.isGroupJudged &&
        game.isInProgress &&
        task != null &&
        task.id == grade.taskId &&
        grade.id == gradeId &&
        grade.graderUid != grade.targetUid &&
        grade.score >= 1 &&
        grade.score <= 5 &&
        game.playerIds.contains(grade.graderUid) &&
        game.playerIds.contains(grade.targetUid) &&
        task.playerStatuses[grade.targetUid]?.state ==
            TaskPlayerState.submitted &&
        PeerGrading.canGrade(task, grade.graderUid);
    if (!allowed) throw StateError('permission-denied: grade refused');
    grades[gradeId] = grade;
    settlePeerTask(gameId, grade.taskId);
  }

  /// The mock's copy of the server settle pass (also the 24 h sweep: call it
  /// after moving [clock]).
  void settlePeerTask(String gameId, String taskId) {
    final index = _games.indexWhere((g) => g['id'] == gameId);
    if (index == -1) return;
    final game = Game.fromMap(_games[index]);
    if (!game.isInProgress) return;
    final ledger = _peerResults.putIfAbsent(gameId, () => {});
    final locked = {
      for (final key in ledger.keys)
        if (key.startsWith('${taskId}__')) key.substring(taskId.length + 2),
    };
    final outcome = PeerGrading.settle(
      game: game,
      taskId: taskId,
      grades: _peerGrades[gameId]?.values ?? const [],
      locked: locked,
      now: clock(),
    );
    if (outcome == null) return;
    for (final lock in outcome.locks) {
      ledger['${taskId}__${lock.uid}'] = lock.points;
    }
    final totals = <String, int>{};
    ledger.forEach((key, points) {
      final uid = key.substring(key.indexOf('__') + 2);
      totals[uid] = (totals[uid] ?? 0) + points;
    });
    final next = PeerGrading.apply(game, outcome, totals: totals, now: clock());
    _games[index] = {..._games[index], ...next.toMap(), 'id': gameId};
    _gamesController.add(List.from(_games));
    _gameControllers[gameId]?.add(_games[index]);
  }

  void dispose() {
    _gamesController.close();
    for (final controller in _gameControllers.values) {
      controller.close();
    }
    _gameControllers.clear();
  }
}