import 'package:bloc_test/bloc_test.dart';
import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuthException;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:taskcaster_app/core/models/user.dart';
import 'package:taskcaster_app/core/utils/friendly_errors.dart';
import 'package:taskcaster_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:taskcaster_app/features/auth/presentation/bloc/auth_bloc.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  group('AuthBloc Tests', () {
    late AuthBloc authBloc;
    late MockAuthRepository mockAuthRepository;
    late User testUser;

    setUp(() {
      mockAuthRepository = MockAuthRepository();
      authBloc = AuthBloc(authRepository: mockAuthRepository);
      testUser = User(
        id: 'test_user_id',
        displayName: 'Test User',
        email: 'test@example.com',
        createdAt: DateTime.now(),
      );
    });

    tearDown(() {
      authBloc.close();
    });

    test('initial state should be AuthInitial', () {
      expect(authBloc.state, equals(AuthInitial()));
    });

    group('SignInRequested', () {
      blocTest<AuthBloc, AuthState>(
        'emits [AuthLoading, AuthAuthenticated] when sign in is successful',
        build: () {
          when(() => mockAuthRepository.signInWithEmailAndPassword(any(), any()))
              .thenAnswer((_) async => testUser);
          return authBloc;
        },
        act: (bloc) => bloc.add(const SignInRequested(
          email: 'test@example.com',
          password: 'password123',
        )),
        expect: () => [
          AuthLoading(),
          AuthAuthenticated(user: testUser),
        ],
      );

      blocTest<AuthBloc, AuthState>(
        'maps wrong-password to human copy (never the raw exception)',
        build: () {
          when(() => mockAuthRepository.signInWithEmailAndPassword(any(), any()))
              .thenThrow(FirebaseAuthException(code: 'wrong-password'));
          return authBloc;
        },
        act: (bloc) => bloc.add(const SignInRequested(
          email: 'test@example.com',
          password: 'wrongpassword',
        )),
        expect: () => [
          AuthLoading(),
          const AuthError(
              message: 'Email or password doesn\'t match. Please try again.'),
        ],
      );

      blocTest<AuthBloc, AuthState>(
        'falls back to friendly generic copy for unknown errors',
        build: () {
          when(() => mockAuthRepository.signInWithEmailAndPassword(any(), any()))
              .thenThrow(Exception('Invalid credentials'));
          return authBloc;
        },
        act: (bloc) => bloc.add(const SignInRequested(
          email: 'test@example.com',
          password: 'wrongpassword',
        )),
        expect: () => [
          AuthLoading(),
          const AuthError(message: FriendlyErrors.generic),
        ],
      );
    });

    group('SignUpRequested', () {
      blocTest<AuthBloc, AuthState>(
        'emits [AuthLoading, AuthAuthenticated] when sign up is successful',
        build: () {
          when(() => mockAuthRepository.createUserWithEmailAndPassword(
                any(),
                any(),
                any(),
              )).thenAnswer((_) async => testUser);
          return authBloc;
        },
        act: (bloc) => bloc.add(const SignUpRequested(
          email: 'test@example.com',
          password: 'password123',
          displayName: 'Test User',
        )),
        expect: () => [
          AuthLoading(),
          AuthAuthenticated(user: testUser),
        ],
      );

      blocTest<AuthBloc, AuthState>(
        'maps email-already-in-use to human copy',
        build: () {
          when(() => mockAuthRepository.createUserWithEmailAndPassword(
                any(),
                any(),
                any(),
              )).thenThrow(FirebaseAuthException(code: 'email-already-in-use'));
          return authBloc;
        },
        act: (bloc) => bloc.add(const SignUpRequested(
          email: 'test@example.com',
          password: 'password123',
          displayName: 'Test User',
        )),
        expect: () => [
          AuthLoading(),
          const AuthError(
              message:
                  'That email already has an account — try signing in instead.'),
        ],
      );
    });

    group('GoogleSignInRequested', () {
      blocTest<AuthBloc, AuthState>(
        'emits [AuthLoading, AuthAuthenticated] when Google sign in succeeds',
        build: () {
          when(() => mockAuthRepository.signInWithGoogle())
              .thenAnswer((_) async => testUser);
          return authBloc;
        },
        act: (bloc) => bloc.add(GoogleSignInRequested()),
        expect: () => [
          AuthLoading(),
          AuthAuthenticated(user: testUser),
        ],
        verify: (_) {
          verify(() => mockAuthRepository.signInWithGoogle()).called(1);
        },
      );

      blocTest<AuthBloc, AuthState>(
        'emits [AuthLoading, AuthError] when Google sign in is cancelled',
        build: () {
          when(() => mockAuthRepository.signInWithGoogle())
              .thenThrow(Exception('Google sign-in was cancelled'));
          return authBloc;
        },
        act: (bloc) => bloc.add(GoogleSignInRequested()),
        expect: () => [
          AuthLoading(),
          const AuthError(message: 'Sign-in was cancelled.'),
        ],
      );
    });

    group('AppleSignInRequested', () {
      blocTest<AuthBloc, AuthState>(
        'emits [AuthLoading, AuthAuthenticated] when Apple sign in succeeds',
        build: () {
          when(() => mockAuthRepository.signInWithApple())
              .thenAnswer((_) async => testUser);
          return authBloc;
        },
        act: (bloc) => bloc.add(AppleSignInRequested()),
        expect: () => [
          AuthLoading(),
          AuthAuthenticated(user: testUser),
        ],
        verify: (_) {
          verify(() => mockAuthRepository.signInWithApple()).called(1);
        },
      );

      blocTest<AuthBloc, AuthState>(
        'emits [AuthLoading, AuthError] when Apple sign in fails',
        build: () {
          when(() => mockAuthRepository.signInWithApple())
              .thenThrow(Exception('Apple sign-in failed'));
          return authBloc;
        },
        act: (bloc) => bloc.add(AppleSignInRequested()),
        expect: () => [
          AuthLoading(),
          const AuthError(message: FriendlyErrors.generic),
        ],
      );
    });

    group('SignOutRequested', () {
      blocTest<AuthBloc, AuthState>(
        'emits [AuthLoading, AuthUnauthenticated] when sign out is successful',
        build: () {
          when(() => mockAuthRepository.signOut()).thenAnswer((_) async {});
          return authBloc;
        },
        act: (bloc) => bloc.add(SignOutRequested()),
        expect: () => [
          AuthLoading(),
          AuthUnauthenticated(),
        ],
      );

      blocTest<AuthBloc, AuthState>(
        'emits [AuthLoading, AuthError] when sign out fails',
        build: () {
          when(() => mockAuthRepository.signOut())
              .thenThrow(Exception('Sign out failed'));
          return authBloc;
        },
        act: (bloc) => bloc.add(SignOutRequested()),
        expect: () => [
          AuthLoading(),
          const AuthError(message: FriendlyErrors.generic),
        ],
      );
    });

    group('AuthCheckRequested', () {
      blocTest<AuthBloc, AuthState>(
        'listens to auth state changes and emits corresponding states',
        build: () {
          when(() => mockAuthRepository.authStateChanges)
              .thenAnswer((_) => Stream.value('test_user_id'));
          when(() => mockAuthRepository.getCurrentUser())
              .thenAnswer((_) async => testUser);
          return authBloc;
        },
        act: (bloc) => bloc.add(AuthCheckRequested()),
        expect: () => [
          AuthLoading(),
          AuthAuthenticated(user: testUser),
        ],
      );

      blocTest<AuthBloc, AuthState>(
        'emits AuthUnauthenticated when auth state is null',
        build: () {
          when(() => mockAuthRepository.authStateChanges)
              .thenAnswer((_) => Stream.value(null));
          return authBloc;
        },
        act: (bloc) => bloc.add(AuthCheckRequested()),
        expect: () => [
          AuthLoading(),
          AuthUnauthenticated(),
        ],
      );
    });
  });
}