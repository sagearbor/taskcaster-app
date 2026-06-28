part of 'auth_bloc.dart';

abstract class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object> get props => [];
}

class AuthCheckRequested extends AuthEvent {}

class SignInRequested extends AuthEvent {
  final String email;
  final String password;

  const SignInRequested({
    required this.email,
    required this.password,
  });

  @override
  List<Object> get props => [email, password];
}

class SignUpRequested extends AuthEvent {
  final String email;
  final String password;
  final String displayName;

  const SignUpRequested({
    required this.email,
    required this.password,
    required this.displayName,
  });

  @override
  List<Object> get props => [email, password, displayName];
}

class SignOutRequested extends AuthEvent {}

class AnonymousSignInRequested extends AuthEvent {}

/// Sign in with Google (native Android account picker → Firebase credential).
class GoogleSignInRequested extends AuthEvent {}

/// Sign in with Apple (web OAuth flow on Android → Firebase credential).
class AppleSignInRequested extends AuthEvent {}

/// Update the signed-in user's display name and/or avatar emoji.
class UpdateProfileRequested extends AuthEvent {
  final String? displayName;
  final String? avatarEmoji;

  const UpdateProfileRequested({this.displayName, this.avatarEmoji});

  @override
  List<Object> get props => [displayName ?? '', avatarEmoji ?? ''];
}

/// Convert a guest account into a permanent email/password account.
class UpgradeGuestRequested extends AuthEvent {
  final String email;
  final String password;
  final String displayName;

  const UpgradeGuestRequested({
    required this.email,
    required this.password,
    required this.displayName,
  });

  @override
  List<Object> get props => [email, password, displayName];
}

/// Send a password-reset email.
class PasswordResetRequested extends AuthEvent {
  final String email;

  const PasswordResetRequested({required this.email});

  @override
  List<Object> get props => [email];
}
