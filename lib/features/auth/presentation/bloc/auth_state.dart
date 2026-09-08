part of 'auth_bloc.dart';

abstract class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {}

class AuthLoading extends AuthState {}

class AuthAuthenticated extends AuthState {
  final User user;

  const AuthAuthenticated({required this.user});

  @override
  List<Object> get props => [user];
}

/// Emitted after a successful profile edit. Extends [AuthAuthenticated] so the
/// app stays on the authenticated screens; the profile screen listens for this
/// specific type to show a confirmation and pop.
class AuthProfileUpdated extends AuthAuthenticated {
  const AuthProfileUpdated({required super.user});
}

/// Emitted when a profile edit fails but the user is still signed in. Extends
/// [AuthAuthenticated] so we never flip back to the login screen on a
/// non-fatal error.
class AuthProfileUpdateFailure extends AuthAuthenticated {
  final String message;

  const AuthProfileUpdateFailure({required super.user, required this.message});

  @override
  List<Object> get props => [user, message];
}

/// Emitted when deleteAccount() hit Firebase's requires-recent-login check.
/// The UI should show a re-auth prompt matching [providerIds] (a password
/// field for an email/password account; a "Continue with Google/Apple"
/// button otherwise) and dispatch [AccountDeletionReauthenticated] once the
/// user has confirmed their identity.
class AuthReauthenticationRequired extends AuthAuthenticated {
  final List<String> providerIds;

  const AuthReauthenticationRequired({
    required super.user,
    required this.providerIds,
  });

  @override
  List<Object> get props => [user, providerIds];
}

/// Emitted when a delete-account attempt (or its re-authentication) fails.
/// Extends [AuthAuthenticated] so the app stays on the authenticated screens.
class AuthAccountDeletionFailure extends AuthAuthenticated {
  final String message;

  const AuthAccountDeletionFailure({required super.user, required this.message});

  @override
  List<Object> get props => [user, message];
}

class AuthUnauthenticated extends AuthState {}

/// Emitted once deleteAccount() has fully succeeded: the owned Firestore
/// data and the Firebase Auth user are both gone. Extends
/// [AuthUnauthenticated] so the auth wrapper naturally returns to sign-in.
class AuthAccountDeleted extends AuthUnauthenticated {}

/// Transient one-shot state: a password-reset email was sent.
class AuthPasswordResetSent extends AuthState {
  final String email;

  const AuthPasswordResetSent({required this.email});

  @override
  List<Object> get props => [email];
}

class AuthError extends AuthState {
  final String message;

  const AuthError({required this.message});

  @override
  List<Object> get props => [message];
}
