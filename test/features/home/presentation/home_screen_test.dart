import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/di/service_locator.dart';
import 'package:taskcaster_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:taskcaster_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:taskcaster_app/features/home/presentation/screens/home_screen.dart';

void main() {
  setUp(() async {
    await sl.reset();
    await ServiceLocator.init(useMockServices: true);
  });

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Keep the NearbyAutoCastBanner quietly idle during initState (its
    // Android path would hit real permission channels that don't exist under
    // flutter_test). The platform check runs synchronously in cubit.start(),
    // so the override can be cleared right after the first pump — and must
    // be, or the framework's invariant check fails the test.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await tester.pumpWidget(
        BlocProvider<AuthBloc>(
          create: (_) => AuthBloc(authRepository: sl<AuthRepository>()),
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
    // Let the games stream deliver its first snapshot.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('every destination the old four FABs served is still reachable',
      (tester) async {
    await pumpHome(tester);

    // The ONE floating action: Create Game.
    expect(find.text('Create Game'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);

    // Join lives in a persistent app-bar slot.
    expect(find.text('Join'), findsOneWidget);

    // AR Games and Discover are game-mode entries in the list.
    expect(find.text('AR Games'), findsOneWidget);
    expect(find.text('Discover'), findsOneWidget);

    // Existing game-mode banners are all still present.
    expect(find.text('Quick Play'), findsOneWidget);
    expect(find.text('Drawing Telephone'), findsOneWidget);
    expect(find.text('Trivia Buzzer'), findsOneWidget);
    expect(find.text('Balloon Blitz'), findsOneWidget);
  });

  testWidgets('the games list itself still renders alongside the entries',
      (tester) async {
    await pumpHome(tester);

    expect(find.text('Your games'), findsOneWidget);
    // Seeded mock games from MockGameDataSource.
    expect(find.text('Saturday Night Shenanigans'), findsOneWidget);
  });

  testWidgets('Join opens the join-game screen', (tester) async {
    await pumpHome(tester);

    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();

    expect(find.text('Join the Fun!'), findsOneWidget);
  });
}
