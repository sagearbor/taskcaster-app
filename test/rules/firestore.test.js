// Firestore security rules tests for the feed_posts video changes, plus a
// smoke test that the pre-existing photo-post create and grade paths still
// work. Run via test/rules/run.sh (firebase emulators:exec).
const { assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { doc, setDoc, updateDoc, increment } = require('firebase/firestore');
const { makeTestEnv } = require('./helpers');

describe('firestore.rules — feed_posts (video)', function () {
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

  function photoPost(overrides = {}) {
    return {
      userId: 'u1',
      mediaType: 'photo',
      photoData: 'abc123',
      videoStoragePath: null,
      isHouse: false,
      gradeCount: 0,
      gradeSum: 0,
      graderIds: [],
      boosted: false,
      tapCount: 0,
      tapSeconds: {},
      ...overrides,
    };
  }

  // ---- Smoke tests: pre-existing paths must still work ----

  it('SMOKE: owner can create a photo post (pre-existing path)', async () => {
    const db = testEnv.authenticatedContext('u1').firestore();
    await assertSucceeds(setDoc(doc(db, 'feed_posts/photo1'), photoPost()));
  });

  it('SMOKE: a signed-in non-owner can grade a post (pre-existing path)', async () => {
    const owner = testEnv.authenticatedContext('u1').firestore();
    await assertSucceeds(setDoc(doc(owner, 'feed_posts/grade1'), photoPost()));
    const grader = testEnv.authenticatedContext('u2').firestore();
    await assertSucceeds(
      setDoc(doc(grader, 'feed_posts/grade1/grades/u2'), { score: 4 })
    );
  });

  // ---- New: video post create ----

  it('a video post create by its owner, path under their own uid, is allowed', async () => {
    const db = testEnv.authenticatedContext('u1').firestore();
    await assertSucceeds(
      setDoc(
        doc(db, 'feed_posts/vidOwn'),
        photoPost({
          mediaType: 'video',
          photoData: null,
          videoStoragePath: 'submissions/u1/20260912/0',
        })
      )
    );
  });

  it('a video post claiming another uid\'s clip (submissions/u2/...) is denied', async () => {
    const db = testEnv.authenticatedContext('u1').firestore();
    await assertFails(
      setDoc(
        doc(db, 'feed_posts/vidOther'),
        photoPost({
          mediaType: 'video',
          photoData: null,
          videoStoragePath: 'submissions/u2/20260912/0',
        })
      )
    );
  });

  it('a house entry carrying a videoStoragePath is denied', async () => {
    const db = testEnv.authenticatedContext('u3').firestore();
    await assertFails(
      setDoc(
        doc(db, 'feed_posts/houseVid'),
        photoPost({
          userId: 'house',
          isHouse: true,
          mediaType: 'video',
          photoData: null,
          videoStoragePath: 'submissions/u3/20260912/0',
        })
      )
    );
  });

  // ---- New: tapBump with tapSeconds ----

  it('a non-owner update of {tapCount +1, tapSeconds.3 +1} is allowed', async () => {
    const owner = testEnv.authenticatedContext('u1').firestore();
    await setDoc(doc(owner, 'feed_posts/tapOk'), photoPost());
    const other = testEnv.authenticatedContext('u2').firestore();
    await assertSucceeds(
      updateDoc(doc(other, 'feed_posts/tapOk'), {
        tapCount: increment(1),
        'tapSeconds.3': increment(1),
      })
    );
  });

  it('an update touching only tapSeconds (no tapCount change) is denied', async () => {
    const owner = testEnv.authenticatedContext('u1').firestore();
    await setDoc(doc(owner, 'feed_posts/tapSecondsOnly'), photoPost());
    const other = testEnv.authenticatedContext('u2').firestore();
    await assertFails(
      updateDoc(doc(other, 'feed_posts/tapSecondsOnly'), {
        'tapSeconds.3': increment(1),
      })
    );
  });

  it('a tapCount +51 jump is denied', async () => {
    const owner = testEnv.authenticatedContext('u1').firestore();
    await setDoc(doc(owner, 'feed_posts/tapTooBig'), photoPost());
    const other = testEnv.authenticatedContext('u2').firestore();
    await assertFails(
      updateDoc(doc(other, 'feed_posts/tapTooBig'), {
        tapCount: increment(51),
      })
    );
  });

  it('the owner may still rewrite their own post', async () => {
    const owner = testEnv.authenticatedContext('u1').firestore();
    await setDoc(doc(owner, 'feed_posts/ownRewrite'), photoPost());
    await assertSucceeds(
      updateDoc(doc(owner, 'feed_posts/ownRewrite'), { photoData: 'newphoto' })
    );
  });
});
