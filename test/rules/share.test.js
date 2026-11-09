// Firestore security rules tests for WP-09 sharing: the `shareable` flag on
// feed_posts (owner-only, bool-only, either way) and the create-only
// share_attributions/{uid} record. Each attack has a matching allowed write.
// Run via test/rules/run.sh (firebase emulators:exec).
const { assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const {
  doc,
  getDoc,
  setDoc,
  updateDoc,
  deleteDoc,
  serverTimestamp,
  Timestamp,
} = require('firebase/firestore');
const { makeTestEnv } = require('./helpers');

function post(overrides = {}) {
  return {
    userId: 'author',
    gameId: 'g1',
    taskId: 'task-in-a-friend-game',
    mediaType: 'text',
    text: 'An attempt',
    photoData: null,
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

describe('firestore.rules — WP-09 sharing', function () {
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

  const as = (uid) => testEnv.authenticatedContext(uid).firestore();

  async function seed(path, data) {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), path), data);
    });
  }

  const seedPost = (id, data = {}) =>
    seed(`feed_posts/${id}`, { ...post(), createdAt: Timestamp.now(), ...data });

  // ---- shareable on create ----

  it('ALLOWED: creating a post with shareable true or false', async () => {
    const db = as('author');
    await assertSucceeds(setDoc(doc(db, 'feed_posts/a'), post({ shareable: true })));
    await assertSucceeds(setDoc(doc(db, 'feed_posts/b'), post({ shareable: false })));
    await assertSucceeds(setDoc(doc(db, 'feed_posts/c'), post()));
  });

  it('DENIED: creating a post with a non-bool shareable', async () => {
    await assertFails(setDoc(doc(as('author'), 'feed_posts/a'), post({ shareable: 'yes' })));
    await assertFails(setDoc(doc(as('author'), 'feed_posts/b'), post({ shareable: 1 })));
  });

  // ---- shareable on update ----

  it('ALLOWED: the owner flipping shareable on, then off again', async () => {
    await seedPost('p1');
    const db = as('author');
    await assertSucceeds(updateDoc(doc(db, 'feed_posts/p1'), { shareable: true }));
    await assertSucceeds(updateDoc(doc(db, 'feed_posts/p1'), { shareable: false }));
  });

  it('ALLOWED: the owner sharing a legacy post that has no shareable field', async () => {
    await seedPost('p1');
    await assertSucceeds(updateDoc(doc(as('author'), 'feed_posts/p1'), { shareable: true }));
  });

  it('DENIED: anyone else making a private post public (or a public one private)', async () => {
    await seedPost('p1', { shareable: false });
    await seedPost('p2', { shareable: true });
    const db = as('mallory');
    await assertFails(updateDoc(doc(db, 'feed_posts/p1'), { shareable: true }));
    await assertFails(updateDoc(doc(db, 'feed_posts/p2'), { shareable: false }));
  });

  it('DENIED: the owner setting a non-bool shareable', async () => {
    await seedPost('p1');
    await assertFails(updateDoc(doc(as('author'), 'feed_posts/p1'), { shareable: 'public' }));
  });

  it('DENIED: smuggling a counter change in with the shareable flip', async () => {
    await seedPost('p1');
    await assertFails(
      updateDoc(doc(as('author'), 'feed_posts/p1'), { shareable: true, gradeCount: 3, gradeSum: 15 })
    );
    await assertFails(
      updateDoc(doc(as('author'), 'feed_posts/p1'), {
        shareable: true,
        playbackUrl: 'https://evil.example/x.mp4',
      })
    );
  });

  // ---- reading a private post by id ----

  it('ALLOWED: a private post is readable by its author and its game\'s players', async () => {
    await seed('games/g1', { playerIds: ['author', 'friend'], players: [] });
    await seedPost('p1', { shareable: false });
    await assertSucceeds(getDoc(doc(as('author'), 'feed_posts/p1')));
    await assertSucceeds(getDoc(doc(as('friend'), 'feed_posts/p1')));
  });

  it('DENIED: a private post read by id by anyone else', async () => {
    await seed('games/g1', { playerIds: ['author', 'friend'], players: [] });
    await seedPost('p1', { shareable: false });
    await seedPost('p2', { shareable: false, gameId: 'no-such-game' });
    await assertFails(getDoc(doc(as('mallory'), 'feed_posts/p1')));
    await assertFails(getDoc(doc(as('mallory'), 'feed_posts/p2')));
    await assertFails(getDoc(doc(testEnv.unauthenticatedContext().firestore(), 'feed_posts/p1')));
  });

  it('ALLOWED: public and unset (Arena) posts stay readable by any signed-in user', async () => {
    await seedPost('p1', { shareable: true });
    await seedPost('p2');
    await assertSucceeds(getDoc(doc(as('mallory'), 'feed_posts/p1')));
    await assertSucceeds(getDoc(doc(as('mallory'), 'feed_posts/p2')));
  });

  // ---- share_attributions ----

  function attribution(overrides = {}) {
    return {
      fromPostId: 'challenger',
      postId: 'mine',
      taskId: 'starter-09-v2',
      createdAt: serverTimestamp(),
      ...overrides,
    };
  }

  it('ALLOWED: a new player recording the challenge their first post answered', async () => {
    await seedPost('challenger', { userId: 'friend' });
    await seedPost('mine', { userId: 'newbie' });
    await assertSucceeds(setDoc(doc(as('newbie'), 'share_attributions/newbie'), attribution()));
  });

  it('DENIED: a second attribution (create-only), edits, deletes and reads', async () => {
    await seedPost('challenger', { userId: 'friend' });
    await seedPost('mine', { userId: 'newbie' });
    const db = as('newbie');
    await assertSucceeds(setDoc(doc(db, 'share_attributions/newbie'), attribution()));
    await assertFails(setDoc(doc(db, 'share_attributions/newbie'), attribution({ fromPostId: 'other' })));
    await assertFails(updateDoc(doc(db, 'share_attributions/newbie'), { fromPostId: 'mine' }));
    await assertFails(deleteDoc(doc(db, 'share_attributions/newbie')));
    await assertFails(getDoc(doc(db, 'share_attributions/newbie')));
  });

  it('DENIED: writing an attribution as someone else, or for someone else\'s post', async () => {
    await seedPost('challenger', { userId: 'friend' });
    await seedPost('mine', { userId: 'newbie' });
    await seedPost('theirs', { userId: 'friend' });
    await assertFails(setDoc(doc(as('mallory'), 'share_attributions/newbie'), attribution()));
    await assertFails(
      setDoc(doc(as('newbie'), 'share_attributions/newbie'), attribution({ postId: 'theirs' }))
    );
  });

  it('DENIED: pointing at a challenge post that does not exist, extra keys, or a client clock', async () => {
    await seedPost('mine', { userId: 'newbie' });
    await seedPost('challenger', { userId: 'friend' });
    const db = as('newbie');
    await assertFails(
      setDoc(doc(db, 'share_attributions/newbie'), attribution({ fromPostId: 'ghost' }))
    );
    await assertFails(
      setDoc(doc(db, 'share_attributions/newbie'), attribution({ reward: 1000 }))
    );
    await assertFails(
      setDoc(doc(db, 'share_attributions/newbie'), attribution({ createdAt: Timestamp.now() }))
    );
  });
});
