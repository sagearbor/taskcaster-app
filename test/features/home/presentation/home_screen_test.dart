import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/config/environment.dart';
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
  tearDown(() => AppConfig.debugLabModesOverride = null);

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

  testWidgets(
      'the invites section self-hides when there are no invites (no empty '
      'shame box)', (tester) async {
    await pumpHome(tester);

    // The widget is mounted (it still needs to watch the invites stream so
    // it can appear the moment an invite arrives) but renders nothing (a
    // zero-size SizedBox.shrink(), hence skipOffstage: false below) — no
    // "Invites from friends" header, no "No invites yet" shame box.
    expect(
      find.byType(HomeInvitesSection, skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('Invites from friends'), findsNothing);
    expect(find.textContaining('No invites yet'), findsNothing);
  });

  testWidgets('the one big Play button opens the three-row release sheet',
      (tester) async {
    AppConfig.debugLabModesOverride = false;
    await pumpHome(tester);

    expect(find.text('Play'), findsOneWidget);
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();

    expect(find.text('Challenge friends'), findsOneWidget);
    expect(find.text('Join with a code'), findsOneWidget);
    expect(find.text('Drawing Telephone (same room)'), findsOneWidget);
    expect(find.text('Quick Play'), findsNothing);
    expect(find.text('Discover'), findsNothing);
  });

  testWidgets('Challenge friends lands in the new lobby with the invite up',
      (tester) async {
    AppConfig.debugLabModesOverride = false;
    await tester.runAsync(() => sl<AuthRepository>().signInAnonymously());
    await pumpHome(tester);

    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Challenge friends'));
    // Mock repo create + addTasks, then the lobby's share dialog opens on
    // the first loaded frame.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }

    expect(find.text('Share Game Invite'), findsOneWidget);
  });

  testWidgets('Balloon Pop (Lab) offers a Solo / Multiplayer chooser',
      (tester) async {
    AppConfig.debugLabModesOverride = true;
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

  testWidgets(
      'zone 1 shows the starter-pack hero when the user has no starter game '
      'yet', (tester) async {
    await pumpHome(tester);

    // MockGameDataSource seeds ordinary games but no gameKind == 'starter'
    // one, so the hero should invite the (pre-round-7) user to start theirs.
    expect(
      find.textContaining('first ten tasks are waiting'),
      findsOneWidget,
    );
    expect(find.text('Start'), findsOneWidget);
  });

  testWidgets('the Arena button opens the Arena screen', (tester) async {
    await pumpHome(tester);

    await tester.tap(find.text('Arena — grade the crowd'));
    await tester.pumpAndSettle();

    expect(find.text('The Arena'), findsOneWidget);
  });

  testWidgets('the app bar no longer shows a Join button', (tester) async {
    await pumpHome(tester);
    // Code entry moved into the invites empty state + Play sheet.
    expect(find.widgetWithText(TextButton, 'Join'), findsNothing);
  });
}
