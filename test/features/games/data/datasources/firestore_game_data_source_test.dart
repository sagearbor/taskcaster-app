import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/features/games/data/datasources/firestore_game_data_source.dart';

void main() {
  late FakeFirebaseFirestore fakeFirestore;
  late MockFirebaseAuth fakeAuth;
  late FirestoreGameDataSource dataSource;

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
    fakeAuth = MockFirebaseAuth(signedIn: true);
    dataSource = FirestoreGameDataSource(
      firestore: fakeFirestore,
      auth: fakeAuth,
    );
  });

  group('FirestoreGameDataSource', () {
    group('createGame', () {
      test('should create game in Firestore and return document ID', () async {
        // Arrange
        final gameData = {
          'gameName': 'Test Game',
          'creatorId': 'user_123',
          'judgeId': 'user_456',
          'status': 'lobby',
          'inviteCode': 'TEST123',
          'createdAt': DateTime.now().toIso8601String(),
          'players': [
            {'userId': 'user_123', 'displayName': 'Player 1', 'totalScore': 0},
          ],
          'tasks': [],
          'settings': {'taskDeadlineHours': 24},
        };

        // Act
        final gameId = await dataSource.createGame(gameData);

        // Assert
        expect(gameId, isNotEmpty);
        final doc = await fakeFirestore.collection('games').doc(gameId).get();
        expect(doc.exists, isTrue);
        expect(doc.data()?['gameName'], 'Test Game');
      });
    });

    group('getGamesStream', () {
      test('should return games stream filtered by current user', () async {
        // Arrange
        final currentUserId = fakeAuth.currentUser!.uid;
        await fakeFirestore.collection('games').add({
          'gameName': 'User Game',
          'creatorId': currentUserId,
          'players': [
            {'userId': currentUserId, 'displayName': 'Current User', 'totalScore': 0},
          ],
          'createdAt': DateTime.now().toIso8601String(),
        });

        await fakeFirestore.collection('games').add({
          'gameName': 'Other Game',
          'creatorId': 'other_user',
          'players': [
            {'userId': 'other_user', 'displayName': 'Other User', 'totalScore': 0},
          ],
          'createdAt': DateTime.now().toIso8601String(),
        });

        // Act
        final stream = dataSource.getGamesStream();
        final games = await stream.first;

        // Assert
        expect(games.length, 1);
        expect(games[0]['gameName'], 'User Game');
      });

      test('should return empty stream when user not authenticated', () async {
        // Arrange
        final unauthDataSource = FirestoreGameDataSource(
          firestore: fakeFirestore,
          auth: MockFirebaseAuth(signedIn: false),
        );

        // Act
        final stream = unauthDataSource.getGamesStream();
        final games = await stream.first;

        // Assert
        expect(games, isEmpty);
      });
    });

    group('getInvitedGamesStream', () {
      test('should return only games whose invitedEmails contains the email',
          () async {
        await fakeFirestore.collection('games').add({
          'gameName': 'Invited Game',
          'status': 'lobby',
          'invitedEmails': ['bob@example.com'],
          'createdAt': DateTime.now().toIso8601String(),
        });
        await fakeFirestore.collection('games').add({
          'gameName': 'Other Game',
          'status': 'lobby',
          'invitedEmails': ['carol@example.com'],
          'createdAt': DateTime.now().toIso8601String(),
        });

        final games =
            await dataSource.getInvitedGamesStream('bob@example.com').first;

        expect(games.length, 1);
        expect(games.first['gameName'], 'Invited Game');
        expect(games.first['id'], isNotNull);
      });

      test('should return empty when nobody matches', () async {
        await fakeFirestore.collection('games').add({
          'gameName': 'Invited Game',
          'status': 'lobby',
          'invitedEmails': ['bob@example.com'],
          'createdAt': DateTime.now().toIso8601String(),
        });

        final games =
            await dataSource.getInvitedGamesStream('nobody@example.com').first;

        expect(games, isEmpty);
      });
    });

    group('getGameStream', () {
      test('should return game stream for specific game', () async {
        // Arrange
        final docRef = await fakeFirestore.collection('games').add({
          'gameName': 'Test Game',
          'status': 'lobby',
        });

        // Act
        final stream = dataSource.getGameStream(docRef.id);
        final game = await stream.first;

        // Assert
        expect(game, isNotNull);
        expect(game?['gameName'], 'Test Game');
        expect(game?['id'], docRef.id);
      });

      test('should return null for non-existent game', () async {
        // Act
        final stream = dataSource.getGameStream('non_existent_id');
        final game = await stream.first;

        // Assert
        expect(game, isNull);
      });
    });

    group('updateGame', () {
      test('should update game fields', () async {
        // Arrange
        final docRef = await fakeFirestore.collection('games').add({
          'gameName': 'Original Name',
          'status': 'lobby',
        });

        // Act
        await dataSource.updateGame(docRef.id, {'status': 'inProgress'});

        // Assert
        final doc = await fakeFirestore.collection('games').doc(docRef.id).get();
        expect(doc.data()?['status'], 'inProgress');
        expect(doc.data()?['gameName'], 'Original Name');
      });
    });

    group('deleteGame', () {
      test('should delete game from Firestore', () async {
        // Arrange
        final docRef = await fakeFirestore.collection('games').add({
          'gameName': 'Test Game',
        });

        // Act
        await dataSource.deleteGame(docRef.id);

        // Assert
        final doc = await fakeFirestore.collection('games').doc(docRef.id).get();
        expect(doc.exists, isFalse);
      });
    });

    group('joinGame', () {
      test('should add player to game by invite code', () async {
        // Arrange
        final userId = 'new_user_123';
        await fakeFirestore.collection('games').add({
          'gameName': 'Test Game',
          'inviteCode': 'JOIN123',
          'players': [
            {'userId': 'existing_user', 'displayName': 'Existing', 'totalScore': 0},
          ],
        });

        // Act
        final gameId = await dataSource.joinGame('JOIN123', userId);

        // Assert
        expect(gameId, isNotEmpty);
        final doc = await fakeFirestore.collection('games').doc(gameId).get();
        final players = List.from(doc.data()?['players'] ?? []);
        expect(players.length, 2);
        expect(players.any((p) => p['userId'] == userId), isTrue);
      });

      test('should not duplicate player if already in game', () async {
        // Arrange
        final userId = 'existing_user';
        await fakeFirestore.collection('games').add({
          'gameName': 'Test Game',
          'inviteCode': 'JOIN456',
          'players': [
            {'userId': userId, 'displayName': 'Existing', 'totalScore': 0},
          ],
        });

        // Act
        final gameId = await dataSource.joinGame('JOIN456', userId);

        // Assert
        final doc = await fakeFirestore.collection('games').doc(gameId).get();
        final players = List.from(doc.data()?['players'] ?? []);
        expect(players.length, 1);
      });

      test('should throw exception for invalid invite code', () async {
        // Act & Assert
        expect(
          () => dataSource.joinGame('INVALID', 'user_123'),
          throwsException,
        );
      });
    });

    group('startGame', () {
      test('should initialize first task with playerStatuses', () async {
        // Arrange
        final docRef = await fakeFirestore.collection('games').add({
          'gameName': 'Test Game',
          'status': 'lobby',
          'players': [
            {'userId': 'user_1', 'displayName': 'Player 1', 'totalScore': 0},
            {'userId': 'user_2', 'displayName': 'Player 2', 'totalScore': 0},
          ],
          'tasks': [
            {
              'id': 'task_1',
              'title': 'Test Task',
              'description': 'Do something',
              'taskType': 'video',
            },
          ],
          'settings': {'taskDeadlineHours': 24},
        });

        // Act
        await dataSource.startGame(docRef.id);

        // Assert
        final doc = await fakeFirestore.collection('games').doc(docRef.id).get();
        final data = doc.data()!;
        expect(data['status'], 'inProgress');
        expect(data['currentTaskIndex'], 0);

        final tasks = List.from(data['tasks']);
        final firstTask = tasks[0];
        expect(firstTask['status'], 'waiting_for_submissions');
        expect(firstTask['playerStatuses'], isNotNull);
        expect(firstTask['playerStatuses']['user_1'], isNotNull);
        expect(firstTask['playerStatuses']['user_1']['state'], 'not_started');
        expect(firstTask['deadline'], isNotNull);
      });

      test('should throw exception if less than 2 players', () async {
        // Arrange
        final docRef = await fakeFirestore.collection('games').add({
          'players': [
            {'userId': 'user_1', 'displayName': 'Player 1', 'totalScore': 0},
          ],
          'tasks': [{'id': 'task_1'}],
        });

        // Act & Assert
        expect(
          () => dataSource.startGame(docRef.id),
          throwsA(isA<Exception>()),
        );
      });

      test('should throw exception if no tasks', () async {
        // Arrange
        final docRef = await fakeFirestore.collection('games').add({
          'players': [
            {'userId': 'user_1', 'displayName': 'Player 1', 'totalScore': 0},
            {'userId': 'user_2', 'displayName': 'Player 2', 'totalScore': 0},
          ],
          'tasks': [],
        });

        // Act & Assert
        expect(
          () => dataSource.startGame(docRef.id),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('submitTask', () {
      test('should update player submission and task status', () async {
        // Arrange
        final docRef = await fakeFirestore.collection('games').add({
          'players': [
            {'userId': 'user_1', 'displayName': 'Player 1', 'totalScore': 0},
          ],
          'tasks': [
            {
              'id': 'task_1',
              'title': 'Test Task',
              'playerStatuses': {
                'user_1': {
                  'state': 'not_started',
                  'videoUrl': null,
                  'score': null,
                },
              },
              'submissions': [],
            },
          ],
        });

        // Act
        await dataSource.submitTask(
          docRef.id,
          0,
          'user_1',
          'https://youtube.com/watch?v=test',
        );

        // Assert
        final doc = await fakeFirestore.collection('games').doc(docRef.id).get();
        final tasks = List.from(doc.data()?['tasks'] ?? []);
        final task = tasks[0];

        expect(task['playerStatuses']['user_1']['state'], 'submitted');
        expect(task['playerStatuses']['user_1']['videoUrl'], 'https://youtube.com/watch?v=test');
        expect(task['submissions'].length, 1);
        expect(task['submissions'][0]['userId'], 'user_1');
      });

      test('should set task status to ready_to_judge when all players submitted', () async {
        // Arrange
        final docRef = await fakeFirestore.collection('games').add({
          'players': [
            {'userId': 'user_1', 'displayName': 'Player 1', 'totalScore': 0},
            {'userId': 'user_2', 'displayName': 'Player 2', 'totalScore': 0},
          ],
          'tasks': [
            {
              'id': 'task_1',
              'playerStatuses': {
                'user_1': {'state': 'not_started'},
                'user_2': {'state': 'submitted'},
              },
              'submissions': [],
            },
          ],
        });

        // Act
        await dataSource.submitTask(docRef.id, 0, 'user_1', 'https://test.com');

        // Assert
        final doc = await fakeFirestore.collection('games').doc(docRef.id).get();
        final tasks = List.from(doc.data()?['tasks'] ?? []);
        expect(tasks[0]['status'], 'ready_to_judge');
      });
    });

    group('scoreSubmission', () {
      test('should update player score and task status', () async {
        // Arrange
        final docRef = await fakeFirestore.collection('games').add({
          'players': [
            {'userId': 'user_1', 'displayName': 'Player 1', 'totalScore': 0},
          ],
          'tasks': [
            {
              'id': 'task_1',
              'playerStatuses': {
                'user_1': {
                  'state': 'submitted',
                  'videoUrl': 'https://test.com',
                },
              },
              'submissions': [
                {
                  'id': 'sub_1',
                  'userId': 'user_1',
                  'videoUrl': 'https://test.com',
                  'isJudged': false,
                },
              ],
            },
          ],
        });

        // Act
        await dataSource.scoreSubmission(docRef.id, 0, 'user_1', 5);

        // Assert
        final doc = await fakeFirestore.collection('games').doc(docRef.id).get();
        final data = doc.data()!;

        final tasks = List.from(data['tasks']);
        expect(tasks[0]['playerStatuses']['user_1']['score'], 5);
        expect(tasks[0]['playerStatuses']['user_1']['state'], 'judged');
        expect(tasks[0]['submissions'][0]['score'], 5);
        expect(tasks[0]['submissions'][0]['isJudged'], true);

        final players = List.from(data['players']);
        expect(players[0]['totalScore'], 5);
      });

      test('should set task status to completed when all judged', () async {
        // Arrange
        final docRef = await fakeFirestore.collection('games').add({
          'players': [
            {'userId': 'user_1', 'displayName': 'Player 1', 'totalScore': 0},
            {'userId': 'user_2', 'displayName': 'Player 2', 'totalScore': 0},
          ],
          'tasks': [
            {
              'id': 'task_1',
              'playerStatuses': {
                'user_1': {'state': 'submitted'},
                'user_2': {'state': 'judged', 'score': 3},
              },
              'submissions': [],
            },
          ],
        });

        // Act
        await dataSource.scoreSubmission(docRef.id, 0, 'user_1', 5);

        // Assert
        final doc = await fakeFirestore.collection('games').doc(docRef.id).get();
        final tasks = List.from(doc.data()?['tasks'] ?? []);
        expect(tasks[0]['status'], 'completed');
      });
    });

    group('advanceToNextTask', () {
      test('should increment currentTaskIndex and initialize next task', () async {
        // Arrange
        final docRef = await fakeFirestore.collection('games').add({
          'currentTaskIndex': 0,
          'players': [
            {'userId': 'user_1', 'displayName': 'Player 1', 'totalScore': 5},
          ],
          'tasks': [
            {'id': 'task_1', 'status': 'completed'},
            {'id': 'task_2', 'title': 'Next Task'},
          ],
          'settings': {'taskDeadlineHours': 24},
        });

        // Act
        await dataSource.advanceToNextTask(docRef.id);

        // Assert
        final doc = await fakeFirestore.collection('games').doc(docRef.id).get();
        final data = doc.data()!;

        expect(data['currentTaskIndex'], 1);

        final tasks = List.from(data['tasks']);
        final nextTask = tasks[1];
        expect(nextTask['status'], 'waiting_for_submissions');
        expect(nextTask['playerStatuses'], isNotNull);
        expect(nextTask['playerStatuses']['user_1']['state'], 'not_started');
        expect(nextTask['deadline'], isNotNull);
      });

      test('should throw exception when no more tasks', () async {
        // Arrange
        final docRef = await fakeFirestore.collection('games').add({
          'currentTaskIndex': 0,
          'players': [
            {'userId': 'user_1', 'displayName': 'Player 1', 'totalScore': 5},
          ],
          'tasks': [
            {'id': 'task_1', 'status': 'completed'},
          ],
        });

        // Act & Assert
        expect(
          () => dataSource.advanceToNextTask(docRef.id),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('skipTask', () {
      test('should mark player as skipped', () async {
        // Arrange
        final docRef = await fakeFirestore.collection('games').add({
          'tasks': [
            {
              'id': 'task_1',
              'playerStatuses': {
                'user_1': {'state': 'not_started'},
              },
            },
          ],
        });

        // Act
        await dataSource.skipTask(docRef.id, 0, 'user_1');

        // Assert
        final doc = await fakeFirestore.collection('games').doc(docRef.id).get();
        final tasks = List.from(doc.data()?['tasks'] ?? []);
        expect(tasks[0]['playerStatuses']['user_1']['state'], 'skipped');
        expect(tasks[0]['playerStatuses']['user_1']['score'], 0);
      });

      test('should set task to ready_to_judge when all players done', () async {
        // Arrange
        final docRef = await fakeFirestore.collection('games').add({
          'tasks': [
            {
              'id': 'task_1',
              'playerStatuses': {
                'user_1': {'state': 'not_started'},
                'user_2': {'state': 'submitted'},
              },
            },
          ],
        });

        // Act
        await dataSource.skipTask(docRef.id, 0, 'user_1');

        // Assert
        final doc = await fakeFirestore.collection('games').doc(docRef.id).get();
        final tasks = List.from(doc.data()?['tasks'] ?? []);
        expect(tasks[0]['status'], 'ready_to_judge');
      });
    });
  });
}