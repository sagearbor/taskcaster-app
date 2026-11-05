import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'auth_remote_data_source.dart';

/// Asks Apple for an ID credential bound to [hashedNonce]. The production
/// implementation is [SignInWithApple.getAppleIDCredential]; tests inject a
/// fake so the link-vs-sign-in branch can run off-device.
typedef AppleCredentialRequest = Future<AuthorizationCredentialAppleID>
    Function(String hashedNonce);

class FirebaseAuthDataSource implements AuthRemoteDataSource {
  final firebase_auth.FirebaseAuth _firebaseAuth;
  final FirebaseFirestore _firestore;
  final GoogleSignIn _googleSignIn;

  /// On the web, Google sign-in goes through Firebase's own OAuth popup
  /// instead of the google_sign_in plugin. The plugin's web implementation
  /// needs a `google-signin-client_id` and its `signIn()` no longer yields the
  /// tokens Firebase wants, so on the live site "Continue with Google" always
  /// failed with "Something went wrong". Injectable so the popup branch can be
  /// unit-tested off-web.
  final bool _useWebPopup;

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

  final AppleCredentialRequest _requestAppleCredential;

  /// Set when a guest's Google/Apple sign-in could not be linked because that
  /// Google/Apple identity already belongs to another account, so the session
  /// switched to that account instead. Read once via [takeSignInNotice].
  String? _signInNotice;

  /// The one-line message shown when a guest lands in an existing account.
  static const String existingAccountNotice =
      'Signed in to your existing account';

  FirebaseAuthDataSource({
    firebase_auth.FirebaseAuth? firebaseAuth,
    FirebaseFirestore? firestore,
    GoogleSignIn? googleSignIn,
    bool? useWebPopup,
    AppleCredentialRequest? appleCredentialRequest,
  })  : _firebaseAuth = firebaseAuth ?? firebase_auth.FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _googleSignIn = googleSignIn ?? GoogleSignIn(),
        _useWebPopup = useWebPopup ?? kIsWeb,
        _requestAppleCredential =
            appleCredentialRequest ?? _defaultAppleCredentialRequest;

  static const String _usersCollection = 'users';

  /// users/{uid} is readable by every signed-in user (it carries the display
  /// name and avatar other players see). Anything personal (today, the email
  /// address) lives in users/{uid}/private/profile instead, which
  /// firestore.rules restricts to the owner.
  static const String _privateCollection = 'private';
  static const String _privateProfileDoc = 'profile';

  DocumentReference<Map<String, dynamic>> _publicUserDoc(String uid) =>
      _firestore.collection(_usersCollection).doc(uid);

  DocumentReference<Map<String, dynamic>> _privateProfile(String uid) =>
      _publicUserDoc(uid).collection(_privateCollection).doc(_privateProfileDoc);

