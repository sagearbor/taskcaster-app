import '../../../../core/models/user.dart';

abstract class AuthRepository {
  Stream<String?> get authStateChanges;
  Future<User> signInWithEmailAndPassword(String email, String password);
  Future<User> createUserWithEmailAndPassword(
      String email, String password, String displayName);
  Future<User> signInAnonymously();

  /// Sign in with Google (native Android flow). Returns the signed-in [User].
  Future<User> signInWithGoogle();

  /// Sign in with Apple (web OAuth flow on Android). Returns the [User].
  Future<User> signInWithApple();

  Future<void> signOut();
  String? getCurrentUserId();
  Future<User?> getCurrentUser();
  bool isCurrentUserAnonymous();

  /// Update the current user's profile. Returns the updated [User].
  Future<User> updateProfile({String? displayName, String? avatarEmoji});

  /// Send a password-reset email to [email].
  Future<void> sendPasswordReset(String email);

  /// Convert the current anonymous (guest) user into a permanent email/password
  /// account, preserving their uid (and all existing game data). Returns the
  /// upgraded [User].
  Future<User> upgradeGuestAccount(
      String email, String password, String displayName);

  /// Sign-in provider ids for the signed-in user (e.g. 'password',
  /// 'google.com', 'apple.com'); empty for a guest or signed-out user.
  List<String> getCurrentUserProviderIds();

  /// Permanently delete the signed-in user's account: their Firestore
  /// profile doc (and the fcmTokens/friend-links data it and its
  /// subcollections carry), then the Firebase Auth account itself. May throw
  /// a requires-recent-login auth error — call [reauthenticate] and retry.
  Future<void> deleteAccount();

  /// Re-authenticate the signed-in user ahead of a sensitive action that hit
  /// requires-recent-login. [password] is required only for email/password
  /// accounts.
  Future<void> reauthenticate({String? password});
}
