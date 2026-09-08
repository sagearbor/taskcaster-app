// Device-driven proof that FirebaseAuthDataSource.deleteAccount() really
// removes a user's owned Firestore data (the users/{uid} profile doc —
// including the fcmTokens map it carries as a field — and the
// users/{uid}/friends subcollection) and the Firebase Auth account itself.
//
// Runs against the Firebase Local Emulator Suite (Firestore + Auth), not
// production Firebase. Start the emulators first:
//
//   firebase emulators:start --only auth,firestore --project taskmaster-app-3d480
//
// then, with an Android device/emulator attached:
//
//   flutter test integration_test/delete_account_emulator_test.dart -d <device-id>
//
// Why a device test and not `flutter test`: the real firebase_auth /
// cloud_firestore plugins need a live platform (Android/iOS/web) — the
// Dart-VM "flutter tester" target used by plain `flutter test` has no
// platform-channel implementation for them.
//
// Why raw HTTP for the "after" reads: firestore.rules require a signed-in
// user for every read, and the whole point of this test is that no such
// user exists anymore once deleteAccount() has run. The emulator's REST API
// accepts `Authorization: Bearer owner` to bypass security rules for
// exactly this kind of test/admin check; production Firestore does not
// honor that token, so this bypass has no effect outside the emulator.
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:taskcaster_app/features/auth/data/datasources/firebase_auth_data_source.dart';
import 'package:taskcaster_app/firebase_options.dart';

/// 10.0.2.2 is the Android emulator's alias for the host machine's
/// loopback interface, i.e. where `firebase emulators:start` is listening.
const String _emulatorHost = '10.0.2.2';
const int _firestorePort = 8080;
const int _authPort = 9099;
const String _projectId = 'taskmaster-app-3d480';

Future<Map<String, dynamic>?> _emulatorGetDoc(String path) async {
  final uri = Uri.parse(
    'http://$_emulatorHost:$_firestorePort/v1/projects/$_projectId/'
    'databases/(default)/documents/$path',
  );
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    request.headers.set('Authorization', 'Bearer owner');
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw Exception(
          'Emulator GET $path -> ${response.statusCode}: $body');
    }
    return jsonDecode(body) as Map<String, dynamic>;
  } finally {
    client.close();
  }
}

Future<List<dynamic>> _emulatorListDocs(String collectionPath) async {
  final uri = Uri.parse(
    'http://$_emulatorHost:$_firestorePort/v1/projects/$_projectId/'
    'databases/(default)/documents/$collectionPath',
  );
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    request.headers.set('Authorization', 'Bearer owner');
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw Exception(
          'Emulator LIST $collectionPath -> ${response.statusCode}: $body');
    }
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    return (decoded['documents'] as List<dynamic>?) ?? const [];
  } finally {
    client.close();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    firebase_auth.FirebaseAuth.instance
        .useAuthEmulator(_emulatorHost, _authPort);
    FirebaseFirestore.instance
        .useFirestoreEmulator(_emulatorHost, _firestorePort);
  });

  testWidgets(
    'deleteAccount removes the Firestore profile doc, its fcmTokens, the '
    'friends subcollection, and the Firebase Auth account',
    (tester) async {
      final firebaseAuth = firebase_auth.FirebaseAuth.instance;
      final firestore = FirebaseFirestore.instance;
      final dataSource = FirebaseAuthDataSource(
        firebaseAuth: firebaseAuth,
        firestore: firestore,
      );

      final stamp = DateTime.now().millisecondsSinceEpoch;
      final email = 'delete-me-$stamp@example.com';
      final uid =
          await dataSource.createUserWithEmailAndPassword(email, 'password123');

      // Seed exactly the kind of data the real app creates for a user:
      // the profile doc (fcmTokens lives on it as a field, per
      // NotificationService.registerToken) and one friend link in the
      // owned friends subcollection (per FirebaseFriendsRepository).
      await firestore.collection('users').doc(uid).set({
        'displayName': 'Delete Me',
        'email': email,
        'fcmTokens': {'test-device-token': FieldValue.serverTimestamp()},
      });
      await firestore
          .collection('users')
          .doc(uid)
          .collection('friends')
          .doc('some-friend-uid')
          .set({
        'displayName': 'A Friend',
        'lastPlayedAt': DateTime.now().toIso8601String(),
      });

      // Sanity check: the seeded data is really there before deletion, so
      // the "after" assertions below prove something actually changed.
      final before = await _emulatorGetDoc('users/$uid');
      expect(before, isNotNull, reason: 'seeded users/{uid} doc missing');
      final friendsBefore = await _emulatorListDocs('users/$uid/friends');
      expect(friendsBefore, hasLength(1),
          reason: 'seeded friends subcollection missing');

      // The method under test — same code path Settings -> Delete Account
      // drives via AuthBloc -> AuthRepositoryImpl -> this data source.
      await dataSource.deleteAccount();

      // 1. The Firestore profile doc — and the fcmTokens map that lived on
      //    it — is gone.
      final after = await _emulatorGetDoc('users/$uid');
      expect(after, isNull,
          reason: 'users/{uid} doc (with fcmTokens) should be deleted');

      // 2. The friends subcollection is gone.
      final friendsAfter = await _emulatorListDocs('users/$uid/friends');
      expect(friendsAfter, isEmpty,
          reason: 'users/{uid}/friends should be empty');

      // 3. The client no longer has a signed-in user...
      expect(firebaseAuth.currentUser, isNull);

      // 4. ...and the account is truly gone server-side, not just locally
      //    signed out: signing in again with the same credentials fails.
      await expectLater(
        firebaseAuth.signInWithEmailAndPassword(
            email: email, password: 'password123'),
        throwsA(isA<firebase_auth.FirebaseAuthException>().having(
          (e) => e.code,
          'code',
          anyOf('user-not-found', 'invalid-credential', 'INVALID_LOGIN_CREDENTIALS'),
        )),
      );
    },
  );
}
