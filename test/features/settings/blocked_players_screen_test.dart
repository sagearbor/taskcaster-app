import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taskcaster_app/core/di/service_locator.dart';
import 'package:taskcaster_app/core/services/moderation/moderation_service.dart';
import 'package:taskcaster_app/core/theme/theme_controller.dart';
import 'package:taskcaster_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:taskcaster_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:taskcaster_app/features/settings/presentation/screens/blocked_players_screen.dart';
import 'package:taskcaster_app/features/settings/presentation/screens/settings_screen.dart';

void main() {
  late InMemoryModerationStore store;
  late ModerationService moderation;

  setUp(() {
    store = InMemoryModerationStore();
    moderation =
        ModerationService(store: store, cache: InMemoryModerationCache());
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: BlockedPlayersScreen(moderation: moderation, viewerId: 'me'),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('lists blocked players by name, house personas included',
      (tester) async {
    store.blocked['me'] = ['troll-uid', 'house:Greg'];
    store.names['troll-uid'] = 'Trevor';
    await pumpScreen(tester);

    expect(find.text('Blocked players'), findsOneWidget);
    expect(find.text('Trevor'), findsOneWidget);
    expect(find.text('Greg'), findsOneWidget);
    expect(find.text('Unblock'), findsNWidgets(2));
  });

  testWidgets('Unblock removes the player from the list and the account',
      (tester) async {
    store.blocked['me'] = ['troll-uid', 'house:Greg'];
    store.names['troll-uid'] = 'Trevor';
    await pumpScreen(tester);

    await tester.tap(find.byKey(const ValueKey('unblock-troll-uid')));
    await tester.pumpAndSettle();

    expect(find.text('Trevor'), findsNothing);
    expect(find.text('Greg'), findsOneWidget);
    expect(find.text('Trevor is unblocked.'), findsOneWidget);
    expect(store.blocked['me'], ['house:Greg']);
  });

  testWidgets('an empty list says how to block someone', (tester) async {
    await pumpScreen(tester);
    expect(find.byKey(const Key('blocked-players-empty')), findsOneWidget);
    expect(find.text('Unblock'), findsNothing);
  });

  testWidgets('Settings has a Blocked players entry that opens the screen',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await ThemeController.instance.setThemeMode(ThemeMode.system);
    await sl.reset();
    await ServiceLocator.init(useMockServices: true);
    addTearDown(sl.reset);
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(BlocProvider<AuthBloc>(
      create: (_) => AuthBloc(authRepository: sl<AuthRepository>()),
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('SAFETY'), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings-blocked-players')));
    await tester.pumpAndSettle();
    expect(find.byType(BlockedPlayersScreen), findsOneWidget);
    expect(find.byKey(const Key('blocked-players-empty')), findsOneWidget);
  });
}
