import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/di/service_locator.dart';
import 'package:taskcaster_app/core/theme/app_theme.dart';
import 'package:taskcaster_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:taskcaster_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:taskcaster_app/features/auth/presentation/screens/auth_wrapper.dart';

/// Drives the real app widgets (mock services) through the first-run flow a
/// new player sees: login -> guest sign-in -> home -> open the public games
/// gallery -> clone a template. Uses the same shell wiring as main_mock
/// (AuthBloc ABOVE MaterialApp) so pushed routes can read AuthBloc — exactly
/// the structure that has to hold for the Discover "Play these tasks" clone
/// (which reads AuthBloc) to work.
Widget _appUnderTest() {
  return BlocProvider(
    create: (_) => AuthBloc(authRepository: sl<AuthRepository>())
      ..add(AuthCheckRequested()),
    child: MaterialApp(
      title: 'TaskCaster Party App',
      theme: AppTheme.lightTheme,
      home: const AuthWrapper(),
    ),
  );
}

void main() {
  setUp(() => ServiceLocator.init(useMockServices: true));
  tearDown(() => sl.reset());

  testWidgets('guest sign-in -> home -> discover -> clone a public game',
      (tester) async {
    // Tall viewport so the home ListView builds all the way down to the Play
    // button (it sits below the seeded games list; a short viewport would lazily
    // skip it).
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_appUnderTest());
    await tester.pumpAndSettle();

    // Login screen is guest-first: the primary action is one big "Play"
    // button that does the anonymous sign-in.
    expect(find.text('Play'), findsOneWidget);
    await tester.tap(find.text('Play'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    // Home screen — the one big Play button opens the destinations sheet.
    expect(find.text('Play'), findsOneWidget);
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();

    // Open the public games gallery via the sheet's Discover row.
    await tester.tap(find.text('Discover'));
    await tester.pumpAndSettle();
    expect(find.text('Discover Games'), findsOneWidget);
    expect(find.text('Weekend Warriors'), findsOneWidget);

    // Clone a public game — this reads AuthBloc, so it would throw a
    // ProviderNotFound if AuthBloc weren't above the navigator.
    await tester.tap(find.text('Play these tasks').first);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    // No exception, and we navigated off the gallery into the cloned game.
    expect(tester.takeException(), isNull);
    expect(find.text('Discover Games'), findsNothing);
  });
}
