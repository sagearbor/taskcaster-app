import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/models/game.dart';
import 'package:taskcaster_app/core/models/game_settings.dart';
import 'package:taskcaster_app/core/models/player.dart';
import 'package:taskcaster_app/features/friends/data/repositories/firebase_friends_repository.dart';

Game _game(List<Player> players) => Game(
      id: 'g1',
      gameName: 'Game Night',
      creatorId: players.first.userId,
      judgeId: players.first.userId,
      status: GameStatus.completed,
      inviteCode: 'ABC234',
      createdAt: DateTime(2026, 1, 1),
      players: players,
      tasks: const [],
      settings: GameSettings.quickPlay(),
    );

void main() {
  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth auth;
  late FirebaseFriendsRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'me', email: 'me@example.com', displayName: 'Me'),
    );
    repo = FirebaseFriendsRepository(firestore: firestore, auth: auth);
  });

  test('addFriendsFromGame upserts every co-player except me', () async {
    await repo.addFriendsFromGame(_game(const [
      Player(userId: 'me', displayName: 'Me', totalScore: 0),
      Player(userId: 'alice', displayName: 'Alice', totalScore: 3),
      Player(userId: 'bob', displayName: 'Bob', totalScore: 5),
    ]));

    final friends = await repo.watchFriends().first;
    expect(friends.map((f) => f.uid).toSet(), {'alice', 'bob'});
    expect(friends.every((f) => f.lastPlayedAt != null), isTrue);

    // Self is never friended.
    final myFriendDocs =
        await firestore.collection('users').doc('me').collection('friends').get();
    expect(myFriendDocs.docs.map((d) => d.id).contains('me'), isFalse);

    // Display name persisted.
    final alice = friends.firstWhere((f) => f.uid == 'alice');
    expect(alice.displayName, 'Alice');
  });

  test('addFriendsFromGame merges without clobbering an existing avatarEmoji',
      () async {
    // Seed an existing friend doc that already has an avatar.
    await firestore
        .collection('users')
        .doc('me')
        .collection('friends')
        .doc('alice')
        .set({'displayName': 'Alice', 'avatarEmoji': '🦊'});

    await repo.addFriendsFromGame(_game(const [
      Player(userId: 'me', displayName: 'Me', totalScore: 0),
      Player(userId: 'alice', displayName: 'Alice', totalScore: 3),
    ]));

    final friends = await repo.watchFriends().first;
    final alice = friends.firstWhere((f) => f.uid == 'alice');
    expect(alice.avatarEmoji, '🦊'); // preserved via merge
    expect(alice.lastPlayedAt, isNotNull); // stamped
  });

  test('removeFriend deletes the friend doc', () async {
    await repo.addFriendsFromGame(_game(const [
      Player(userId: 'me', displayName: 'Me', totalScore: 0),
      Player(userId: 'alice', displayName: 'Alice', totalScore: 3),
    ]));
    expect((await repo.watchFriends().first).map((f) => f.uid), contains('alice'));

    await repo.removeFriend('alice');

    expect(await repo.watchFriends().first, isEmpty);
  });

  test('addFriendsFromGame is a no-op with no co-players', () async {
    await repo.addFriendsFromGame(_game(const [
      Player(userId: 'me', displayName: 'Me', totalScore: 0),
    ]));
    expect(await repo.watchFriends().first, isEmpty);
  });
}