  static Future<AuthorizationCredentialAppleID> _defaultAppleCredentialRequest(
      String hashedNonce) {
    return SignInWithApple.getAppleIDCredential(
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
  }

  @override
  String? takeSignInNotice() {
    final notice = _signInNotice;
    _signInNotice = null;
    return notice;
  }

  /// Link error codes Firebase returns when the Google/Apple identity being
  /// linked already belongs to a different (non-guest) account.
  static bool _isAlreadyInUse(firebase_auth.FirebaseAuthException e) =>
      e.code == 'credential-already-in-use' ||
      e.code == 'email-already-in-use';

  /// Sign in with [credential], but if the current session is a guest, LINK
  /// the credential to it instead, so the uid (and with it the guest's games,
  /// posts and grades) carries over to the permanent account.
  /// signInWithCredential from a guest would mint a brand-new uid and orphan
  /// everything the guest made.
  ///
  /// If the identity is already attached to another account, the guest
  /// cannot be merged into it; we sign in to that account (the player's
  /// "real" one) and leave a notice for the UI.
  Future<firebase_auth.User> _linkOrSignIn(
      firebase_auth.AuthCredential credential) async {
    _signInNotice = null;
    final current = _firebaseAuth.currentUser;
    if (current != null && current.isAnonymous) {
      try {
        final result = await current.linkWithCredential(credential);
        return result.user ?? _firebaseAuth.currentUser ?? current;
      } on firebase_auth.FirebaseAuthException catch (e) {
        if (!_isAlreadyInUse(e)) rethrow;
        // Firebase hands back a fresh credential on iOS/Android (Apple's
        // nonce-bound token cannot be replayed); fall back to ours.
        final result =
            await _firebaseAuth.signInWithCredential(e.credential ?? credential);
        _signInNotice = existingAccountNotice;
        return result.user!;
      }
    }
    final result = await _firebaseAuth.signInWithCredential(credential);
    return result.user!;
  }

  /// Web counterpart of [_linkOrSignIn]: the OAuth popup flow.
  Future<firebase_auth.User> _linkOrSignInWithPopup(
      firebase_auth.AuthProvider provider) async {
    _signInNotice = null;
    final current = _firebaseAuth.currentUser;
    if (current != null && current.isAnonymous) {
      try {
        final result = await current.linkWithPopup(provider);
        return result.user ?? _firebaseAuth.currentUser ?? current;
      } on firebase_auth.FirebaseAuthException catch (e) {
        if (!_isAlreadyInUse(e)) rethrow;
        final result = e.credential != null
            ? await _firebaseAuth.signInWithCredential(e.credential!)
            : await _firebaseAuth.signInWithPopup(provider);
        _signInNotice = existingAccountNotice;
        return result.user!;
      }
    }
    final result = await _firebaseAuth.signInWithPopup(provider);
    return result.user!;
  }

  /// After a guest is linked, the top-level displayName can still be empty
  /// (the provider's name only lands in providerData). Copy it up so the
  /// profile doc and the app bar show the real name.
  Future<firebase_auth.User> _adoptProviderName(firebase_auth.User user) async {
    if (user.displayName != null && user.displayName!.trim().isNotEmpty) {
      return user;
    }
    final fromProvider = user.providerData
        .map((p) => p.displayName)
        .whereType<String>()
        .firstWhere((n) => n.trim().isNotEmpty, orElse: () => '');
    if (fromProvider.isEmpty) return user;
    try {
      await user.updateDisplayName(fromProvider.trim());
      await user.reload();
    } catch (_) {
      // Cosmetic; never fail a sign-in over it.
    }
    return _firebaseAuth.currentUser ?? user;
  }

  /// The account's email, falling back to the linked provider's when the
  /// top-level field has not been populated yet (fresh link).
  static String? _emailOf(firebase_auth.User user) {
    if (user.email != null && user.email!.isNotEmpty) return user.email;
    for (final p in user.providerData) {
      if (p.email != null && p.email!.isNotEmpty) return p.email;
    }
    return null;
  }

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
    if (_useWebPopup) {
      // Web: Firebase-hosted OAuth popup. No google_sign_in plugin involved,
      // so no web client id / GIS script configuration is needed beyond the
      // Google provider being enabled in the Firebase console.
      // A guest is linked (same uid) rather than signed in afresh.
      final provider = firebase_auth.GoogleAuthProvider()
        ..addScope('email')
        ..setCustomParameters({'prompt': 'select_account'});
      final user =
          await _adoptProviderName(await _linkOrSignInWithPopup(provider));
      _cachedAvatarEmoji = null;
      await _upsertUserDoc(user);
      return user.uid;
    }

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

    // 3. Exchange the Google credential for a Firebase session, linking it
    //    to the current guest, if there is one, so their uid survives.
    final user = await _adoptProviderName(await _linkOrSignIn(credential));
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

    final appleCredential = await _requestAppleCredential(hashedNonce);

    final oauthCredential =
        firebase_auth.OAuthProvider('apple.com').credential(
      idToken: appleCredential.identityToken,
      rawNonce: rawNonce,
      accessToken: appleCredential.authorizationCode,
    );

    // Link to the current guest when there is one (keeps the uid).
    final user = await _linkOrSignIn(oauthCredential);

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
        if (data.containsKey('email')) {
          await _migrateEmailToPrivate(user, data['email']);
        }
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

  /// A session restored from disk never goes through a sign-in method, so the
  /// public-email cleanup also runs the first time the profile is read.
  Future<void> _migrateEmailToPrivate(
      firebase_auth.User user, Object? publicEmail) async {
    try {
      final email = _emailOf(user) ??
          (publicEmail is String && publicEmail.isNotEmpty ? publicEmail : null);
      final batch = _firestore.batch();
      if (email != null) {
        batch.set(_privateProfile(user.uid), {
          'email': email,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      batch.update(_publicUserDoc(user.uid), {'email': FieldValue.delete()});
      await batch.commit();
    } catch (_) {
      // Retried on the next read; never block loading the profile.
    }
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
    // Never on the public doc: see [_privateProfile].
    update['email'] = FieldValue.delete();
    final batch = _firestore.batch();
    batch.set(_publicUserDoc(user.uid), update, SetOptions(merge: true));
    final email = _emailOf(user);
    if (email != null) {
      batch.set(_privateProfile(user.uid), {
        'email': email,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
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
    final batch = _firestore.batch();
    batch.set(_publicUserDoc(linkedUser.uid), {
      'displayName': displayName.trim().isNotEmpty
          ? displayName.trim()
          : email.split('@')[0],
      'email': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.set(_privateProfile(linkedUser.uid), {
      'email': email,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await batch.commit();
    return linkedUser.uid;
  }

  /// Create/merge the users/{uid} profile doc after a social sign-in so the
  /// display name is persisted (mirrors email/password sign-up). The email
  /// goes to the owner-only users/{uid}/private/profile doc, and any email an
  /// older build left on the public doc is removed in the same batch: this is
  /// the "migrate on next sign-in" step.
  Future<void> _upsertUserDoc(firebase_auth.User user) async {
    try {
      final email = _emailOf(user);
      final fallbackName =
          email != null && email.contains('@') ? email.split('@')[0] : 'Player';
      final batch = _firestore.batch();
      batch.set(_publicUserDoc(user.uid), {
        'displayName': (user.displayName != null &&
                user.displayName!.trim().isNotEmpty)
            ? user.displayName!.trim()
            : fallbackName,
        'email': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (email != null) {
        batch.set(_privateProfile(user.uid), {
          'email': email,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await batch.commit();
    } catch (_) {
      // Non-fatal: the auth session is valid even if the profile write fails.
    }
  }

  @override
  List<String> getCurrentUserProviderIds() {
    final user = _firebaseAuth.currentUser;
    if (user == null) return const [];
    return user.providerData.map((p) => p.providerId).toList();
  }

  @override
  Future<void> deleteAccount() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      throw Exception('No signed-in user to delete');
    }
    // Everything else the account left behind (feed posts and their grades,
    // grades it gave, Storage clips, push subscriptions, game memberships)
    // is removed server-side by the `deleteUserData` auth onDelete Cloud
    // Function (functions/src/account_deletion.js), which fires once step 2
    // below succeeds.
    //
    // 1. Delete the Firestore data this user owns WHILE still authenticated
    //    — security rules only allow a user to write their own users/{uid}
    //    doc and its friends subcollection. Deleting the doc removes the
    //    fcmTokens map too (it's a field on the doc, not a separate
    //    collection). The reciprocal edge in another user's own friends
    //    subcollection is theirs to keep or remove (self-write only, see
    //    firestore.rules) — it is simply left pointing at a uid that no
    //    longer resolves to an account.
    await _deleteOwnedFirestoreData(user.uid);
    // 2. Delete the Firebase Auth account itself. This throws
    //    FirebaseAuthException(code: 'requires-recent-login') if the
    //    session is stale; the caller should call reauthenticate() then
    //    retry deleteAccount() (the Firestore delete above is idempotent —
    //    a second run against already-deleted docs is a harmless no-op).
    await user.delete();
    _cachedAvatarEmoji = null;
  }

  Future<void> _deleteOwnedFirestoreData(String uid) async {
    final userDoc = _publicUserDoc(uid);
    final friends = await userDoc.collection('friends').get();
    final batch = _firestore.batch();
    for (final doc in friends.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(_privateProfile(uid));
    batch.delete(userDoc);
    await batch.commit();
  }

  @override
  Future<void> reauthenticate({String? password}) async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      throw Exception('No signed-in user to re-authenticate');
    }
    final providerIds = getCurrentUserProviderIds();

    if (providerIds.contains('password')) {
      if (password == null || password.isEmpty) {
        throw Exception('Password is required to confirm this change');
      }
      final email = user.email;
      if (email == null) {
        throw Exception('No email on this account to re-authenticate with');
      }
      final credential = firebase_auth.EmailAuthProvider.credential(
        email: email,
        password: password,
      );
      await user.reauthenticateWithCredential(credential);
      return;
    }

    if (providerIds.contains('google.com')) {
      if (_useWebPopup) {
        final provider = firebase_auth.GoogleAuthProvider()
          ..setCustomParameters({'prompt': 'select_account'});
        await user.reauthenticateWithPopup(provider);
      } else {
        final googleUser = await _googleSignIn.signIn();
        if (googleUser == null) {
          throw Exception('Google sign-in was cancelled');
        }
        final googleAuth = await googleUser.authentication;
        final credential = firebase_auth.GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        await user.reauthenticateWithCredential(credential);
      }
      return;
    }

    if (providerIds.contains('apple.com')) {
      final rawNonce = _generateNonce();
      final hashedNonce = _sha256(rawNonce);
      final appleCredential = await _requestAppleCredential(hashedNonce);
      final oauthCredential = firebase_auth.OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        rawNonce: rawNonce,
        accessToken: appleCredential.authorizationCode,
      );
      await user.reauthenticateWithCredential(oauthCredential);
      return;
    }

    // No known provider (e.g. an anonymous/guest session) — nothing to
    // re-authenticate with automatically.
    throw Exception('Please sign out and sign back in, then try again.');
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
