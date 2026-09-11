import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mocktail/mocktail.dart';
import 'package:taskcaster_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:taskcaster_app/features/auth/presentation/widgets/auth_form.dart';

class MockAuthBloc extends Mock implements AuthBloc {}

void main() {
  group('AuthForm Widget Tests', () {
    late MockAuthBloc mockAuthBloc;

    setUp(() {
      mockAuthBloc = MockAuthBloc();
      when(() => mockAuthBloc.state).thenReturn(AuthInitial());
      // BlocBuilder subscribes to .stream; mocktail returns null unless stubbed.
      when(() => mockAuthBloc.stream)
          .thenAnswer((_) => const Stream<AuthState>.empty());
    });

    Widget createTestWidget({
      required String title,
      required String buttonText,
      required bool showDisplayNameField,
      Function(String, String, String?)? onSubmit,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: BlocProvider<AuthBloc>.value(
            value: mockAuthBloc,
            child: AuthForm(
              title: title,
              buttonText: buttonText,
              showDisplayNameField: showDisplayNameField,
              onSubmit: onSubmit ?? (email, password, displayName) {},
            ),
          ),
        ),
      );
    }

    testWidgets('should display login form fields correctly', (tester) async {
      await tester.pumpWidget(createTestWidget(
        title: 'Sign In',
        buttonText: 'Sign In',
        showDisplayNameField: false,
      ));

      expect(find.byType(TextFormField), findsNWidgets(2)); // Email and password
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Sign In'), findsOneWidget);
      expect(find.text('Display Name'), findsNothing);
    });

    testWidgets('should display register form fields correctly', (tester) async {
      await tester.pumpWidget(createTestWidget(
        title: 'Create Account',
        buttonText: 'Sign Up',
        showDisplayNameField: true,
      ));

      expect(find.byType(TextFormField), findsNWidgets(3)); // Display name, email, and password
      expect(find.text('Display Name'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Sign Up'), findsOneWidget);
    });

    testWidgets('should validate email field correctly', (tester) async {
      await tester.pumpWidget(createTestWidget(
        title: 'Sign In',
        buttonText: 'Sign In',
        showDisplayNameField: false,
      ));

      final submitButton = find.text('Sign In');
      await tester.tap(submitButton);
      await tester.pump();

      expect(find.text('Email is required'), findsOneWidget);

      // Enter invalid email
      await tester.enterText(find.byType(TextFormField).first, 'invalid-email');
      await tester.tap(submitButton);
      await tester.pump();

      expect(find.text('Enter a valid email'), findsOneWidget);
    });

    testWidgets('should validate password field correctly', (tester) async {
      await tester.pumpWidget(createTestWidget(
        title: 'Sign In',
        buttonText: 'Sign In',
        showDisplayNameField: false,
      ));

      final submitButton = find.text('Sign In');
      await tester.tap(submitButton);
      await tester.pump();

      expect(find.text('Password is required'), findsOneWidget);

      // Enter short password
      await tester.enterText(find.byType(TextFormField).last, '123');
      await tester.tap(submitButton);
      await tester.pump();

      expect(find.text('Password must be at least 6 characters'), findsOneWidget);
    });

    testWidgets('should validate display name field when shown', (tester) async {
      await tester.pumpWidget(createTestWidget(
        title: 'Create Account',
        buttonText: 'Sign Up',
        showDisplayNameField: true,
      ));

      final submitButton = find.text('Sign Up');
      await tester.tap(submitButton);
      await tester.pump();

      expect(find.text('Display name is required'), findsOneWidget);

      // Enter short display name
      await tester.enterText(find.byType(TextFormField).first, 'A');
      await tester.tap(submitButton);
      await tester.pump();

      expect(find.text('Display name must be at least 2 characters'), findsOneWidget);
    });

    testWidgets('should toggle password visibility', (tester) async {
      await tester.pumpWidget(createTestWidget(
        title: 'Sign In',
        buttonText: 'Sign In',
        showDisplayNameField: false,
      ));

      // The password field is the last text input; inspect the rendered
      // EditableText to verify obscuring (TextFormField doesn't expose it).
      final passwordEditable =
          tester.widget<EditableText>(find.byType(EditableText).last);

      // Initially password should be obscured, with the "eye" icon inviting
      // a tap to reveal it (conventional semantics).
      expect(passwordEditable.obscureText, true);
      expect(find.byIcon(Icons.visibility), findsOneWidget);

      // Tap visibility toggle
      final visibilityToggle = find.byIcon(Icons.visibility);
      await tester.tap(visibilityToggle);
      await tester.pump();

      // Now visible: the icon flips to "eye off" (tap to hide again).
      expect(find.byIcon(Icons.visibility_off), findsOneWidget);
    });

    testWidgets('should call onSubmit with correct parameters', (tester) async {
      String? submittedEmail;
      String? submittedPassword;
      String? submittedDisplayName;

      await tester.pumpWidget(createTestWidget(
        title: 'Create Account',
        buttonText: 'Sign Up',
        showDisplayNameField: true,
        onSubmit: (email, password, displayName) {
          submittedEmail = email;
          submittedPassword = password;
          submittedDisplayName = displayName;
        },
      ));

      // Fill form with valid data
      await tester.enterText(find.byType(TextFormField).first, 'Test User');
      await tester.enterText(find.byType(TextFormField).at(1), 'test@example.com');
      await tester.enterText(find.byType(TextFormField).last, 'password123');

      // Submit form
      await tester.tap(find.text('Sign Up'));
      await tester.pump();

      expect(submittedEmail, 'test@example.com');
      expect(submittedPassword, 'password123');
      expect(submittedDisplayName, 'Test User');
    });

    testWidgets('should show loading state when AuthLoading', (tester) async {
      when(() => mockAuthBloc.state).thenReturn(AuthLoading());

      await tester.pumpWidget(createTestWidget(
        title: 'Sign In',
        buttonText: 'Sign In',
        showDisplayNameField: false,
      ));

      // Button should show loading indicator
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      
      // Form fields should be disabled
      final emailField = tester.widget<TextFormField>(find.byType(TextFormField).first);
      expect(emailField.enabled, false);
    });

    testWidgets('should disable form when loading', (tester) async {
      when(() => mockAuthBloc.state).thenReturn(AuthLoading());

      await tester.pumpWidget(createTestWidget(
        title: 'Sign In',
        buttonText: 'Sign In',
        showDisplayNameField: false,
      ));

      final emailField = tester.widget<TextFormField>(find.byType(TextFormField).first);
      final passwordField = tester.widget<TextFormField>(find.byType(TextFormField).last);
      
      expect(emailField.enabled, false);
      expect(passwordField.enabled, false);
    });
  });
}