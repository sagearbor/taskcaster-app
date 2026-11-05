import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:taskcaster_app/features/auth/data/datasources/firebase_auth_data_source.dart';

class _Auth extends Mock implements fb.FirebaseAuth {}

class _User extends Mock implements fb.User {}

class _Cred extends Mock implements fb.UserCredential {}

class _Google extends Mock implements GoogleSignIn {}

class _GoogleAccount extends Mock implements GoogleSignInAccount {}

class _GoogleTokens extends Mock implements GoogleSignInAuthentication {}

/// A guest who taps "Continue with Google/Apple" must keep their uid (and so
/// their games and posts): the data source links the provider credential to
/// the anonymous user instead of calling signInWithCredential, which would
/// mint a new uid. When the provider identity already has an account, it
/// falls back to signing in to that account and leaves a notice for the UI.
void main() {
  setUpAll(() {
    registerFallbackValue(
        const fb.AuthCredential(providerId: 'x', signInMethod: 'x'));
    registerFallbackValue(fb.GoogleAuthProvider());
  });

  late _Auth auth;
  late FakeFirebaseFirestore firestore;
  late _Google google;

  _User user(String uid,
      {required bool anonymous, String? email, String? name}) {
    final u = _User();
    when(() => u.uid).thenReturn(uid);
    when(() => u.isAnonymous).thenReturn(anonymous);
    when(() => u.email).thenReturn(email);
    when(() => u.displayName).thenReturn(name);
    when(() => u.providerData).thenReturn(const []);
    return u;
  }

  _Cred cred(fb.User u) {
    final c = _Cred();
    when(() => c.user).thenReturn(u);
    return c;
  }

  void stubGooglePicker() {
    final account = _GoogleAccount();
    final tokens = _GoogleTokens();
    when(() => tokens.accessToken).thenReturn('access');
    when(() => tokens.idToken).thenReturn('id');
    when(() => account.authentication).thenAnswer((_) async => tokens);
    when(() => google.signIn()).thenAnswer((_) async => account);
  }

  FirebaseAuthDataSource source({bool web = false}) => FirebaseAuthDataSource(
        firebaseAuth: auth,
        firestore: firestore,
        googleSignIn: google,
        useWebPopup: web,
        appleCredentialRequest: (nonce) async =>
            const AuthorizationCredentialAppleID(
          userIdentifier: 'apple-user',
          givenName: null,
          familyName: null,
          authorizationCode: 'code',
          email: null,
          identityToken: 'apple-id-token',
          state: null,
        ),
      );

  setUp(() {
    auth = _Auth();
    firestore = FakeFirebaseFirestore();
    google = _Google();
  });

  group('signInWithGoogle (native)', () {
    test('a guest is LINKED, keeping the same uid', () async {
      stubGooglePicker();
      final guest = user('guest-1', anonymous: true);
      final linked = user('guest-1',
          anonymous: false, email: 'g@example.com', name: 'Gina');
      when(() => auth.currentUser).thenReturn(guest);
      when(() => guest.linkWithCredential(any()))
          .thenAnswer((_) async => cred(linked));

      final ds = source();
      final uid = await ds.signInWithGoogle();

      expect(uid, 'guest-1');
      verify(() => guest.linkWithCredential(any())).called(1);
      verifyNever(() => auth.signInWithCredential(any()));
      expect(ds.takeSignInNotice(), isNull);

      // Email goes to the owner-only private doc, never the public one.
      final public = await firestore.doc('users/guest-1').get();
      expect(public.data()?['displayName'], 'Gina');
      expect(public.data()!.containsKey('email'), isFalse);
      final private = await firestore.doc('users/guest-1/private/profile').get();
      expect(private.data()?['email'], 'g@example.com');
    });

    test(
        'credential-already-in-use signs in to the existing account '
        'and leaves a one-shot notice', () async {
      stubGooglePicker();
      final guest = user('guest-1', anonymous: true);
      final existing = user('real-9',
          anonymous: false, email: 'g@example.com', name: 'Gina');
      const fresh =
          fb.AuthCredential(providerId: 'google.com', signInMethod: 'google.com');
      when(() => auth.currentUser).thenReturn(guest);
      when(() => guest.linkWithCredential(any())).thenThrow(
          fb.FirebaseAuthException(
              code: 'credential-already-in-use', credential: fresh));
      when(() => auth.signInWithCredential(fresh))
          .thenAnswer((_) async => cred(existing));

      final ds = source();
      final uid = await ds.signInWithGoogle();

      expect(uid, 'real-9');
      verify(() => auth.signInWithCredential(fresh)).called(1);
      expect(ds.takeSignInNotice(), 'Signed in to your existing account');
      expect(ds.takeSignInNotice(), isNull, reason: 'consumed on read');
    });

    test('any other link failure is rethrown, not swallowed', () async {
      stubGooglePicker();
      final guest = user('guest-1', anonymous: true);
      when(() => auth.currentUser).thenReturn(guest);
      when(() => guest.linkWithCredential(any())).thenThrow(
          fb.FirebaseAuthException(code: 'network-request-failed'));

      await expectLater(source().signInWithGoogle(),
          throwsA(isA<fb.FirebaseAuthException>()));
      verifyNever(() => auth.signInWithCredential(any()));
    });

    test('with no guest session it signs in normally', () async {
      stubGooglePicker();
      final signedIn =
          user('new-3', anonymous: false, email: 'n@example.com', name: 'N');
      when(() => auth.currentUser).thenReturn(null);
      when(() => auth.signInWithCredential(any()))
          .thenAnswer((_) async => cred(signedIn));

      expect(await source().signInWithGoogle(), 'new-3');
      verify(() => auth.signInWithCredential(any())).called(1);
    });
  });

  test('signInWithApple links a guest too', () async {
    final guest = user('guest-2', anonymous: true);
    final linked = user('guest-2',
        anonymous: false, email: 'a@privaterelay.appleid.com', name: 'Al');
    // After the link, currentUser is the linked account.
    var current = guest;
    when(() => auth.currentUser).thenAnswer((_) => current);
    when(() => guest.linkWithCredential(any())).thenAnswer((_) async {
      current = linked;
      return cred(linked);
    });

    final uid = await source().signInWithApple();

    expect(uid, 'guest-2');
    verify(() => guest.linkWithCredential(any())).called(1);
    verifyNever(() => auth.signInWithCredential(any()));
  });

  test('web: a guest is linked through linkWithPopup', () async {
    final guest = user('guest-w', anonymous: true);
    final linked =
        user('guest-w', anonymous: false, email: 'w@example.com', name: 'W');
    when(() => auth.currentUser).thenReturn(guest);
    when(() => guest.linkWithPopup(any()))
        .thenAnswer((_) async => cred(linked));

    expect(await source(web: true).signInWithGoogle(), 'guest-w');
    verify(() => guest.linkWithPopup(any())).called(1);
    verifyNever(() => auth.signInWithPopup(any()));
  });

  group('private email', () {
    test('a legacy public email moves to private/profile on profile read',
        () async {
      final u = user('old-1', anonymous: false, email: 'o@example.com');
      when(() => auth.currentUser).thenReturn(u);
      await firestore
          .doc('users/old-1')
          .set({'displayName': 'Old', 'email': 'o@example.com'});

      await source().getCurrentUserProfile();

      final public = await firestore.doc('users/old-1').get();
      expect(public.data()!.containsKey('email'), isFalse);
      expect(public.data()?['displayName'], 'Old');
      final private = await firestore.doc('users/old-1/private/profile').get();
      expect(private.data()?['email'], 'o@example.com');
    });

    test('updateProfile never writes email to the public doc', () async {
      final u = user('p-1', anonymous: false, email: 'p@example.com');
      when(() => auth.currentUser).thenReturn(u);
      when(() => u.updateDisplayName(any())).thenAnswer((_) async {});

      await source().updateProfile(displayName: 'Pat');

      final public = await firestore.doc('users/p-1').get();
      expect(public.data()?['displayName'], 'Pat');
      expect(public.data()!.containsKey('email'), isFalse);
      final private = await firestore.doc('users/p-1/private/profile').get();
      expect(private.data()?['email'], 'p@example.com');
    });

    test('deleteAccount removes the private profile as well', () async {
      final u = user('d-1', anonymous: false, email: 'd@example.com');
      when(() => auth.currentUser).thenReturn(u);
      when(() => u.delete()).thenAnswer((_) async {});
      await firestore.doc('users/d-1').set({'displayName': 'D'});
      await firestore
          .doc('users/d-1/private/profile')
          .set({'email': 'd@example.com'});
      await firestore.doc('users/d-1/friends/f1').set({'uid': 'f1'});

      await source().deleteAccount();

      expect((await firestore.doc('users/d-1').get()).exists, isFalse);
      expect((await firestore.doc('users/d-1/private/profile').get()).exists,
          isFalse);
      expect((await firestore.doc('users/d-1/friends/f1').get()).exists,
          isFalse);
      verify(() => u.delete()).called(1);
    });
  });
}
