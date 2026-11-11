// Firestore rules for Arena moderation (App Store guideline 1.2):
//   reports/{postId}_{uid}  create-only, as yourself, fixed keys + reasons;
//   users/{uid}.blockedUids  owner-only, a list;
//   feed_posts.hidden        server-owned, and a hidden post is private.
// Run via test/rules/run.sh (firebase emulators:exec).
const { assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const {
  doc,
  getDoc,
  getDocs,
  collection,
  setDoc,
  updateDoc,
  deleteDoc,
  arrayUnion,
  arrayRemove,
  serverTimestamp,
  Timestamp,
} = require('firebase/firestore');
const { makeTestEnv } = require('./helpers');

describe('firestore.rules — Arena moderation', function () {
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

  async function seedPost(id = 'p1', overrides = {}) {
    await seed(`feed_posts/${id}`, {
      userId: 'author',
      gameId: '',
      taskId: 'starter-01-v2',
      mediaType: 'text',
      text: 'An attempt',
      isHouse: false,
      gradeCount: 0,
      gradeSum: 0,
      graderIds: [],
      boosted: false,
      tapCount: 0,
      createdAt: Timestamp.now(),
      ...overrides,
    });
  }

  function report(overrides = {}) {
    return {
      postId: 'p1',
      authorId: 'author',
      reporterId: 'bob',
      reason: 'spam',
      createdAt: serverTimestamp(),
      ...overrides,
    };
  }

  describe('reports', () => {
    it('a signed-in player can report someone else\'s post', async () => {
      await seedPost();
      await assertSucceeds(setDoc(doc(as('bob'), 'reports/p1_bob'), report()));
    });

    it('accepts each of the four reasons', async () => {
      await seedPost();
      for (const [i, reason] of ['inappropriate', 'spam', 'harassment', 'other'].entries()) {
        const uid = `r${i}`;
        await assertSucceeds(
          setDoc(doc(as(uid), `reports/p1_${uid}`), report({ reporterId: uid, reason }))
        );
      }
    });

    it('an anonymous guest can report too', async () => {
      await seedPost();
      const guest = testEnv
        .authenticatedContext('guest', { firebase: { sign_in_provider: 'anonymous' } })
        .firestore();
      await assertSucceeds(
        setDoc(doc(guest, 'reports/p1_guest'), report({ reporterId: 'guest' }))
      );
    });

    it('a house post can be reported', async () => {
      await seedPost('house-starter-01', { userId: 'house', isHouse: true });
      await assertSucceeds(
        setDoc(
          doc(as('bob'), 'reports/house-starter-01_bob'),
          report({ postId: 'house-starter-01', authorId: 'house' })
        )
      );
    });

    it('signed-out clients cannot report', async () => {
      await seedPost();
      const anon = testEnv.unauthenticatedContext().firestore();
      await assertFails(setDoc(doc(anon, 'reports/p1_bob'), report()));
    });

    it('cannot report as someone else', async () => {
      await seedPost();
      await assertFails(setDoc(doc(as('mallory'), 'reports/p1_bob'), report()));
      await assertFails(
        setDoc(doc(as('mallory'), 'reports/p1_mallory'), report({ reporterId: 'bob' }))
      );
    });

    it('the doc id must be {postId}_{reporterUid}', async () => {
      await seedPost();
      await assertFails(setDoc(doc(as('bob'), 'reports/anything'), report()));
      await assertFails(setDoc(doc(as('bob'), 'reports/p2_bob'), report()));
    });

    it('rejects a reason outside the four', async () => {
      await seedPost();
      await assertFails(setDoc(doc(as('bob'), 'reports/p1_bob'), report({ reason: 'meh' })));
      await assertFails(setDoc(doc(as('bob'), 'reports/p1_bob'), report({ reason: 'Spam' })));
      await assertFails(setDoc(doc(as('bob'), 'reports/p1_bob'), report({ reason: 1 })));
    });

    it('rejects extra or missing keys', async () => {
      await seedPost();
      await assertFails(
        setDoc(doc(as('bob'), 'reports/p1_bob'), report({ note: 'free text' }))
      );
      const { authorId, ...noAuthor } = report();
      await assertFails(setDoc(doc(as('bob'), 'reports/p1_bob'), noAuthor));
    });

    it('createdAt must be the server clock', async () => {
      await seedPost();
      await assertFails(
        setDoc(
          doc(as('bob'), 'reports/p1_bob'),
          report({ createdAt: Timestamp.fromDate(new Date('2030-01-01')) })
        )
      );
    });

    it('the post must exist and authorId must be its real author', async () => {
      await assertFails(setDoc(doc(as('bob'), 'reports/p1_bob'), report()));
      await seedPost();
      await assertFails(
        setDoc(doc(as('bob'), 'reports/p1_bob'), report({ authorId: 'someone-else' }))
      );
    });

    it('cannot report your own post', async () => {
      await seedPost();
      await assertFails(
        setDoc(
          doc(as('author'), 'reports/p1_author'),
          report({ reporterId: 'author', authorId: 'author' })
        )
      );
    });

    it('the same player cannot report the same post twice', async () => {
      await seedPost();
      await assertSucceeds(setDoc(doc(as('bob'), 'reports/p1_bob'), report()));
      await assertFails(
        setDoc(doc(as('bob'), 'reports/p1_bob'), report({ reason: 'harassment' }))
      );
    });

    it('nobody can read, update or delete a report — not even its reporter', async () => {
      await seedPost();
      await assertSucceeds(setDoc(doc(as('bob'), 'reports/p1_bob'), report()));
      for (const uid of ['bob', 'author', 'stranger']) {
        await assertFails(getDoc(doc(as(uid), 'reports/p1_bob')));
        await assertFails(getDocs(collection(as(uid), 'reports')));
      }
      await assertFails(updateDoc(doc(as('bob'), 'reports/p1_bob'), { reason: 'other' }));
      await assertFails(deleteDoc(doc(as('bob'), 'reports/p1_bob')));
    });
  });

  describe('users/{uid}.blockedUids', () => {
    it('the owner can create, add to and remove from their block list', async () => {
      const alice = as('alice');
      await assertSucceeds(
        setDoc(doc(alice, 'users/alice'), { blockedUids: arrayUnion('troll') }, { merge: true })
      );
      await assertSucceeds(
        updateDoc(doc(alice, 'users/alice'), { blockedUids: arrayUnion('house:Greg') })
      );
      await assertSucceeds(
        updateDoc(doc(alice, 'users/alice'), { blockedUids: arrayRemove('troll') })
      );
      const snap = await getDoc(doc(alice, 'users/alice'));
      if (JSON.stringify(snap.data().blockedUids) !== '["house:Greg"]') {
        throw new Error(`unexpected list ${JSON.stringify(snap.data().blockedUids)}`);
      }
    });

    it('the owner can add a block to an existing profile', async () => {
      await seed('users/alice', { displayName: 'Alice' });
      await assertSucceeds(
        setDoc(doc(as('alice'), 'users/alice'), { blockedUids: arrayUnion('troll') }, { merge: true })
      );
    });

    it('nobody else can write someone\'s block list', async () => {
      await seed('users/alice', { displayName: 'Alice', blockedUids: ['troll'] });
      await assertFails(
        updateDoc(doc(as('troll'), 'users/alice'), { blockedUids: arrayRemove('troll') })
      );
      await assertFails(
        setDoc(doc(as('troll'), 'users/alice'), { blockedUids: [] }, { merge: true })
      );
      const anon = testEnv.unauthenticatedContext().firestore();
      await assertFails(updateDoc(doc(anon, 'users/alice'), { blockedUids: [] }));
    });

    it('must be a list, and a bounded one', async () => {
      await seed('users/alice', { displayName: 'Alice' });
      await assertFails(updateDoc(doc(as('alice'), 'users/alice'), { blockedUids: 'troll' }));
      await assertFails(
        setDoc(doc(as('bob'), 'users/bob'), { blockedUids: { troll: true } })
      );
      const tooMany = Array.from({ length: 501 }, (_, i) => `u${i}`);
      await assertFails(updateDoc(doc(as('alice'), 'users/alice'), { blockedUids: tooMany }));
    });

    it('the plan fields stay server-owned alongside a block write', async () => {
      await seed('users/alice', { displayName: 'Alice', plan: 'free' });
      await assertFails(
        updateDoc(doc(as('alice'), 'users/alice'), {
          blockedUids: arrayUnion('troll'),
          plan: 'pro',
        })
      );
    });
  });

  describe('feed_posts.hidden', () => {
    it('the author cannot clear (or set) hidden', async () => {
      await seedPost('p1', { hidden: true });
      await assertFails(updateDoc(doc(as('author'), 'feed_posts/p1'), { hidden: false }));
      await seedPost('p2');
      await assertFails(updateDoc(doc(as('author'), 'feed_posts/p2'), { hidden: true }));
      await assertFails(updateDoc(doc(as('stranger'), 'feed_posts/p2'), { hidden: true }));
    });

    it('a hidden post is private: strangers cannot read it by id, its author can', async () => {
      await seedPost('p1', { hidden: true });
      await assertFails(getDoc(doc(as('stranger'), 'feed_posts/p1')));
      await assertSucceeds(getDoc(doc(as('author'), 'feed_posts/p1')));
    });

    it('an ordinary post is still readable by strangers', async () => {
      await seedPost('p1');
      await assertSucceeds(getDoc(doc(as('stranger'), 'feed_posts/p1')));
    });
  });
});
