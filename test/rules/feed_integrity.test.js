// Firestore security rules tests for Arena integrity (WP-03): the crowd
// counters on feed_posts turn into game points, so every write path is pinned
// down exactly, and community_tasks.upvotes moves only by one vote per user.
// Each attack has a matching "normal client write still works" test.
// Run via test/rules/run.sh (firebase emulators:exec).
const { assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const {
  doc,
  getDoc,
  setDoc,
  updateDoc,
  deleteDoc,
  increment,
  arrayUnion,
  serverTimestamp,
  writeBatch,
  Timestamp,
} = require('firebase/firestore');
const { makeTestEnv } = require('./helpers');

function post(overrides = {}) {
  return {
    userId: 'author',
    gameId: 'g1',
    taskId: 'starter-01-v2',
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

describe('firestore.rules — feed_posts integrity', function () {
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

  /** Write a post bypassing rules (the state a real history could leave). */
  async function seed(id, data) {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const d = { ...post(), createdAt: Timestamp.now(), ...data };
      await setDoc(doc(ctx.firestore(), `feed_posts/${id}`), d);
    });
  }

  /** The app's grade transaction, as a batch. */
  function gradeBatch(db, id, uid, score, postUpdate) {
    const batch = writeBatch(db);
    batch.set(doc(db, `feed_posts/${id}/grades/${uid}`), {
      score,
      createdAt: serverTimestamp(),
    });
    batch.update(
      doc(db, `feed_posts/${id}`),
      postUpdate || {
        gradeCount: increment(1),
        gradeSum: increment(score),
        graderIds: arrayUnion(uid),
      }
    );
    return batch.commit();
  }

  // ---- create ----

  it('ALLOWED: a fresh post with zero counters and a server createdAt', async () => {
    await assertSucceeds(setDoc(doc(as('author'), 'feed_posts/p1'), post()));
  });

  it('DENIED: create with forged counters (gradeCount 3 / gradeSum 15)', async () => {
    await assertFails(
      setDoc(doc(as('author'), 'feed_posts/p1'), post({ gradeCount: 3, gradeSum: 15 }))
    );
  });

  it('DENIED: create pre-boosted, pre-tapped or pre-graded', async () => {
    const db = as('author');
    await assertFails(setDoc(doc(db, 'feed_posts/b'), post({ boosted: true })));
    await assertFails(setDoc(doc(db, 'feed_posts/t'), post({ tapCount: 9 })));
    await assertFails(setDoc(doc(db, 'feed_posts/s'), post({ tapSeconds: { 3: 9 } })));
    await assertFails(setDoc(doc(db, 'feed_posts/g'), post({ graderIds: ['x'] })));
  });

  it('DENIED: create with a client createdAt (far-future pin to the top)', async () => {
    const db = as('author');
    await assertFails(
      setDoc(doc(db, 'feed_posts/p1'), post({ createdAt: '9999-01-01T00:00:00.000Z' }))
    );
    await assertFails(
      setDoc(
        doc(db, 'feed_posts/p2'),
        post({ createdAt: Timestamp.fromDate(new Date('9999-01-01T00:00:00Z')) })
      )
    );
  });

  // WP-08: playbackUrl / posterUrl are server-owned (the app prefers
  // playbackUrl, so a client-chosen one could make a post play any URL).
  it('DENIED: create carrying a client playbackUrl or posterUrl', async () => {
    const db = as('author');
    const video = {
      mediaType: 'video',
      videoUrl: 'https://example.test/v',
      videoStoragePath: 'submissions/author/20261105/0',
    };
    await assertFails(
      setDoc(doc(db, 'feed_posts/v1'), post({ ...video, playbackUrl: 'https://evil.test/x.mp4' }))
    );
    await assertFails(
      setDoc(doc(db, 'feed_posts/v2'), post({ ...video, posterUrl: 'https://evil.test/x.jpg' }))
    );
    await assertFails(
      setDoc(doc(db, 'feed_posts/v3'), post({ ...video, playbackUrl: null }))
    );
    // The normal video post (no server fields) is still allowed.
    await assertSucceeds(setDoc(doc(db, 'feed_posts/v4'), post(video)));
  });

  it('DENIED: owner setting playbackUrl / posterUrl after the fact', async () => {
    await seed('p1', { mediaType: 'video', videoStoragePath: 'submissions/author/20261105/0' });
    const db = as('author');
    await assertFails(updateDoc(doc(db, 'feed_posts/p1'), { playbackUrl: 'https://evil.test/x.mp4' }));
    await assertFails(updateDoc(doc(db, 'feed_posts/p1'), { posterUrl: 'https://evil.test/x.jpg' }));
  });

  it('DENIED: any client reading or writing clips/ (server-only metadata)', async () => {
    const db = as('author');
    await assertFails(setDoc(doc(db, 'clips/author_20261105_0'), { status: 'ready' }));
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'clips/author_20261105_0'), { uid: 'author' });
    });
    await assertFails(getDoc(doc(db, 'clips/author_20261105_0')));
  });

  it('DENIED: create as someone else', async () => {
    await assertFails(setDoc(doc(as('mallory'), 'feed_posts/p1'), post()));
  });

  // ---- house posts ----

  it('DENIED: any client creating a house post', async () => {
    await assertFails(
      setDoc(
        doc(as('mallory'), 'feed_posts/house-starter-01-v2'),
        post({ userId: 'house', isHouse: true })
      )
    );
  });

  it('DENIED: a house-flagged post under your own uid', async () => {
    await assertFails(setDoc(doc(as('author'), 'feed_posts/p1'), post({ isHouse: true })));
  });

  it('DENIED: rewriting or deleting a seeded house post (vandalism)', async () => {
    await seed('house-starter-01-v2', { userId: 'house', isHouse: true });
    const db = as('mallory');
    await assertFails(
      updateDoc(doc(db, 'feed_posts/house-starter-01-v2'), { text: 'vandalised' })
    );
    await assertFails(
      updateDoc(doc(db, 'feed_posts/house-starter-01-v2'), { userId: 'house', caption: 'x' })
    );
    await assertFails(deleteDoc(doc(db, 'feed_posts/house-starter-01-v2')));
  });

  it('ALLOWED: grading and tapping a house post like any other', async () => {
    await seed('house-starter-01-v2', { userId: 'house', isHouse: true });
    const db = as('grader');
    await assertSucceeds(gradeBatch(db, 'house-starter-01-v2', 'grader', 5));
    await assertSucceeds(
      updateDoc(doc(db, 'feed_posts/house-starter-01-v2'), { tapCount: increment(1) })
    );
  });

  // ---- owner updates ----

  it('DENIED: owner forging their own counters', async () => {
    await seed('p1', { tapCount: 5, graderIds: ['x'], gradeCount: 1, gradeSum: 1 });
    const db = as('author');
    await assertFails(updateDoc(doc(db, 'feed_posts/p1'), { gradeCount: 3, gradeSum: 15 }));
    await assertFails(updateDoc(doc(db, 'feed_posts/p1'), { tapCount: 0 }));
    await assertFails(updateDoc(doc(db, 'feed_posts/p1'), { graderIds: [] }));
  });

  it('DENIED: owner changing identity, media pointer, game, task or createdAt', async () => {
    await seed('p1', {});
    const db = as('author');
    for (const change of [
      { userId: 'someone' },
      { videoStoragePath: 'submissions/author/x' },
      { gameId: 'g2' },
      { taskId: 'starter-02' },
      { createdAt: Timestamp.fromDate(new Date('9999-01-01T00:00:00Z')) },
      { isHouse: true },
    ]) {
      await assertFails(updateDoc(doc(db, 'feed_posts/p1'), change));
    }
  });

  it('ALLOWED: owner editing caption/text', async () => {
    await seed('p1', {});
    await assertSucceeds(
      updateDoc(doc(as('author'), 'feed_posts/p1'), { caption: 'c', text: 't' })
    );
  });

  // ---- boost ----

  it('ALLOWED: owner boosting their own post (false -> true)', async () => {
    await seed('p1', {});
    await assertSucceeds(updateDoc(doc(as('author'), 'feed_posts/p1'), { boosted: true }));
  });

  it('DENIED: owner un-boosting (true -> false)', async () => {
    await seed('p1', { boosted: true });
    await assertFails(updateDoc(doc(as('author'), 'feed_posts/p1'), { boosted: false }));
  });

  it('DENIED: a non-owner toggling boosted either way', async () => {
    await seed('p1', {});
    await seed('p2', { boosted: true });
    const db = as('mallory');
    await assertFails(updateDoc(doc(db, 'feed_posts/p1'), { boosted: true }));
    await assertFails(updateDoc(doc(db, 'feed_posts/p2'), { boosted: false }));
  });

  // ---- grades ----

  it('ALLOWED: a normal grade (grade doc + exact counter bump)', async () => {
    await seed('p1', { gradeCount: 1, gradeSum: 3, graderIds: ['early'] });
    await assertSucceeds(gradeBatch(as('grader'), 'p1', 'grader', 4));
  });

  it('DENIED: self-grade', async () => {
    await seed('p1', {});
    await assertFails(gradeBatch(as('author'), 'p1', 'author', 5));
  });

  it('DENIED: repeat grade (second grade doc + second bump)', async () => {
    await seed('p1', {});
    const db = as('grader');
    await assertSucceeds(gradeBatch(db, 'p1', 'grader', 5));
    await assertFails(gradeBatch(db, 'p1', 'grader', 5));
  });

  it('DENIED: a counter bump with no grade doc in the same commit', async () => {
    await seed('p1', {});
    await assertFails(
      updateDoc(doc(as('grader'), 'feed_posts/p1'), {
        gradeCount: increment(1),
        gradeSum: increment(5),
        graderIds: arrayUnion('grader'),
      })
    );
  });

  it('DENIED: a lone grade doc with no counter bump', async () => {
    await seed('p1', {});
    await assertFails(
      setDoc(doc(as('grader'), 'feed_posts/p1/grades/grader'), { score: 5 })
    );
  });

  it('DENIED: gradeSum that does not match the grade doc score', async () => {
    await seed('p1', {});
    await assertFails(
      gradeBatch(as('grader'), 'p1', 'grader', 1, {
        gradeCount: increment(1),
        gradeSum: increment(5),
        graderIds: arrayUnion('grader'),
      })
    );
  });

  it('DENIED: wiping graderIds while grading', async () => {
    await seed('p1', { gradeCount: 2, gradeSum: 8, graderIds: ['a', 'b'] });
    await assertFails(
      gradeBatch(as('grader'), 'p1', 'grader', 4, {
        gradeCount: increment(1),
        gradeSum: increment(4),
        graderIds: ['grader'],
      })
    );
  });

  it('DENIED: grading under someone else\'s uid', async () => {
    await seed('p1', {});
    await assertFails(
      gradeBatch(as('grader'), 'p1', 'victim', 1, {
        gradeCount: increment(1),
        gradeSum: increment(1),
        graderIds: arrayUnion('victim'),
      })
    );
  });

  // ---- taps ----

  it('ALLOWED: a plain tap and a timed tap', async () => {
    await seed('p1', { tapCount: 2, tapSeconds: { 3: 2 } });
    const db = as('viewer');
    await assertSucceeds(updateDoc(doc(db, 'feed_posts/p1'), { tapCount: increment(1) }));
    await assertSucceeds(
      updateDoc(doc(db, 'feed_posts/p1'), {
        tapCount: increment(2),
        'tapSeconds.3': increment(2),
        lastTapSecond: '3',
      })
    );
    await assertSucceeds(
      updateDoc(doc(db, 'feed_posts/p1'), {
        tapCount: increment(1),
        'tapSeconds.7': increment(1),
        lastTapSecond: '7',
      })
    );
  });

  it('DENIED: replacing tapSeconds wholesale', async () => {
    await seed('p1', { tapCount: 2, tapSeconds: { 3: 2 } });
    await assertFails(
      updateDoc(doc(as('viewer'), 'feed_posts/p1'), {
        tapCount: increment(1),
        tapSeconds: { 9: 1 },
        lastTapSecond: '9',
      })
    );
  });

  it('DENIED: a tapSeconds bucket moving by more than the tapCount delta', async () => {
    await seed('p1', {});
    await assertFails(
      updateDoc(doc(as('viewer'), 'feed_posts/p1'), {
        tapCount: increment(1),
        'tapSeconds.3': increment(40),
        lastTapSecond: '3',
      })
    );
  });

  it('DENIED: two tapSeconds buckets in one write', async () => {
    await seed('p1', {});
    await assertFails(
      updateDoc(doc(as('viewer'), 'feed_posts/p1'), {
        tapCount: increment(2),
        'tapSeconds.3': increment(1),
        'tapSeconds.4': increment(1),
        lastTapSecond: '3',
      })
    );
  });

  it('DENIED: tapCount going backwards', async () => {
    await seed('p1', { tapCount: 9 });
    await assertFails(updateDoc(doc(as('viewer'), 'feed_posts/p1'), { tapCount: 0 }));
  });
});

