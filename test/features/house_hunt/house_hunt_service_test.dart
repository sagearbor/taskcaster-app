import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:taskcaster_app/core/models/game.dart';
import 'package:taskcaster_app/core/models/game_settings.dart';
import 'package:taskcaster_app/core/models/task.dart';
import 'package:taskcaster_app/core/models/user.dart';
import 'package:taskcaster_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:taskcaster_app/features/friends/domain/models/friend.dart';
import 'package:taskcaster_app/features/friends/domain/repositories/invites_repository.dart';
import 'package:taskcaster_app/features/games/data/datasources/mock_game_data_source.dart';
import 'package:taskcaster_app/features/games/data/repositories/game_repository_impl.dart';
import 'package:taskcaster_app/features/games/domain/repositories/game_repository.dart';
import 'package:taskcaster_app/features/house_hunt/domain/house_hunt_service.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockInvitesRepository extends Mock implements InvitesRepository {}

class FakeGame extends Fake implements Game {}

User _hider() => User(
      id: 'hider',
      displayName: 'Alice',
      email: 'alice@example.com',
      createdAt: DateTime(2026, 1, 1),
    );

List<String> _fivePrompts() =>
    List.generate(HouseHuntService.huntSize, (i) => 'Find treasure $i');

void main() {
  setUpAll(() => registerFallbackValue(FakeGame()));

  late MockAuthRepository auth;
  late GameRepository gameRepo;
  late MockInvitesRepository invites;
  late HouseHuntService service;

  setUp(() {
    auth = MockAuthRepository();
    when(() => auth.getCurrentUser()).thenAnswer((_) async => _hider());

    gameRepo = GameRepositoryImpl(MockGameDataSource());

    invites = MockInvitesRepository();
    when(() => invites.sendToFriend(any(), any())).thenAnswer((_) async {});
    when(() => invites.sendToEmail(any(), any())).thenAnswer((_) async {});

    service = HouseHuntService(
      authRepository: auth,
      gameRepository: gameRepo,
      invitesRepository: invites,
    );
  });

  group('static framing helpers', () {
    test('gameNameFor uses the hider name', () {
      expect(HouseHuntService.gameNameFor('Alice'), "Alice's House Hunt");
    });

    test('gameNameFor falls back for a blank name', () {
      expect(HouseHuntService.gameNameFor('   '), "A Sneaky Hider's House Hunt");
    });

    test('isHouseHuntGame detects via gameKind', () {
      final hunt = Game(
        id: 'g',
        gameName: 'Whatever Name',
        creatorId: 'h',
        judgeId: 'h',
        status: GameStatus.lobby,
        inviteCode: 'ABC234',
        createdAt: DateTime(2026, 1, 1),
        players: const [],
        tasks: const [],
        settings: GameSettings.quickPlay(),
        gameKind: HouseHuntService.kindHouseHunt,
      );
      expect(HouseHuntService.isHouseHuntGame(hunt), isTrue);
    });

    test('isHouseHuntGame falls back to the legacy name-suffix convention '
        'for pre-existing docs with no gameKind', () {
      final legacyHunt = Game(
        id: 'g',
        gameName: "Alice's House Hunt",
        creatorId: 'h',
        judgeId: 'h',
        status: GameStatus.lobby,
        inviteCode: 'ABC234',
        createdAt: DateTime(2026, 1, 1),
        players: const [],
        tasks: const [],
        settings: GameSettings.quickPlay(),
        // No gameKind — simulates a game document written before the field
        // existed.
      );
      expect(legacyHunt.gameKind, isNull);
      expect(HouseHuntService.isHouseHuntGame(legacyHunt), isTrue);
    });

    test('isHouseHuntGame is false for an ordinary game (neither kind nor '
        'name match)', () {
      final ordinary = Game(
        id: 'g',
        gameName: 'Epic Quest',
        creatorId: 'h',
        judgeId: 'h',
        status: GameStatus.lobby,
        inviteCode: 'ABC234',
        createdAt: DateTime(2026, 1, 1),
        players: const [],
        tasks: const [],
        settings: GameSettings.quickPlay(),
      );
      expect(HouseHuntService.isHouseHuntGame(ordinary), isFalse);
    });
  });

  group('createAndSendHunt payload', () {
    test('creates a lobby game: hider is judge, 5 framed tasks, framed name',
        () async {
      final result = await service.createAndSendHunt(
        prompts: _fivePrompts(),
        friend: const Friend(uid: 'seeker', displayName: 'Bob'),
      );

      final game = await gameRepo.getGameStream(result.gameId).first;
      expect(game, isNotNull);
      game!;

      // Hider owns and judges.
      expect(game.creatorId, 'hider');
      expect(game.judgeId, 'hider');
      expect(game.status, GameStatus.lobby);

      // Framed name.
      expect(game.gameName, "Alice's House Hunt");

      // Carries the real type discriminator (not just the name convention).
      expect(game.gameKind, HouseHuntService.kindHouseHunt);
      expect(HouseHuntService.isHouseHuntGame(game), isTrue);

      // Single player (the hider), with the real display name (not "Creator").
      expect(game.players.length, 1);
      expect(game.players.single.displayName, 'Alice');

      // Exactly five ordinary video tasks carrying the hunt framing.
      expect(game.tasks.length, HouseHuntService.huntSize);
      for (final task in game.tasks) {
        expect(task.taskType, TaskType.video);
        expect(task.category, HouseHuntService.category);
        expect(task.description, startsWith('Hunt!'));
        expect(task.description, contains('proof'));
        expect(task.submissions, isEmpty);
      }

      // Task titles carry the chosen prompts verbatim.
      expect(
        game.tasks.map((t) => t.title).toList(),
        _fivePrompts(),
      );
    });

    test('rejects the wrong number of prompts', () {
      expect(
        () => service.createAndSendHunt(prompts: const ['only one']),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects when blank prompts leave fewer than 5', () {
      final prompts = ['a', 'b', 'c', 'd', '   '];
      expect(
        () => service.createAndSendHunt(prompts: prompts),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws (and creates nothing) when no hider is signed in', () async {
      when(() => auth.getCurrentUser()).thenAnswer((_) async => null);
      await expectLater(
        service.createAndSendHunt(prompts: _fivePrompts()),
        throwsA(isA<StateError>()),
      );
      // No House Hunt game reached the store (the mock source seeds unrelated
      // starter games, so filter to ours).
      final games = await gameRepo.getGamesStream().first;
      expect(games.where(HouseHuntService.isHouseHuntGame), isEmpty);
    });
  });

  group('createAndSendHunt invite issuance', () {
    test('friend target fires a one-tap invite carrying the game code',
        () async {
      final result = await service.createAndSendHunt(
        prompts: _fivePrompts(),
        friend: const Friend(uid: 'seeker', displayName: 'Bob'),
      );

      final captured =
          verify(() => invites.sendToFriend('seeker', captureAny())).captured;
      final sentGame = captured.single as Game;
      // The invite carries the SAME code that is on the created game.
      expect(sentGame.inviteCode, result.inviteCode);
      expect(sentGame.tasks.length, HouseHuntService.huntSize);
      verifyNever(() => invites.sendToEmail(any(), any()));
    });

    test('email target routes to sendToEmail', () async {
      await service.createAndSendHunt(
        prompts: _fivePrompts(),
        email: 'bob@example.com',
      );
      verify(() => invites.sendToEmail('bob@example.com', any())).called(1);
      verifyNever(() => invites.sendToFriend(any(), any()));
    });

    test('no friend and no email issues no invite (share-link path)', () async {
      final result = await service.createAndSendHunt(prompts: _fivePrompts());
      verifyNever(() => invites.sendToFriend(any(), any()));
      verifyNever(() => invites.sendToEmail(any(), any()));
      // The game still exists for the hider to share the code from the lobby.
      final game = await gameRepo.getGameStream(result.gameId).first;
      expect(game, isNotNull);
    });

    test('a picked friend wins over a typed email', () async {
      await service.createAndSendHunt(
        prompts: _fivePrompts(),
        friend: const Friend(uid: 'seeker', displayName: 'Bob'),
        email: 'ignored@example.com',
      );
      verify(() => invites.sendToFriend('seeker', any())).called(1);
      verifyNever(() => invites.sendToEmail(any(), any()));
    });
  });
}
