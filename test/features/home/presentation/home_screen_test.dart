import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/di/service_locator.dart';
import 'package:taskcaster_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:taskcaster_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:taskcaster_app/features/home/presentation/screens/home_screen.dart';
import 'package:taskcaster_app/features/home/presentation/widgets/home_invites_section.dart';

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

  testWidgets('invites section sits at the top of home', (tester) async {
    await pumpHome(tester);

    expect(find.byType(HomeInvitesSection), findsOneWidget);
    expect(find.text('Invites from friends'), findsOneWidget);

    // The invites section must be above the "Jump back in" / games list — it's
    // the first thing an invited player sees.
    final invitesY =
        tester.getTopLeft(find.byType(HomeInvitesSection)).dy;
    final playY = tester.getTopLeft(find.text('Play').first).dy;
    expect(invitesY, lessThan(playY));
  });

  testWidgets('the one big Play button opens a sheet listing all six '
      'destinations', (tester) async {
    await pumpHome(tester);

    expect(find.text('Play'), findsOneWidget);
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();

    // All six Play destinations + the code-join row.
    expect(find.text('Quick Play'), findsOneWidget);
    expect(find.text('Drawing Telephone'), findsOneWidget);
    expect(find.text('Trivia Buzzer'), findsOneWidget);
    expect(find.text('Balloon Pop'), findsOneWidget);
    expect(find.text('Create custom game'), findsOneWidget);
    expect(find.text('Discover'), findsOneWidget);
    expect(find.text('Join with a code'), findsOneWidget);
  });

  testWidgets('Balloon Pop offers a Solo / Multiplayer chooser',
      (tester) async {
    await pumpHome(tester);

    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Balloon Pop'));
    await tester.pumpAndSettle();

    expect(find.text('Solo'), findsOneWidget);
    expect(find.text('Multiplayer race'), findsOneWidget);
  });

  testWidgets('the games list still renders under "Jump back in"',
      (tester) async {
    await pumpHome(tester);

    // Seeded mock games from MockGameDataSource surface as resume/compact
    // cards under Zone 2.
    expect(find.text('Jump back in'), findsOneWidget);
    expect(find.text('Saturday Night Shenanigans'), findsOneWidget);
  });

  testWidgets('the app bar no longer shows a Join button', (tester) async {
    await pumpHome(tester);
    // Code entry moved into the invites empty state + Play sheet.
    expect(find.widgetWithText(TextButton, 'Join'), findsNothing);
  });
}
