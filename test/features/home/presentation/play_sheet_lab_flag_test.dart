import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/config/environment.dart';
import 'package:taskcaster_app/core/di/service_locator.dart';
import 'package:taskcaster_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:taskcaster_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:taskcaster_app/features/games/domain/repositories/game_repository.dart';
import 'package:taskcaster_app/features/games/presentation/bloc/games_bloc.dart';
import 'package:taskcaster_app/features/home/presentation/widgets/play_sheet.dart';

/// WP-06: release builds show exactly four Play rows (party mode added with the in-person pack); everything else sits
/// behind AppConfig.labModes (--dart-define=LAB_MODES=true).
void main() {
  const shipped = [
    'Challenge friends',
    'Party mode (same room)',
    'Join with a code',
    'Drawing Telephone (same room)',
  ];
  const lab = [
    'Quick Play',
    'Trivia Buzzer',
    'Balloon Pop',
    'Treasure Hunt',
    'Tower Trials',
    'Gem Rush',
    'House Hunt',
    'Clue Hunt',
    'Create custom game',
    'Discover',
  ];

  setUp(() async {
    await sl.reset();
    await ServiceLocator.init(useMockServices: true);
  });
  tearDown(() {
    AppConfig.debugLabModesOverride = null;
    return sl.reset();
  });

  test('labModes defaults to off (no --dart-define)', () {
    expect(AppConfig.labModes, isFalse);
    expect(AppConfig.labModesEnabled, isFalse);
  });

  Future<GamesBloc> openSheet(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final gamesBloc = GamesBloc(
      gameRepository: sl<GameRepository>(),
      authRepository: sl<AuthRepository>(),
    );
    addTearDown(gamesBloc.close);
    final authBloc = AuthBloc(authRepository: sl<AuthRepository>());
    addTearDown(authBloc.close);

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<GamesBloc>.value(value: gamesBloc),
            BlocProvider<AuthBloc>.value(value: authBloc),
          ],
          child: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showPlaySheet(context),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return gamesBloc;
  }

  testWidgets('release (Lab off): exactly the shipped rows',
      (tester) async {
    AppConfig.debugLabModesOverride = false;
    await openSheet(tester);

    for (final name in shipped) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    for (final name in lab) {
      expect(find.text(name), findsNothing, reason: name);
    }
    expect(find.text('Lab'), findsNothing);
    expect(find.byType(ListTile), findsNWidgets(shipped.length));
  });

  testWidgets('Lab on: every row, shipped rows first', (tester) async {
    AppConfig.debugLabModesOverride = true;
    await openSheet(tester);

    for (final name in [...shipped, ...lab]) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    expect(find.text('Lab'), findsOneWidget);
    expect(find.byType(ListTile), findsNWidgets(shipped.length + lab.length));
  });

  testWidgets('no row title carries an emoji', (tester) async {
    AppConfig.debugLabModesOverride = true;
    await openSheet(tester);

    final emoji = RegExp(r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]',
        unicode: true);
    for (final tile in tester.widgetList<ListTile>(find.byType(ListTile))) {
      final title = (tile.title! as Text).data!;
      expect(emoji.hasMatch(title), isFalse, reason: title);
    }
  });

  testWidgets('Challenge friends closes the sheet and asks the bloc for a '
      'friend game', (tester) async {
    AppConfig.debugLabModesOverride = false;
    await tester.runAsync(() => sl<AuthRepository>().signInAnonymously());
    final bloc = await openSheet(tester);
    final states = <GamesState>[];
    final sub = bloc.stream.listen(states.add);
    addTearDown(sub.cancel);

    await tester.tap(find.text('Challenge friends'));
    // Mock repository delays run on the fake clock.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }

    expect(find.text('Challenge friends'), findsNothing);
    expect(states.whereType<ChallengeFriendsReady>(), isNotEmpty);
  });
}
