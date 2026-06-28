abstract class AuthRemoteDataSource {
  Stream<String?> get authStateChanges;
  Future<String> signInWithEmailAndPassword(String email, String password);
  Future<String> createUserWithEmailAndPassword(String email, String password);
  Future<String> signInAnonymously();

  /// Sign in with Google. Returns the Firebase uid of the signed-in user.
  /// Throws if the user cancels the picker or the credential exchange fails.
  Future<String> signInWithGoogle();

  /// Sign in with Apple. Returns the Firebase uid of the signed-in user.
  /// On Android this drives Apple's web OAuth flow (Services ID + redirect).
  /// Throws if the user cancels or the credential exchange fails.
  Future<String> signInWithApple();

  Future<void> signOut();
  String? getCurrentUserId();

  /// Synchronous snapshot of the current user (displayName, email,
  /// isAnonymous). Used where an immediate, best-effort read is enough.
  Map<String, dynamic>? getCurrentUserData();

  /// Full async profile including avatarEmoji (read from persistent storage
  /// where applicable, e.g. the Firestore users/{uid} doc). Returns
  /// displayName, email, isAnonymous, avatarEmoji, createdAt.
  Future<Map<String, dynamic>?> getCurrentUserProfile();

  /// Update the signed-in user's display name and/or avatar emoji.
  Future<void> updateProfile({String? displayName, String? avatarEmoji});

  /// Send a password-reset email.
  Future<void> sendPasswordReset(String email);

  /// Convert the current anonymous user into a permanent email/password
  /// account WITHOUT changing their uid (so existing game data is preserved).
  /// Returns the (unchanged) uid.
  Future<String> upgradeGuestAccount(
      String email, String password, String displayName);
}
