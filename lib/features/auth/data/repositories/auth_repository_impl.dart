import '../../../../core/models/user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_data_source.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDataSource remoteDataSource;

  AuthRepositoryImpl(this.remoteDataSource);

  @override
  Stream<String?> get authStateChanges => remoteDataSource.authStateChanges;

  @override
  Future<User> signInWithEmailAndPassword(
      String email, String password) async {
    final userId =
        await remoteDataSource.signInWithEmailAndPassword(email, password);
    return User(
      id: userId,
      displayName: email.split('@')[0], // Simple display name extraction
      email: email,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<User> createUserWithEmailAndPassword(
      String email, String password, String displayName) async {
    final userId =
        await remoteDataSource.createUserWithEmailAndPassword(email, password);
    // Persist the chosen display name so it survives reloads.
    try {
      await remoteDataSource.updateProfile(displayName: displayName);
    } catch (_) {
      // Non-fatal: the account exists even if the name write fails.
    }
    return User(
      id: userId,
      displayName: displayName,
      email: email,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<void> signOut() => remoteDataSource.signOut();

  @override
  String? getCurrentUserId() => remoteDataSource.getCurrentUserId();

  @override
  Future<User?> getCurrentUser() async {
    final userId = getCurrentUserId();
    if (userId == null) return null;

    // Full profile (async) so avatarEmoji is included.
    final userData = await remoteDataSource.getCurrentUserProfile();
    if (userData == null) return null;

    final createdAtRaw = userData['createdAt'] as String?;

    return User(
      id: userId,
      displayName: userData['displayName'] ??
          userData['email']?.split('@')[0] ??
          (userData['isAnonymous'] == true ? 'Guest' : 'User'),
      email: userData['email'],
      createdAt: createdAtRaw != null
          ? (DateTime.tryParse(createdAtRaw) ?? DateTime.now())
          : DateTime.now(),
      avatarEmoji: userData['avatarEmoji'] as String?,
    );
  }

  @override
  Future<User> signInAnonymously() async {
    final userId = await remoteDataSource.signInAnonymously();
    return User(
      id: userId,
      displayName: 'Guest',
      email: null,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<User> signInWithGoogle() async {
    await remoteDataSource.signInWithGoogle();
    // Read back the full profile (displayName/email from the provider) so the
    // returned User matches what the rest of the app expects.
    final user = await getCurrentUser();
    if (user == null) {
      throw Exception('Google sign-in failed');
    }
    return user;
  }

  @override
  Future<User> signInWithApple() async {
    await remoteDataSource.signInWithApple();
    final user = await getCurrentUser();
    if (user == null) {
      throw Exception('Apple sign-in failed');
    }
    return user;
  }

  @override
  bool isCurrentUserAnonymous() {
    final userData = remoteDataSource.getCurrentUserData();
    return userData?['isAnonymous'] == true;
  }

  @override
  Future<User> updateProfile({String? displayName, String? avatarEmoji}) async {
    await remoteDataSource.updateProfile(
      displayName: displayName,
      avatarEmoji: avatarEmoji,
    );
    final updated = await getCurrentUser();
    if (updated == null) {
      throw Exception('No signed-in user to update');
    }
    return updated;
  }

  @override
  Future<void> sendPasswordReset(String email) =>
      remoteDataSource.sendPasswordReset(email);

  @override
  Future<User> upgradeGuestAccount(
      String email, String password, String displayName) async {
    final userId =
        await remoteDataSource.upgradeGuestAccount(email, password, displayName);
    return User(
      id: userId,
      displayName: displayName.trim().isNotEmpty
          ? displayName.trim()
          : email.split('@')[0],
      email: email,
      createdAt: DateTime.now(),
    );
  }
}
