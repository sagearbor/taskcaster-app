import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuthException;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:taskcaster_app/core/models/user.dart';
import 'package:taskcaster_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:taskcaster_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:taskcaster_app/features/settings/presentation/screens/settings_screen.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late MockAuthRepository mockAuthRepository;
  late AuthBloc bloc;
  late User testUser;

  setUp(() {
    mockAuthRepository = MockAuthRepository();
    bloc = AuthBloc(authRepository: mockAuthRepository);
    testUser = User(
      id: 'uid-1',
      displayName: 'Sophie',
      email: 'sophie@example.com',
      createdAt: DateTime(2026, 1, 1),
    );
    when(() => mockAuthRepository.authStateChanges)
        .thenAnswer((_) => Stream.value('uid-1'));
    when(() => mockAuthRepository.getCurrentUser())
        .thenAnswer((_) async => testUser);
  });

  tearDown(() => bloc.close());

  // Places SettingsScreen behind a root route with a distinctive marker, so
  // "did we navigate back to it" is a plain findsOneWidget check.
  Widget appWithSettingsPushed() {
    return BlocProvider<AuthBloc>.value(
      value: bloc,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
              ),
              child: const Text('Root screen'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> pumpSignedInSettings(WidgetTester tester) async {
    // The Settings ListView is a real Sliver, which only builds children
    // near the viewport regardless of using a fixed children: list — the
    // Account section (Delete Account included) sits below the default
    // 800x600 test surface. Use a tall surface (mirrors settings_screen_test
    // .dart's pumpDark) so the whole list is built without needing to
    // scroll first.
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Doing a raw `await` on the bloc's stream (real Future/Stream
    // machinery, not tied to a widget rebuild) OUTSIDE tester.runAsync()
    // leaves flutter_test's fake-async test zone unable to track it —
    // subsequent tester.* calls (pumpWidget included) then hang forever.
    // runAsync() is the documented way to await genuine async work mid-test.
    await tester.runAsync(() async {
      bloc.add(AuthCheckRequested());
      await bloc.stream.firstWhere((s) => s is AuthAuthenticated);
    });
    await tester.pumpWidget(appWithSettingsPushed());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Root screen'));
    await tester.pumpAndSettle();
  }

  /// Taps a button that triggers a delete/reauth attempt, then waits for the
  /// bloc to reach a terminal state before pumping further frames.
  ///
  /// Deliberately NOT `pumpAndSettle()`: while the attempt is in flight the
  /// tile shows an indeterminate `CircularProgressIndicator`, whose animation
  /// never stops on its own — pumpAndSettle would spin (up to its 10-minute
  /// timeout) waiting for an animation that only stops once the bloc's
  /// terminal state flips `_deletingAccount` back to false.
  Future<void> tapAndAwaitTerminalState(
      WidgetTester tester, Finder button) async {
    // Subscribe BEFORE tapping: some stubs reject synchronously
    // (thenThrow), so the bloc can already have emitted the terminal state
    // by the time a tap() call returns — subscribing first means we can
    // never miss it, regardless of how the mock resolves.
    final terminalState = bloc.stream.firstWhere((s) =>
        s is AuthAccountDeleted ||
        s is AuthReauthenticationRequired ||
        s is AuthAccountDeletionFailure);
    await tester.tap(button);
    await tester.pump(); // the tap's setState -> spinner appears
    // See the comment on pumpSignedInSettings: awaiting the bloc's stream
    // directly must happen inside runAsync(), not as a bare await here.
    await tester.runAsync(() => terminalState);
    // Let the BlocListener's setState/Navigator/dialog reaction, and any
    // (finite) route or snackbar-entrance transition, play out. NOT
    // pumpAndSettle: a shown SnackBar auto-dismisses itself after ~4s via a
    // Timer, and pumpAndSettle would pump straight through that and leave
    // it already gone by the time control returns here.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('Delete Account tile', () {
    testWidgets('is present under Account and opens a warning dialog',
        (tester) async {
      await pumpSignedInSettings(tester);

      expect(find.text('Delete Account'), findsOneWidget);
      await tester.tap(find.text('Delete Account'));
      await tester.pumpAndSettle();

      expect(find.text('Delete My Account'), findsOneWidget);
      expect(find.textContaining('permanently deletes your account'),
          findsOneWidget);
    });

    testWidgets('Cancel dismisses the dialog without deleting anything',
        (tester) async {
      await pumpSignedInSettings(tester);

      await tester.tap(find.text('Delete Account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Delete My Account'), findsNothing);
      verifyNever(() => mockAuthRepository.deleteAccount());
    });

    testWidgets(
        'confirming deletion calls deleteAccount and returns to the root screen',
        (tester) async {
      when(() => mockAuthRepository.deleteAccount()).thenAnswer((_) async {});
      await pumpSignedInSettings(tester);

      await tester.tap(find.text('Delete Account'));
      await tester.pumpAndSettle();
      await tapAndAwaitTerminalState(tester, find.text('Delete My Account'));

      verify(() => mockAuthRepository.deleteAccount()).called(1);
      // AuthAccountDeleted -> the listener pops back to the first route.
      expect(find.text('Root screen'), findsOneWidget);
      expect(find.byType(SettingsScreen), findsNothing);
    });

    testWidgets(
        'requires-recent-login on a password account shows a password '
        're-auth dialog; confirming it reauthenticates then retries delete',
        (tester) async {
      var deleteCalls = 0;
      when(() => mockAuthRepository.deleteAccount()).thenAnswer((_) async {
        deleteCalls++;
        if (deleteCalls == 1) {
          throw FirebaseAuthException(code: 'requires-recent-login');
        }
      });
      when(() => mockAuthRepository.getCurrentUserProviderIds())
          .thenReturn(const ['password']);
      when(() => mockAuthRepository.reauthenticate(password: 'hunter2'))
          .thenAnswer((_) async {});
      await pumpSignedInSettings(tester);

      await tester.tap(find.text('Delete Account'));
      await tester.pumpAndSettle();
      await tapAndAwaitTerminalState(tester, find.text('Delete My Account'));

      // The password re-auth dialog appeared instead of an error snackbar.
      expect(find.text('Confirm it\'s you'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'hunter2');
      await tapAndAwaitTerminalState(tester, find.text('Confirm & Delete'));

      verify(() => mockAuthRepository.reauthenticate(password: 'hunter2'))
          .called(1);
      expect(deleteCalls, 2);
      expect(find.text('Root screen'), findsOneWidget);
    });

    testWidgets(
        'requires-recent-login on a Google account offers "Continue with '
        'Google" instead of a password field', (tester) async {
      when(() => mockAuthRepository.deleteAccount()).thenAnswer(
          (_) async => throw FirebaseAuthException(code: 'requires-recent-login'));
      when(() => mockAuthRepository.getCurrentUserProviderIds())
          .thenReturn(const ['google.com']);
      await pumpSignedInSettings(tester);

      await tester.tap(find.text('Delete Account'));
      await tester.pumpAndSettle();
      await tapAndAwaitTerminalState(tester, find.text('Delete My Account'));

      expect(find.text('Confirm it\'s you'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Continue with Google'), findsOneWidget);
    });

    testWidgets('a non-Firebase delete failure shows a snackbar and stays put',
        (tester) async {
      // Deliberately not a network-sounding message (FriendlyErrors.action
      // special-cases those) — this exercises the generic fallback path.
      when(() => mockAuthRepository.deleteAccount())
          .thenThrow(Exception('boom'));
      await pumpSignedInSettings(tester);

      await tester.tap(find.text('Delete Account'));
      await tester.pumpAndSettle();
      await tapAndAwaitTerminalState(tester, find.text('Delete My Account'));

      expect(
        find.text('Could not delete your account. Please try again.'),
        findsOneWidget,
      );
      expect(find.byType(SettingsScreen), findsOneWidget);
    });
  });
}
