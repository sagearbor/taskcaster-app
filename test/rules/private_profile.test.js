// Firestore rules for users/{uid}/private/{doc}: the owner-only home of the
// email address, which used to sit on the world-readable users/{uid} doc.
// Run via test/rules/run.sh (firebase emulators:exec).
const { assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { doc, setDoc, getDoc, getDocs, collection, deleteDoc } = require('firebase/firestore');
const { makeTestEnv } = require('./helpers');

describe('firestore.rules — users/{uid}/private', function () {
  this.timeout(60000);
  let testEnv;

  before(async () => {
    testEnv = await makeTestEnv();
  });

  afterEach(async () => {
    await testEnv.clearFirestore();
  });

  after(async () => {
    await testEnv.cleanup();
  });

  // What the app writes on sign-in: public name, private email.
  async function seedAlice() {
    const alice = testEnv.authenticatedContext('alice', { email: 'alice@example.com' }).firestore();
    await assertSucceeds(setDoc(doc(alice, 'users/alice'), { displayName: 'Alice' }));
    await assertSucceeds(
      setDoc(doc(alice, 'users/alice/private/profile'), { email: 'alice@example.com' })
    );
  }

  it('the owner can write and read their private profile', async () => {
    await seedAlice();
    const alice = testEnv.authenticatedContext('alice').firestore();
    const snap = await assertSucceeds(getDoc(doc(alice, 'users/alice/private/profile')));
    if (snap.data().email !== 'alice@example.com') throw new Error('owner read wrong data');
    await assertSucceeds(deleteDoc(doc(alice, 'users/alice/private/profile')));
  });

  it('another user reads users/A with no email field, and is denied private/profile', async () => {
    await seedAlice();
    const bob = testEnv.authenticatedContext('bob').firestore();
    const pub = await assertSucceeds(getDoc(doc(bob, 'users/alice')));
    if ('email' in pub.data()) throw new Error('email leaked on the public doc');
    await assertFails(getDoc(doc(bob, 'users/alice/private/profile')));
  });

  it('an anonymous guest cannot read or list someone else\'s private docs', async () => {
    await seedAlice();
    const guest = testEnv
      .authenticatedContext('guest', { firebase: { sign_in_provider: 'anonymous' } })
      .firestore();
    await assertFails(getDoc(doc(guest, 'users/alice/private/profile')));
    await assertFails(getDocs(collection(guest, 'users/alice/private')));
  });

  it('another user cannot write or delete someone else\'s private profile', async () => {
    await seedAlice();
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertFails(
      setDoc(doc(bob, 'users/alice/private/profile'), { email: 'evil@example.com' })
    );
    await assertFails(deleteDoc(doc(bob, 'users/alice/private/profile')));
  });

  it('signed-out clients are denied', async () => {
    await seedAlice();
    const anon = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(anon, 'users/alice/private/profile')));
  });
});
