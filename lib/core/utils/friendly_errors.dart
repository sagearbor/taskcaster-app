import 'package:firebase_auth/firebase_auth.dart';

/// Central mapping from raw exceptions to short, human-readable copy.
///
/// UI code must never surface `e.toString()` to a player (that shows things
/// like `Exception: [firebase_auth/wrong-password] ...`). Log the real error
/// with `debugPrint` for diagnostics, then show one of these strings instead.
class FriendlyErrors {
  const FriendlyErrors._();

  /// Friendly catch-all when we have nothing more specific to say.
  static const String generic = 'Something went wrong. Please try again.';

  /// Shown whenever the underlying failure looks like connectivity.
  static const String noConnection =
      'No connection — check your internet and try again.';

  /// Human copy for a failed sign-in / sign-up / other auth operation.
  static String auth(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'wrong-password':
        case 'user-not-found':
        case 'invalid-credential':
        case 'INVALID_LOGIN_CREDENTIALS':
          return 'Email or password doesn\'t match. Please try again.';
        case 'email-already-in-use':
        case 'credential-already-in-use':
        case 'account-exists-with-different-credential':
          return 'That email already has an account — try signing in instead.';
        case 'weak-password':
          return 'That password is too weak — use at least 6 characters.';
        case 'invalid-email':
          return 'That doesn\'t look like a valid email address.';
        case 'user-disabled':
          return 'This account has been disabled.';
        case 'too-many-requests':
          return 'Too many attempts — wait a moment and try again.';
        case 'network-request-failed':
          return noConnection;
        case 'operation-not-allowed':
          return 'That sign-in method isn\'t available right now.';
        case 'requires-recent-login':
          return 'For security, please sign in again first.';
      }
      return generic;
    }
    final text = error.toString().toLowerCase();
    // The Google/Apple flows throw plain exceptions when the user backs out
    // of the account picker — that's not an error worth alarming anyone over.
    if (text.contains('cancel')) {
      return 'Sign-in was cancelled.';
    }
    if (_looksLikeNetworkProblem(text)) return noConnection;
    return generic;
  }

  /// Human copy for a failed non-auth action (create game, join, save, ...).
  /// Detects connectivity problems; otherwise returns the action-specific
  /// [fallback] so the player at least knows what didn't happen.
  static String action(Object error, {required String fallback}) {
    if (_looksLikeNetworkProblem(error.toString().toLowerCase())) {
      return noConnection;
    }
    return fallback;
  }

  static bool _looksLikeNetworkProblem(String text) {
    return text.contains('network') ||
        text.contains('socket') ||
        text.contains('unavailable') ||
        text.contains('timed out') ||
        text.contains('timeout');
  }
}
