import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/di/service_locator.dart';
import 'package:taskcaster_app/core/models/game.dart';
import 'package:taskcaster_app/core/models/game_settings.dart';
import 'package:taskcaster_app/core/models/player.dart';
import 'package:taskcaster_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:taskcaster_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:taskcaster_app/features/friends/domain/repositories/friends_repository.dart';
import 'package:taskcaster_app/features/games/domain/repositories/game_repository.dart';
import 'package:taskcaster_app/features/house_hunt/domain/house_hunt_service.dart';
import 'package:taskcaster_app/features/house_hunt/presentation/screens/house_hunt_start_screen.dart';

void main() {
  setUp(() async {
    await sl.reset();
    await ServiceLocator.init(useMockServices: true);
  });

  // A friend the mock graph already knows about, so the picker shows a chip.
  Future<void> seedFriend() async {
    await sl<FriendsRepository>().addFriendsFromGame(
      Game(
        id: 'seed',
        gameName: 'Seed',
        creatorId: 'seeker',
        judgeId: 'seeker',
        status: GameStatus.completed,
        inviteCode: 'SEED12',
        createdAt: DateTime(2026, 1, 1),
        players: const [
          Player(userId: 'seeker', displayName: 'Bob', totalScore: 0),
          // The mock friend repo's "current user" — filtered out of the graph.
          Player(userId: 'mock_user', displayName: 'Me', totalScore: 0),
        ],
        tasks: const [],
        settings: GameSettings.quickPlay(),
      ),
    );
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      BlocProvider<AuthBloc>(
        create: (_) => AuthBloc(authRepository: sl<AuthRepository>()),
        child: const MaterialApp(home: HouseHuntStartScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('deals 5 prompts with swap/edit controls', (tester) async {
    await pumpScreen(tester);

    expect(find.text('🏠 House Hunt'), findsOneWidget);
    expect(find.text('Reshuffle'), findsOneWidget);
    // One swap + one edit control per prompt slot.
    expect(find.byIcon(Icons.refresh), findsNWidgets(HouseHuntService.huntSize));
    expect(find.byIcon(Icons.edit_outlined),
        findsNWidgets(HouseHuntService.huntSize));
  });

  testWidgets('happy path: deal 5 → pick a friend → send creates the hunt',
      (tester) async {
    await seedFriend();
    await pumpScreen(tester);

    // The seeded friend shows as a pickable chip.
    expect(find.text('Bob'), findsOneWidget);
    await tester.tap(find.text('Bob'));
    await tester.pump();

    // Send the hunt.
    final sendButton = find.text('Send the hunt 🏠');
    await tester.ensureVisible(sendButton);
    await tester.tap(sendButton);
    // Let sign-in + game creation + invite complete. The mock sources chain
    // ~1.3s of Future.delayed calls, so advance the fake clock across several
    // pumps (no pumpAndSettle: the destination lobby shimmer never settles).
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    // The created game has the House Hunt shape (the mock source also seeds
    // unrelated starter games, so filter to ours).
    final games = await sl<GameRepository>().getGamesStream().first;
    final hunts = games.where(HouseHuntService.isHouseHuntGame).toList();
    expect(hunts, hasLength(1));
    final game = hunts.single;
    expect(game.tasks.length, HouseHuntService.huntSize);
    expect(game.judgeId, game.creatorId); // hider is judge
    expect(HouseHuntService.isHouseHuntGame(game), isTrue);
    expect(game.players.single.userId, game.creatorId);
    for (final task in game.tasks) {
      expect(task.description, startsWith('Hunt!'));
    }
  });
}
