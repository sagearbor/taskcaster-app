import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/models/user.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/utils/funny_names.dart';
import '../../../friends/domain/repositories/invites_repository.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_data_source.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDataSource remoteDataSource;

  /// Optional post-sign-in collaborators. Nullable so existing tests can
  /// construct the repository with just a data source; wired up in the service
  /// locator for the real app.
  final InvitesRepository? invitesRepository;
  final NotificationService? notificationService;

  AuthRepositoryImpl(
    this.remoteDataSource, {
    this.invitesRepository,
    this.notificationService,
  });

  /// Fire-and-forget side effects that should run whenever a user becomes
  /// authenticated: claim any email invites addressed to them and register this
  /// device's FCM token. Wrapped so a failure never breaks sign-in, and never
  /// awaited so it never slows it down.
  void _afterSignIn(String userId) {
    unawaited(() async {
      try {
        await invitesRepository?.claimEmailInvites();
      } catch (e) {
        debugPrint('AuthRepositoryImpl.claimEmailInvites failed: $e');
      }
      try {
        await notificationService?.registerToken(userId);
      } catch (e) {
        debugPrint('AuthRepositoryImpl.registerToken failed: $e');
      }
    }());
  }

  /// A guest's name: whatever they chose, or their [FunnyNames] name when
  /// they have nothing better than a placeholder ("Guest", empty). In that
  /// case the funny name is also saved to the profile (Auth displayName and
  /// users/{uid}, both owner-writable) so friend-facing surfaces that read it
  /// directly, like invite accepts, carry it too. Best-effort and not
  /// awaited: the name is derived from the uid, so a failed write just means
  /// we try again next launch.
  String _guestName(String userId, String? stored) {
    final trimmed = stored?.trim() ?? '';
    // Already named (by us or by them): nothing to write.
    if (!FunnyNames.isPlaceholder(trimmed) || FunnyNames.isFunnyName(trimmed)) {
      return trimmed;
    }
    final name = FunnyNames.forUid(userId);
    unawaited(() async {
      try {
        await remoteDataSource.updateProfile(displayName: name);
      } catch (e) {
        debugPrint('AuthRepositoryImpl could not save the guest name: $e');
      }
    }());
    return name;
  }

  @override
  Stream<String?> get authStateChanges => remoteDataSource.authStateChanges;

  @override
  Future<User> signInWithEmailAndPassword(
      String email, String password) async {
    final userId =
        await remoteDataSource.signInWithEmailAndPassword(email, password);
    _afterSignIn(userId);
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
    _afterSignIn(userId);
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

    // App-restart with an existing session counts as a sign-in for the purpose
    // of claiming email invites / refreshing the FCM token.
    _afterSignIn(userId);

    final createdAtRaw = userData['createdAt'] as String?;

    final storedName = userData['displayName'] as String?;
    final email = userData['email'] as String?;
    final String displayName;
    if (userData['isAnonymous'] == true && email == null) {
      // Existing guests stored as "Guest" get their funny name here too.
      displayName = _guestName(userId, storedName);
    } else {
      displayName = storedName ?? email?.split('@')[0] ?? 'User';
    }

    return User(
      id: userId,
      displayName: displayName,
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
    // Anonymous users have no email to claim invites for, but registering the
    // FCM token is still worthwhile.
    _afterSignIn(userId);
    return User(
      id: userId,
      displayName: _guestName(userId, null),
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
  String? takeSignInNotice() => remoteDataSource.takeSignInNotice();

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
    // Now that the guest has a real email, claim any invites addressed to it.
    _afterSignIn(userId);
    return User(
      id: userId,
      displayName: displayName.trim().isNotEmpty
          ? displayName.trim()
          : email.split('@')[0],
      email: email,
      createdAt: DateTime.now(),
    );
  }

  @override
  List<String> getCurrentUserProviderIds() =>
      remoteDataSource.getCurrentUserProviderIds();

  @override
  Future<void> deleteAccount() => remoteDataSource.deleteAccount();

  @override
  Future<void> reauthenticate({String? password}) =>
      remoteDataSource.reauthenticate(password: password);
}
