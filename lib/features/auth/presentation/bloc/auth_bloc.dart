import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuthException;
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/models/user.dart';
import '../../../../core/utils/friendly_errors.dart';
import '../../domain/repositories/auth_repository.dart';

part 'auth_event.dart';
part 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository authRepository;

  AuthBloc({required this.authRepository}) : super(AuthInitial()) {
    on<AuthCheckRequested>(_onAuthCheckRequested);
    on<SignInRequested>(_onSignInRequested);
    on<SignUpRequested>(_onSignUpRequested);
    on<SignOutRequested>(_onSignOutRequested);
    on<AnonymousSignInRequested>(_onAnonymousSignInRequested);
    on<GoogleSignInRequested>(_onGoogleSignInRequested);
    on<AppleSignInRequested>(_onAppleSignInRequested);
    on<UpdateProfileRequested>(_onUpdateProfileRequested);
    on<UpgradeGuestRequested>(_onUpgradeGuestRequested);
    on<PasswordResetRequested>(_onPasswordResetRequested);
    on<DeleteAccountRequested>(_onDeleteAccountRequested);
    on<AccountDeletionReauthenticated>(_onAccountDeletionReauthenticated);
  }

  Future<void> _onAuthCheckRequested(AuthCheckRequested event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    
    try {
      final user = await authRepository.getCurrentUser();
      if (user != null) {
        emit(AuthAuthenticated(user: user));
      } else {
        emit(AuthUnauthenticated());
      }
    } catch (e) {
      emit(AuthUnauthenticated());
    }
  }

  Future<void> _onSignInRequested(SignInRequested event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final user = await authRepository.signInWithEmailAndPassword(
        event.email,
        event.password,
      );
      emit(AuthAuthenticated(user: user));
    } catch (e) {
      emit(_authError('sign-in', e));
    }
  }

  /// Log the raw error for diagnostics, then emit copy a player can act on —
  /// never the exception string itself.
  AuthError _authError(String operation, Object e) {
    debugPrint('AuthBloc $operation failed: $e');
    return AuthError(message: FriendlyErrors.auth(e));
  }

  Future<void> _onSignUpRequested(SignUpRequested event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final user = await authRepository.createUserWithEmailAndPassword(
        event.email,
        event.password,
        event.displayName,
      );
      emit(AuthAuthenticated(user: user));
    } catch (e) {
      emit(_authError('sign-up', e));
    }
  }

  Future<void> _onSignOutRequested(SignOutRequested event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      await authRepository.signOut();
      emit(AuthUnauthenticated());
    } catch (e) {
      emit(_authError('sign-out', e));
    }
  }

  Future<void> _onAnonymousSignInRequested(AnonymousSignInRequested event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final user = await authRepository.signInAnonymously();
      emit(AuthAuthenticated(user: user));
    } catch (e) {
      emit(_authError('guest sign-in', e));
    }
  }

  Future<void> _onGoogleSignInRequested(
      GoogleSignInRequested event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final user = await authRepository.signInWithGoogle();
      emit(AuthAuthenticated(user: user));
    } catch (e) {
      emit(_authError('Google sign-in', e));
    }
  }

  Future<void> _onAppleSignInRequested(
      AppleSignInRequested event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final user = await authRepository.signInWithApple();
      emit(AuthAuthenticated(user: user));
    } catch (e) {
      emit(_authError('Apple sign-in', e));
    }
  }

  Future<void> _onUpdateProfileRequested(
      UpdateProfileRequested event, Emitter<AuthState> emit) async {
    final current = state;
    if (current is! AuthAuthenticated) return;
    try {
      final user = await authRepository.updateProfile(
        displayName: event.displayName,
        avatarEmoji: event.avatarEmoji,
      );
      emit(AuthProfileUpdated(user: user));
    } catch (e) {
      // Stay authenticated; surface the failure without flipping to login.
      debugPrint('AuthBloc profile update failed: $e');
      emit(AuthProfileUpdateFailure(
        user: current.user,
        message: FriendlyErrors.action(
          e,
          fallback: 'Could not update your profile. Please try again.',
        ),
      ));
    }
  }

  Future<void> _onUpgradeGuestRequested(
      UpgradeGuestRequested event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final user = await authRepository.upgradeGuestAccount(
        event.email,
        event.password,
        event.displayName,
      );
      emit(AuthAuthenticated(user: user));
    } catch (e) {
      emit(_authError('guest upgrade', e));
    }
  }

  Future<void> _onPasswordResetRequested(
      PasswordResetRequested event, Emitter<AuthState> emit) async {
    final previous = state;
    try {
      await authRepository.sendPasswordReset(event.email);
      emit(AuthPasswordResetSent(email: event.email));
    } catch (e) {
      emit(_authError('password reset', e));
    } finally {
      // Restore the prior screen state (authenticated or unauthenticated)
      // after the one-shot notification so navigation is unaffected.
      emit(previous);
    }
  }

  Future<void> _onDeleteAccountRequested(
      DeleteAccountRequested event, Emitter<AuthState> emit) async {
    final current = state;
    if (current is! AuthAuthenticated) return;
    emit(AuthLoading());
    await _attemptDeleteAccount(current.user, emit);
  }

  Future<void> _onAccountDeletionReauthenticated(
      AccountDeletionReauthenticated event, Emitter<AuthState> emit) async {
    final current = state;
    if (current is! AuthAuthenticated) return;
    emit(AuthLoading());
    try {
      await authRepository.reauthenticate(password: event.password);
    } catch (e) {
      debugPrint('AuthBloc reauthenticate failed: $e');
      emit(AuthAccountDeletionFailure(
        user: current.user,
        message: FriendlyErrors.action(
          e,
          fallback: 'Could not verify your identity. Please try again.',
        ),
      ));
      return;
    }
    await _attemptDeleteAccount(current.user, emit);
  }

  /// Shared tail of both delete-account entry points: call
  /// [AuthRepository.deleteAccount] and translate the outcome into a state.
  Future<void> _attemptDeleteAccount(User user, Emitter<AuthState> emit) async {
    try {
      await authRepository.deleteAccount();
      emit(AuthAccountDeleted());
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        emit(AuthReauthenticationRequired(
          user: user,
          providerIds: authRepository.getCurrentUserProviderIds(),
        ));
      } else {
        debugPrint('AuthBloc delete account failed: $e');
        emit(AuthAccountDeletionFailure(
          user: user,
          message: FriendlyErrors.action(
            e,
            fallback: 'Could not delete your account. Please try again.',
          ),
        ));
      }
    } catch (e) {
      debugPrint('AuthBloc delete account failed: $e');
      emit(AuthAccountDeletionFailure(
        user: user,
        message: FriendlyErrors.action(
          e,
          fallback: 'Could not delete your account. Please try again.',
        ),
      ));
    }
  }
}