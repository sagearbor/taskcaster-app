import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:taskcaster_app/core/models/user.dart';
import 'package:taskcaster_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:taskcaster_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:taskcaster_app/features/auth/presentation/screens/create_account_screen.dart';

class _Repo extends Mock implements AuthRepository {}

/// The guest "Save your progress" screen offers Google/Apple as well as
/// email, and tells the player plainly when Google/Apple put them in an
/// existing account instead of upgrading the guest.
void main() {
  late _Repo repo;
  late AuthBloc bloc;
  final user = User(
    id: 'real-9',
    displayName: 'Gina',
    email: 'g@example.com',
    createdAt: DateTime(2026),
  );

  setUp(() => repo = _Repo());

  Future<void> pump(WidgetTester tester) async {
    // Built inside the test's fake-async zone so pumpAndSettle drives it.
    bloc = AuthBloc(authRepository: repo);
    addTearDown(bloc.close);
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => BlocProvider.value(
                value: bloc,
                child: const CreateAccountScreen(),
              ),
            )),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('offers Continue with Google and Apple', (tester) async {
    await pump(tester);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with Apple'), findsOneWidget);
  });

  testWidgets('shows the existing-account notice instead of "created"',
      (tester) async {
    when(() => repo.signInWithGoogle()).thenAnswer((_) async => user);
    when(() => repo.takeSignInNotice())
        .thenReturn('Signed in to your existing account');
    await pump(tester);

    final google = find.text('Continue with Google');
    await tester.ensureVisible(google);
    await tester.pumpAndSettle();
    await tester.tap(google);
    await tester.pumpAndSettle();

    expect(find.text('Signed in to your existing account'), findsOneWidget);
    expect(find.textContaining('Account created'), findsNothing);
  });
}