describe('firestore.rules — community_tasks upvotes', function () {
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

  async function seedTask(upvotes = 2) {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'community_tasks/t1'), {
        title: 'Hop',
        description: 'Hop a lot',
        submittedBy: 'author',
        upvotes,
      });
    });
  }

  function vote(db, uid, update = { upvotes: increment(1) }) {
    const batch = writeBatch(db);
    batch.set(doc(db, `community_tasks/t1/votes/${uid}`), { createdAt: serverTimestamp() });
    batch.update(doc(db, 'community_tasks/t1'), update);
    return batch.commit();
  }

  it('ALLOWED: one upvote with its vote doc', async () => {
    await seedTask();
    await assertSucceeds(vote(as('fan'), 'fan'));
  });

  it('DENIED: a second upvote by the same user', async () => {
    await seedTask();
    const db = as('fan');
    await assertSucceeds(vote(db, 'fan'));
    await assertFails(vote(db, 'fan'));
  });

  it('DENIED: an upvote with no vote doc', async () => {
    await seedTask();
    await assertFails(updateDoc(doc(as('fan'), 'community_tasks/t1'), { upvotes: increment(1) }));
  });

  it('DENIED: setting upvotes wholesale (non-author or author)', async () => {
    await seedTask();
    await assertFails(vote(as('fan'), 'fan', { upvotes: 999 }));
    await assertFails(updateDoc(doc(as('author'), 'community_tasks/t1'), { upvotes: 999 }));
    await assertFails(updateDoc(doc(as('fan'), 'community_tasks/t1'), { upvotes: 0 }));
  });

  it('DENIED: creating a task with a head-start tally', async () => {
    await assertFails(
      setDoc(doc(as('author'), 'community_tasks/t2'), {
        title: 'x',
        submittedBy: 'author',
        upvotes: 50,
      })
    );
  });

  it('ALLOWED: creating a task at zero; author editing its content', async () => {
    const db = as('author');
    await assertSucceeds(
      setDoc(doc(db, 'community_tasks/t2'), { title: 'x', submittedBy: 'author', upvotes: 0 })
    );
    await assertSucceeds(updateDoc(doc(db, 'community_tasks/t2'), { title: 'y' }));
  });

  it('DENIED: withdrawing or rewriting a vote doc', async () => {
    await seedTask();
    const db = as('fan');
    await assertSucceeds(vote(db, 'fan'));
    await assertFails(deleteDoc(doc(db, 'community_tasks/t1/votes/fan')));
    await assertFails(setDoc(doc(db, 'community_tasks/t1/votes/fan'), { createdAt: 1 }));
  });
});
