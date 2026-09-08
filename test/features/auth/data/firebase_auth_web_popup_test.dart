import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/features/auth/data/datasources/firebase_auth_data_source.dart';

/// Regression test for the live-web bug where "Continue with Google" always
/// failed: on the web the data source must sign in through Firebase's own
/// OAuth popup (no google_sign_in plugin involved) and still create the
/// users/{uid} profile document.
void main() {
  test('web branch signs in via signInWithPopup and upserts the user doc',
      () async {
    final auth = MockFirebaseAuth(
      mockUser: MockUser(
        uid: 'web-uid',
        email: 'web@example.com',
        displayName: 'Web Person',
      ),
    );
    final firestore = FakeFirebaseFirestore();
    final dataSource = FirebaseAuthDataSource(
      firebaseAuth: auth,
      firestore: firestore,
      useWebPopup: true,
    );

    final uid = await dataSource.signInWithGoogle();

    expect(uid, 'web-uid');
    expect(auth.currentUser?.uid, 'web-uid');
    final doc = await firestore.collection('users').doc('web-uid').get();
    expect(doc.exists, isTrue, reason: 'profile doc must be upserted');
    expect(doc.data()?['email'], 'web@example.com');
  });
}
