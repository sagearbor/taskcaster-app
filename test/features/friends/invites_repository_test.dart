import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/models/game.dart';
import 'package:taskcaster_app/core/models/game_settings.dart';
import 'package:taskcaster_app/core/models/player.dart';
import 'package:taskcaster_app/features/friends/data/repositories/firebase_invites_repository.dart';
import 'package:taskcaster_app/features/friends/domain/models/invite.dart';
import 'package:taskcaster_app/features/games/data/datasources/firestore_game_data_source.dart';
import 'package:taskcaster_app/features/games/data/repositories/game_repository_impl.dart';
import 'package:taskcaster_app/features/games/domain/repositories/game_repository.dart';

Game _lobbyGame() => Game(
      id: 'g1',
      gameName: 'Game Night',
      creatorId: 'inviter',
      judgeId: 'inviter',
      status: GameStatus.lobby,
      inviteCode: 'ABC234',
      createdAt: DateTime(2026, 1, 1),
      players: const [
        Player(userId: 'inviter', displayName: 'Inviter', totalScore: 0),
      ],
      tasks: const [],
      settings: GameSettings.quickPlay(),
    );

GameRepository _gameRepoFor(FakeFirebaseFirestore fs, MockFirebaseAuth auth) =>
    GameRepositoryImpl(FirestoreGameDataSource(firestore: fs, auth: auth));

void main() {
  late FakeFirebaseFirestore firestore;

  MockFirebaseAuth authFor(String uid, {String? email, String? name}) =>
      MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: uid, email: email, displayName: name),
      );

  setUp(() {
    firestore = FakeFirebaseFirestore();
  });

  test('send to friend → recipient watches it → accept joins the game',
      () async {
    final inviterAuth = authFor('inviter', email: 'inviter@x.com', name: 'Inviter');
    final recipientAuth =
        authFor('recipient', email: 'recipient@x.com', name: 'Reese');

    // Seed the game document (via the inviter's game repository).
    final inviterGameRepo = _gameRepoFor(firestore, inviterAuth);
    await inviterGameRepo.updateGame('g1', _lobbyGame());

    final inviterInvites = FirebaseInvitesRepository(
      gameRepository: inviterGameRepo,
      firestore: firestore,
      auth: inviterAuth,
    );
    final recipientGameRepo = _gameRepoFor(firestore, recipientAuth);
    final recipientInvites = FirebaseInvitesRepository(
      gameRepository: recipientGameRepo,
      firestore: firestore,
      auth: recipientAuth,
    );

    // Inviter sends the invite to the recipient's uid.
    await inviterInvites.sendToFriend('recipient', _lobbyGame());

    // Recipient sees it as pending.
    final inbox = await recipientInvites.watchMyInvites().first;
    expect(inbox, hasLength(1));
    final invite = inbox.single;
    expect(invite.gameName, 'Game Night');
    expect(invite.inviterName, 'Inviter');
    expect(invite.status, InviteStatus.pending);

    // Accepting joins the game and stamps the invite accepted.
    final joinedGameId = await recipientInvites.accept(invite);
    expect(joinedGameId, 'g1');

    final game = await recipientGameRepo.getGameStream('g1').first;
    expect(game!.players.map((p) => p.userId), contains('recipient'));

    // No longer pending in the recipient's inbox.
    expect(await recipientInvites.watchMyInvites().first, isEmpty);

    // The stored invite is accepted.
    final stored = await firestore.collection('invites').doc(invite.id).get();
    expect(stored.data()!['status'], InviteStatus.accepted.name);
  });

  test('email invite is claimed on sign-in and then appears in the inbox',
      () async {
    // An email invite with no recipientUid yet.
    final inviterAuth = authFor('inviter', email: 'inviter@x.com', name: 'Inviter');
    final inviterGameRepo = _gameRepoFor(firestore, inviterAuth);
    final inviterInvites = FirebaseInvitesRepository(
      gameRepository: inviterGameRepo,
      firestore: firestore,
      auth: inviterAuth,
    );
    await inviterInvites.sendToEmail('Target@Example.com', _lobbyGame());

    // The recipient (same email, mixed case) signs in.
    final recipientAuth =
        authFor('recipient', email: 'target@example.com', name: 'Reese');
    final recipientGameRepo = _gameRepoFor(firestore, recipientAuth);
    final recipientInvites = FirebaseInvitesRepository(
      gameRepository: recipientGameRepo,
      firestore: firestore,
      auth: recipientAuth,
    );

    // Before claiming, nothing is addressed to their uid.
    expect(await recipientInvites.watchMyInvites().first, isEmpty);

    await recipientInvites.claimEmailInvites();

    final inbox = await recipientInvites.watchMyInvites().first;
    expect(inbox, hasLength(1));
    expect(inbox.single.recipientUid, 'recipient');
  });

  test('decline removes the invite from the inbox', () async {
    final inviterAuth = authFor('inviter', email: 'inviter@x.com', name: 'Inviter');
    final recipientAuth = authFor('recipient', email: 'r@x.com', name: 'Reese');
    final inviterGameRepo = _gameRepoFor(firestore, inviterAuth);
    final inviterInvites = FirebaseInvitesRepository(
      gameRepository: inviterGameRepo,
      firestore: firestore,
      auth: inviterAuth,
    );
    final recipientInvites = FirebaseInvitesRepository(
      gameRepository: _gameRepoFor(firestore, recipientAuth),
      firestore: firestore,
      auth: recipientAuth,
    );

    await inviterInvites.sendToFriend('recipient', _lobbyGame());
    final invite = (await recipientInvites.watchMyInvites().first).single;

    await recipientInvites.decline(invite);

    expect(await recipientInvites.watchMyInvites().first, isEmpty);
  });
}
