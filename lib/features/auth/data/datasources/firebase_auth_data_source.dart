import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'auth_remote_data_source.dart';

class FirebaseAuthDataSource implements AuthRemoteDataSource {
  final firebase_auth.FirebaseAuth _firebaseAuth;
  final FirebaseFirestore _firestore;
  final GoogleSignIn _googleSignIn;

  /// Apple "Services ID" — the identifier you register under
  /// Certificates, Identifiers & Profiles → Identifiers → Services IDs in the
  /// Apple Developer console. It is the OAuth client_id for the Android/web
  /// Apple sign-in flow. This MUST match the value configured both in the
  /// Apple console and in the Firebase console (Authentication → Sign-in
  /// method → Apple → "Services ID"). See SOCIAL_LOGIN_SETUP.md.
  static const String _appleServiceId = 'com.sagearbor.taskcaster.signin';

  /// Where Apple returns the user after web auth. For Firebase this is always
  /// the project's auth handler. The Services ID above must list this exact
  /// URL as a "Return URL" in the Apple console.
  static const String _appleRedirectUri =
      'https://taskmaster-app-3d480.firebaseapp.com/__/auth/handler';

  // Best-effort cache so the synchronous getCurrentUserData() can surface the
  // avatar emoji once it has been loaded via getCurrentUserProfile().
  String? _cachedAvatarEmoji;

  FirebaseAuthDataSource({
    firebase_auth.FirebaseAuth? firebaseAuth,
    FirebaseFirestore? firestore,
    GoogleSignIn? googleSignIn,
  })  : _firebaseAuth = firebaseAuth ?? firebase_auth.FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _googleSignIn = googleSignIn ?? GoogleSignIn();

  static const String _usersCollection = 'users';

  @override
  Stream<String?> get authStateChanges {
    return _firebaseAuth.authStateChanges().map((user) => user?.uid);
  }

  @override
  Future<String> signInWithEmailAndPassword(
      String email, String password) async {
    final credential = await _firebaseAuth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    _cachedAvatarEmoji = null;
    return credential.user!.uid;
  }

  @override
  Future<String> createUserWithEmailAndPassword(
      String email, String password) async {
    final credential = await _firebaseAuth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    _cachedAvatarEmoji = null;
    return credential.user!.uid;
  }

  @override
  Future<String> signInAnonymously() async {
    final credential = await _firebaseAuth.signInAnonymously();
    _cachedAvatarEmoji = null;
    return credential.user!.uid;
  }

  @override
  Future<String> signInWithGoogle() async {
    // 1. Native account picker. Returns null if the user backs out.
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) {
      throw Exception('Google sign-in was cancelled');
    }

