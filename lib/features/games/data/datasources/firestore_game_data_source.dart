import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'game_remote_data_source.dart';

class FirestoreGameDataSource implements GameRemoteDataSource {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  FirestoreGameDataSource({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  static const String _gamesCollection = 'games';

  @override
  Stream<List<Map<String, dynamic>>> getGamesStream() {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      developer.log('No authenticated user, returning empty stream');
      return Stream.value([]);
    }

    // ONE query scoped to the user: every game they create or join carries
    // them in the flat playerIds list (the creator is seeded into it). This
    // used to listen to the whole collection and filter client-side, which
    // billed a read for every game in the database on every snapshot.
    // Needs the playerIds (array-contains) + createdAt (desc) composite index
    // in firestore.indexes.json.
    return _firestore
        .collection(_gamesCollection)
        .where('playerIds', arrayContains: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              return data;
            }).toList());
  }

  @override
  Stream<List<Map<String, dynamic>>> getPublicGamesStream() {
    // Single-field equality filter + client-side sort avoids needing a
    // composite Firestore index.
    return _firestore
        .collection(_gamesCollection)
        .where('isPublic', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
      final games = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList()
        ..sort((a, b) => (b['createdAt'] as String? ?? '')
            .compareTo(a['createdAt'] as String? ?? ''));
      return games;
    });
  }

  @override
  Stream<List<Map<String, dynamic>>> getInvitedGamesStream(String email) {
    final target = email.toLowerCase();
    // Single array-contains filter only — Firestore auto-indexes single-field
    // array-contains, so NO composite index is required. Status filtering and
    // newest-first sorting happen in the repository (client-side), which also
    // avoids the composite index an arrayContains + orderBy query would need.
    return _firestore
        .collection(_gamesCollection)
        .where('invitedEmails', arrayContains: target)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    });
  }

  @override
  Future<String> createGame(Map<String, dynamic> gameData) async {
    try {
      developer.log('=== CREATE GAME DEBUG ===');
      developer.log('Input data: ${gameData.toString()}');

      // Remove id if present (Firestore will generate it)
      final data = Map<String, dynamic>.from(gameData);
      final id = data.remove('id');

      developer.log('Data to write (without id): ${data.toString()}');
      developer.log('User ID: ${_auth.currentUser?.uid}');
      developer.log('User isAnonymous: ${_auth.currentUser?.isAnonymous}');

      // Use provided ID or let Firestore generate one
      if (id != null && id.isNotEmpty) {
        developer.log('Using provided ID: $id');
        await _firestore.collection(_gamesCollection).doc(id).set(data);
        developer.log('Successfully created game with ID: $id');
        return id;
      } else {
        developer.log('Letting Firestore generate ID');
        final docRef = await _firestore.collection(_gamesCollection).add(data);
        developer.log('Successfully created game with auto-generated ID: ${docRef.id}');
        return docRef.id;
      }
    } catch (e, stackTrace) {
      developer.log('ERROR creating game: $e');
      developer.log('Stack trace: $stackTrace');
      rethrow;
    }
  }

  @override
  Future<void> updateGame(String gameId, Map<String, dynamic> updates) async {
    // Use set with merge to handle both create and update cases
    // This is needed for Quick Play which creates then immediately updates
    await _firestore.collection(_gamesCollection).doc(gameId).set(
      updates,
      SetOptions(merge: true),
    );
  }

  @override
  Future<void> deleteGame(String gameId) async {
    await _firestore.collection(_gamesCollection).doc(gameId).delete();
  }

  @override
  Stream<Map<String, dynamic>?> getGameStream(String gameId) {
    return _firestore
        .collection(_gamesCollection)
        .doc(gameId)
        .snapshots()
        .map((snapshot) {
      if (!snapshot.exists) {
        return null;
      }
      final data = snapshot.data()!;
      data['id'] = snapshot.id;
      return data;
    });
  }

  @override
  Future<String?> findGameIdByInviteCode(String inviteCode) async {
    final query = await _firestore
        .collection(_gamesCollection)
        .where('inviteCode', isEqualTo: inviteCode)
        .limit(1)
        .get();
    return query.docs.isEmpty ? null : query.docs.first.id;
  }

  @override
  Future<void> transactGame(String gameId, GameMutation mutate) {
    final ref = _firestore.collection(_gamesCollection).doc(gameId);
    return _firestore.runTransaction<void>((tx) async {
      final snapshot = await tx.get(ref);
      if (!snapshot.exists) {
        throw Exception('Game not found');
      }
      final data = Map<String, dynamic>.from(snapshot.data()!);
      data['id'] = snapshot.id;
      final updates = mutate(data);
      if (updates != null && updates.isNotEmpty) {
        tx.update(ref, updates);
      }
    });
  }

  Future<void> startGame(String gameId) async {
    try {
      developer.log('Starting game $gameId');

      final gameDoc = await _firestore.collection(_gamesCollection).doc(gameId).get();

      if (!gameDoc.exists) {
        throw Exception('Game not found');
      }

      final gameData = gameDoc.data()!;

      // Validation
      final players = List.from(gameData['players'] ?? []);
      final tasks = List.from(gameData['tasks'] ?? []);

      if (players.length < 2) {
        throw Exception('Need at least 2 players to start');
      }
      if (tasks.isEmpty) {
        throw Exception('Need at least 1 task to start');
      }

      // Initialize first task playerStatuses
      final firstTask = Map<String, dynamic>.from(tasks[0]);
      final playerStatuses = <String, Map<String, dynamic>>{};

      for (final player in players) {
        playerStatuses[player['userId']] = {
          'state': 'not_started',
          'videoUrl': null,
          'textAnswer': null,
          'score': null,
          'submittedAt': null,
        };
      }

      firstTask['playerStatuses'] = playerStatuses;
      firstTask['status'] = 'waiting_for_submissions';

      final settings = Map<String, dynamic>.from(gameData['settings'] ?? {});
      final deadlineHours = settings['taskDeadlineHours'] ?? 24;

      firstTask['deadline'] = DateTime.now()
          .add(Duration(hours: deadlineHours))
          .toIso8601String();

      tasks[0] = firstTask;

      // Update game
      await gameDoc.reference.update({
        'status': 'inProgress',
        'currentTaskIndex': 0,
        'tasks': tasks,
      });

      developer.log('Game $gameId started successfully');
    } catch (e, stackTrace) {
      developer.log(
        'Error starting game $gameId',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<void> submitTask(
    String gameId,
    int taskIndex,
    String playerId,
    String videoUrl,
  ) async {
    try {
      developer.log('Player $playerId submitting task $taskIndex for game $gameId');

      final gameDoc = await _firestore.collection(_gamesCollection).doc(gameId).get();

      if (!gameDoc.exists) {
        throw Exception('Game not found');
      }

      final gameData = gameDoc.data()!;
      final tasks = List.from(gameData['tasks']);

      if (taskIndex >= tasks.length) {
        throw Exception('Invalid task index');
      }

      final task = Map<String, dynamic>.from(tasks[taskIndex]);

      // Update playerStatus
      final playerStatuses = Map<String, dynamic>.from(task['playerStatuses'] ?? {});
      playerStatuses[playerId] = {
        'state': 'submitted',
        'videoUrl': videoUrl,
        'textAnswer': null,
        'score': null,
        'submittedAt': DateTime.now().toIso8601String(),
      };

      // Add or update submission
      final submissions = List<Map<String, dynamic>>.from(task['submissions'] ?? []);
      final existingIndex = submissions.indexWhere((s) => s['userId'] == playerId);

      final submission = {
        'id': existingIndex >= 0
            ? submissions[existingIndex]['id']
            : 'sub_${DateTime.now().millisecondsSinceEpoch}',
        'userId': playerId,
        'videoUrl': videoUrl,
        'textAnswer': null,
        'score': null,
        'isJudged': false,
        'submittedAt': DateTime.now().toIso8601String(),
      };

      if (existingIndex >= 0) {
        submissions[existingIndex] = submission;
      } else {
        submissions.add(submission);
      }

      // Check if all players submitted
      final allSubmitted = playerStatuses.values.every(
        (status) => status['state'] == 'submitted' || status['state'] == 'skipped'
      );

      task['playerStatuses'] = playerStatuses;
      task['submissions'] = submissions;
      if (allSubmitted) {
        task['status'] = 'ready_to_judge';
      }

      tasks[taskIndex] = task;

      await gameDoc.reference.update({'tasks': tasks});

      developer.log('Task $taskIndex submitted successfully for player $playerId');
    } catch (e, stackTrace) {
      developer.log(
        'Error submitting task $taskIndex for player $playerId',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<void> scoreSubmission(
    String gameId,
    int taskIndex,
    String playerId,
    int score,
  ) async {
    try {
      developer.log('Scoring submission for player $playerId: $score points');

      final gameDoc = await _firestore.collection(_gamesCollection).doc(gameId).get();

      if (!gameDoc.exists) {
        throw Exception('Game not found');
      }

      final gameData = gameDoc.data()!;

      // Update task
      final tasks = List.from(gameData['tasks']);
      final task = Map<String, dynamic>.from(tasks[taskIndex]);

      final playerStatuses = Map<String, dynamic>.from(task['playerStatuses'] ?? {});
      if (playerStatuses[playerId] != null) {
        playerStatuses[playerId]['score'] = score;
        playerStatuses[playerId]['state'] = 'judged';
      }

      final submissions = List<Map<String, dynamic>>.from(task['submissions'] ?? []);
      final subIndex = submissions.indexWhere((s) => s['userId'] == playerId);
      if (subIndex >= 0) {
        submissions[subIndex]['score'] = score;
        submissions[subIndex]['isJudged'] = true;
      }

      // Check if all judged
      final allJudged = playerStatuses.values.every(
        (status) => status['state'] == 'judged' || status['state'] == 'skipped'
      );

      task['playerStatuses'] = playerStatuses;
      task['submissions'] = submissions;
      if (allJudged) {
        task['status'] = 'completed';
      }

      tasks[taskIndex] = task;

      // Update player total score
      final players = List<Map<String, dynamic>>.from(gameData['players']);
      final playerIndex = players.indexWhere((p) => p['userId'] == playerId);
      if (playerIndex >= 0) {
        players[playerIndex]['totalScore'] =
            (players[playerIndex]['totalScore'] ?? 0) + score;
      }

      await gameDoc.reference.update({
        'tasks': tasks,
        'players': players,
      });

      developer.log('Submission scored successfully for player $playerId');
    } catch (e, stackTrace) {
      developer.log(
        'Error scoring submission for player $playerId',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<void> advanceToNextTask(String gameId) async {
    try {
      developer.log('Advancing game $gameId to next task');

      final gameDoc = await _firestore.collection(_gamesCollection).doc(gameId).get();

      if (!gameDoc.exists) {
        throw Exception('Game not found');
      }

      final gameData = gameDoc.data()!;

      final currentIndex = gameData['currentTaskIndex'] as int;
      final tasks = List.from(gameData['tasks']);

      if (currentIndex >= tasks.length - 1) {
        throw Exception('No more tasks');
      }

      final nextIndex = currentIndex + 1;

      // Initialize next task
      final nextTask = Map<String, dynamic>.from(tasks[nextIndex]);
      final playerStatuses = <String, Map<String, dynamic>>{};

      final players = List.from(gameData['players']);
      for (final player in players) {
        playerStatuses[player['userId']] = {
          'state': 'not_started',
          'videoUrl': null,
          'textAnswer': null,
          'score': null,
          'submittedAt': null,
        };
      }

      nextTask['playerStatuses'] = playerStatuses;
      nextTask['status'] = 'waiting_for_submissions';

      final settings = Map<String, dynamic>.from(gameData['settings'] ?? {});
      final deadlineHours = settings['taskDeadlineHours'] ?? 24;

      nextTask['deadline'] = DateTime.now()
          .add(Duration(hours: deadlineHours))
          .toIso8601String();

      tasks[nextIndex] = nextTask;

      await gameDoc.reference.update({
        'currentTaskIndex': nextIndex,
        'tasks': tasks,
      });

      developer.log('Advanced to task $nextIndex successfully');
    } catch (e, stackTrace) {
      developer.log(
        'Error advancing to next task for game $gameId',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<void> skipTask(
    String gameId,
    int taskIndex,
    String playerId,
  ) async {
    try {
      developer.log('Player $playerId skipping task $taskIndex');

      final gameDoc = await _firestore.collection(_gamesCollection).doc(gameId).get();

      if (!gameDoc.exists) {
        throw Exception('Game not found');
      }

      final gameData = gameDoc.data()!;
      final tasks = List.from(gameData['tasks']);

      if (taskIndex >= tasks.length) {
        throw Exception('Invalid task index');
      }

      final task = Map<String, dynamic>.from(tasks[taskIndex]);

      // Update playerStatus
      final playerStatuses = Map<String, dynamic>.from(task['playerStatuses'] ?? {});
      playerStatuses[playerId] = {
        'state': 'skipped',
        'videoUrl': null,
        'textAnswer': null,
        'score': 0,
        'submittedAt': DateTime.now().toIso8601String(),
      };

      // Check if all players submitted or skipped
      final allDone = playerStatuses.values.every(
        (status) => status['state'] == 'submitted' || status['state'] == 'skipped'
      );

      task['playerStatuses'] = playerStatuses;
      if (allDone) {
        task['status'] = 'ready_to_judge';
      }

      tasks[taskIndex] = task;

      await gameDoc.reference.update({'tasks': tasks});

      developer.log('Task $taskIndex skipped successfully by player $playerId');
    } catch (e, stackTrace) {
      developer.log(
        'Error skipping task $taskIndex for player $playerId',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }
}