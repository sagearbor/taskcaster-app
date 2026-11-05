// Firestore security rules tests for the feed_posts video changes, plus a
// smoke test that the pre-existing photo-post create and grade paths still
// work. Run via test/rules/run.sh (firebase emulators:exec).
const { assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const {
  doc,
  setDoc,
  getDoc,
  updateDoc,
  deleteDoc,
  increment,
  arrayUnion,
  serverTimestamp,
  writeBatch,
} = require('firebase/firestore');
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
      createdAt: serverTimestamp(),
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
    // A grade is the grade doc AND the counter bump, in one commit.
    const batch = writeBatch(grader);
    batch.set(doc(grader, 'feed_posts/grade1/grades/u2'), { score: 4 });
    batch.update(doc(grader, 'feed_posts/grade1'), {
      gradeCount: increment(1),
      gradeSum: increment(4),
      graderIds: arrayUnion('u2'),
    });
    await assertSucceeds(batch.commit());
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

  // ---- New: tapBump with tapSeconds ----

  it('a non-owner update of {tapCount +1, tapSeconds.3 +1} is allowed', async () => {
    const owner = testEnv.authenticatedContext('u1').firestore();
    await setDoc(doc(owner, 'feed_posts/tapOk'), photoPost());
    const other = testEnv.authenticatedContext('u2').firestore();
    await assertSucceeds(
      updateDoc(doc(other, 'feed_posts/tapOk'), {
        tapCount: increment(1),
        'tapSeconds.3': increment(1),
        lastTapSecond: '3',
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

  it('the owner may edit the caption of their own post', async () => {
    const owner = testEnv.authenticatedContext('u1').firestore();
    await setDoc(doc(owner, 'feed_posts/ownRewrite'), photoPost());
    await assertSucceeds(
      updateDoc(doc(owner, 'feed_posts/ownRewrite'), { caption: 'new caption' })
    );
  });

  it('the owner may NOT swap the media of their own post', async () => {
    const owner = testEnv.authenticatedContext('u1').firestore();
    await setDoc(doc(owner, 'feed_posts/ownSwap'), photoPost());
    await assertFails(
      updateDoc(doc(owner, 'feed_posts/ownSwap'), { photoData: 'newphoto' })
    );
  });
});

describe('firestore.rules — montages/{montageId}', function () {
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

  function montage(overrides = {}) {
    return {
      gameId: 'game1',
      taskId: 'starter-01',
      finaleUrl: 'https://example.com/finale.mp4',
      momentsUrl: 'https://example.com/moments.mp4',
      createdAt: Date.now(),
      ...overrides,
    };
  }

  it('a signed-in user can read a montage', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'montages/game1_starter-01'), montage());
    });
    const db = testEnv.authenticatedContext('u1').firestore();
    await assertSucceeds(getDoc(doc(db, 'montages/game1_starter-01')));
  });

  it('an unauthenticated caller cannot read a montage', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'montages/game1_starter-01'), montage());
    });
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, 'montages/game1_starter-01')));
  });

  it('a signed-in user cannot create a montage', async () => {
    const db = testEnv.authenticatedContext('u1').firestore();
    await assertFails(setDoc(doc(db, 'montages/game1_starter-01'), montage()));
  });

  it('a signed-in user cannot update a montage', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'montages/game1_starter-01'), montage());
    });
    const db = testEnv.authenticatedContext('u1').firestore();
    await assertFails(
      updateDoc(doc(db, 'montages/game1_starter-01'), { finaleUrl: 'https://example.com/new.mp4' })
    );
  });

  it('a signed-in user cannot delete a montage', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'montages/game1_starter-01'), montage());
    });
    const db = testEnv.authenticatedContext('u1').firestore();
    await assertFails(deleteDoc(doc(db, 'montages/game1_starter-01')));
  });
});