    // 2. Pull the OAuth tokens for the chosen account. The idToken is what
    //    Firebase verifies; it is populated because google-services.json
    //    carries the "web" OAuth client (client_type 3), which the
    //    google-services Gradle plugin exposes as default_web_client_id.
    final googleAuth = await googleUser.authentication;
    final credential = firebase_auth.GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    // 3. Exchange the Google credential for a Firebase session.
    final result = await _firebaseAuth.signInWithCredential(credential);
    final user = result.user!;
    _cachedAvatarEmoji = null;
    await _upsertUserDoc(user);
    return user.uid;
  }

  @override
  Future<String> signInWithApple() async {
    // Firebase requires the SHA-256 of a random nonce to be embedded in the
    // Apple identity token; we send the raw nonce back to Firebase so it can
    // verify the hash matches (replay protection).
    final rawNonce = _generateNonce();
    final hashedNonce = _sha256(rawNonce);

    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: const [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: hashedNonce,
      // Required on Android (and web): Apple has no native SDK there, so the
      // sign-in runs through Apple's web OAuth page. The clientId is the
      // Services ID and redirectUri is the Firebase auth handler.
      webAuthenticationOptions: WebAuthenticationOptions(
        clientId: _appleServiceId,
        redirectUri: Uri.parse(_appleRedirectUri),
      ),
    );

    final oauthCredential =
        firebase_auth.OAuthProvider('apple.com').credential(
      idToken: appleCredential.identityToken,
      rawNonce: rawNonce,
      accessToken: appleCredential.authorizationCode,
    );

    final result = await _firebaseAuth.signInWithCredential(oauthCredential);
    final user = result.user!;

    // Apple only returns the full name on the FIRST authorization, and never
    // in the identity token — so set it on the Firebase user when present.
    final givenName = appleCredential.givenName;
    final familyName = appleCredential.familyName;
    if ((user.displayName == null || user.displayName!.isEmpty) &&
        (givenName != null || familyName != null)) {
      final fullName =
          [givenName, familyName].whereType<String>().join(' ').trim();
      if (fullName.isNotEmpty) {
        await user.updateDisplayName(fullName);
        await user.reload();
      }
    }

    _cachedAvatarEmoji = null;
    await _upsertUserDoc(_firebaseAuth.currentUser ?? user);
    return user.uid;
  }

  @override
  Future<void> signOut() async {
    _cachedAvatarEmoji = null;
    // Also clear the cached Google account so the next sign-in re-prompts the
    // picker instead of silently reusing the last account.
    try {
      await _googleSignIn.signOut();
    } catch (_) {
      // Non-fatal: Google may not have been used this session.
    }
    await _firebaseAuth.signOut();
  }

  @override
  String? getCurrentUserId() {
    return _firebaseAuth.currentUser?.uid;
  }

  @override
  Map<String, dynamic>? getCurrentUserData() {
    final user = _firebaseAuth.currentUser;
    if (user == null) return null;

    return {
      'displayName': user.displayName,
      'email': user.email,
      'isAnonymous': user.isAnonymous,
      'avatarEmoji': _cachedAvatarEmoji,
    };
  }

  @override
  Future<Map<String, dynamic>?> getCurrentUserProfile() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return null;

    String? avatarEmoji;
    DateTime? createdAt;
    try {
      final doc =
          await _firestore.collection(_usersCollection).doc(user.uid).get();
      final data = doc.data();
      if (data != null) {
        avatarEmoji = data['avatarEmoji'] as String?;
        final created = data['createdAt'];
        if (created is Timestamp) {
          createdAt = created.toDate();
        } else if (created is String) {
          createdAt = DateTime.tryParse(created);
        }
      }
    } catch (_) {
      // Profile doc is optional; fall back to auth-only data.
    }
    _cachedAvatarEmoji = avatarEmoji;

    return {
      'displayName': user.displayName,
      'email': user.email,
      'isAnonymous': user.isAnonymous,
      'avatarEmoji': avatarEmoji,
      if (createdAt != null) 'createdAt': createdAt.toIso8601String(),
    };
  }

  @override
  Future<void> updateProfile({String? displayName, String? avatarEmoji}) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      throw Exception('No signed-in user to update');
    }
    if (displayName != null && displayName.trim().isNotEmpty) {
      await user.updateDisplayName(displayName.trim());
    }
    if (avatarEmoji != null) {
      _cachedAvatarEmoji = avatarEmoji.isEmpty ? null : avatarEmoji;
    }
    // Persist to the users/{uid} doc (merge) so it survives across sessions.
    final update = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (displayName != null && displayName.trim().isNotEmpty) {
      update['displayName'] = displayName.trim();
    }
    if (avatarEmoji != null) {
      update['avatarEmoji'] = avatarEmoji.isEmpty ? null : avatarEmoji;
    }
    if (user.email != null) update['email'] = user.email;
    await _firestore
        .collection(_usersCollection)
        .doc(user.uid)
        .set(update, SetOptions(merge: true));
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    await _firebaseAuth.sendPasswordResetEmail(email: email);
  }

  @override
  Future<String> upgradeGuestAccount(
      String email, String password, String displayName) async {
    final user = _firebaseAuth.currentUser;
    if (user == null || !user.isAnonymous) {
      throw Exception('Only a guest account can be upgraded');
    }
    // Linking preserves the uid (and therefore all existing game data).
    final credential = firebase_auth.EmailAuthProvider.credential(
      email: email,
      password: password,
    );
    final result = await user.linkWithCredential(credential);
    final linkedUser = result.user!;
    if (displayName.trim().isNotEmpty) {
      await linkedUser.updateDisplayName(displayName.trim());
    }
    await _firestore.collection(_usersCollection).doc(linkedUser.uid).set({
      'displayName': displayName.trim().isNotEmpty
          ? displayName.trim()
          : email.split('@')[0],
      'email': email,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return linkedUser.uid;
  }

  /// Create/merge the users/{uid} profile doc after a social sign-in so the
  /// display name + email are persisted (mirrors email/password sign-up).
  Future<void> _upsertUserDoc(firebase_auth.User user) async {
    try {
      final fallbackName = user.email != null && user.email!.contains('@')
          ? user.email!.split('@')[0]
          : 'Player';
      await _firestore.collection(_usersCollection).doc(user.uid).set({
        'displayName': (user.displayName != null &&
                user.displayName!.trim().isNotEmpty)
            ? user.displayName!.trim()
            : fallbackName,
        if (user.email != null) 'email': user.email,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Non-fatal: the auth session is valid even if the profile write fails.
    }
  }

  /// Cryptographically-random nonce (Apple sign-in replay protection).
  static String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }

  static String _sha256(String input) {
    final bytes = utf8.encode(input);
    return sha256.convert(bytes).toString();
  }
}
