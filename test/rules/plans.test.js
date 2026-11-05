// WP-11 (audit 2026-11-05): Free + Pro plans.
//   - Firestore: the plan fields on users/{uid} are server-owned; a client can
//     never grant itself Pro (create, update or merge).
//   - Storage: the clip caps read that plan (cross-service firestore.get):
//     guest 5 lifetime, free 3 a day, Pro 15 a day and bigger files.
// Run via test/rules/run.sh (firebase emulators:exec, Firestore + Storage).
const { assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { doc, setDoc, updateDoc, getDoc, Timestamp } = require('firebase/firestore');
const { ref, uploadBytes, listAll, deleteObject } = require('firebase/storage');
const { makeTestEnv } = require('./helpers');

const MB = 1024 * 1024;
const DAY_MS = 24 * 60 * 60 * 1000;

const bytes = (n) => new Uint8Array(n).fill(7);
const video = { contentType: 'video/mp4' };

function dayKey(date) {
  const two = (n) => String(n).padStart(2, '0');
  return `${date.getUTCFullYear()}${two(date.getUTCMonth() + 1)}${two(date.getUTCDate())}`;
}

async function clearStorageDeep(testEnv) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const walk = async (r) => {
      const { items, prefixes } = await listAll(r);
      await Promise.all(items.map((item) => deleteObject(item)));
      for (const p of prefixes) {
        // eslint-disable-next-line no-await-in-loop
        await walk(p);
      }
    };
    await walk(ref(ctx.storage()));
  });
}

// What the RevenueCat webhook writes (Admin SDK = rules disabled here).
async function seedPlan(testEnv, uid, fields) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), `users/${uid}`), { displayName: uid, ...fields });
  });
}

const proUntil = (ms) => ({ plan: 'pro', planExpiresAt: Timestamp.fromMillis(ms), planStatus: 'active' });

describe('firestore.rules — users/{uid} plan fields are server-owned (WP-11)', function () {
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

  it('a client may still create and edit its own profile', async () => {
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(setDoc(doc(alice, 'users/alice'), { displayName: 'Alice', avatarEmoji: '🎉' }));
    await assertSucceeds(setDoc(doc(alice, 'users/alice'), { displayName: 'Al' }, { merge: true }));
    await assertSucceeds(updateDoc(doc(alice, 'users/alice'), { avatarEmoji: '🦊' }));
  });

  it('a client write of users/{uid}.plan = "pro" is denied (create, merge and update)', async () => {
    const alice = testEnv.authenticatedContext('alice').firestore();
    const far = Timestamp.fromMillis(Date.now() + 365 * DAY_MS);
    await assertFails(setDoc(doc(alice, 'users/alice'), { displayName: 'Alice', plan: 'pro' }));
    await assertSucceeds(setDoc(doc(alice, 'users/alice'), { displayName: 'Alice' }));
    await assertFails(setDoc(doc(alice, 'users/alice'), { plan: 'pro' }, { merge: true }));
    await assertFails(updateDoc(doc(alice, 'users/alice'), { plan: 'pro', planExpiresAt: far }));
    await assertFails(updateDoc(doc(alice, 'users/alice'), { planExpiresAt: far }));
    await assertFails(updateDoc(doc(alice, 'users/alice'), { planLapsedAt: null }));
    await assertFails(updateDoc(doc(alice, 'users/alice'), { usage: { clips: 0 } }));
  });

  it('a Pro user can edit their profile but cannot extend, keep or clear their plan', async () => {
    await seedPlan(testEnv, 'pro1', proUntil(Date.now() + 5 * DAY_MS));
    const pro = testEnv.authenticatedContext('pro1').firestore();
    await assertSucceeds(updateDoc(doc(pro, 'users/pro1'), { displayName: 'Pro One' }));
    await assertFails(updateDoc(doc(pro, 'users/pro1'), {
      planExpiresAt: Timestamp.fromMillis(Date.now() + 999 * DAY_MS),
    }));
    await assertFails(updateDoc(doc(pro, 'users/pro1'), { planStatus: 'active', planWillRenew: true }));
    // A whole-doc overwrite that drops the plan fields also touches them.
    await assertFails(setDoc(doc(pro, 'users/pro1'), { displayName: 'Pro One' }));
  });

  it('nobody can write another user\'s plan', async () => {
    await seedPlan(testEnv, 'alice', { plan: 'free' });
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertFails(updateDoc(doc(bob, 'users/alice'), { plan: 'pro' }));
    await assertSucceeds(getDoc(doc(bob, 'users/alice')));
  });
});

describe('storage.rules — plan-aware clip caps (WP-11)', function () {
  this.timeout(240000);
  let testEnv;

  before(async () => {
    testEnv = await makeTestEnv();
  });

  afterEach(async () => {
    await clearStorageDeep(testEnv);
    await testEnv.clearFirestore();
  });

  after(async () => {
    await testEnv.cleanup();
  });

  const DAY = dayKey(new Date());
  const today = (uid, slot) => `submissions/${uid}/${DAY}/${slot}`;
  const put = (storage, path, n = 1024) => uploadBytes(ref(storage, path), bytes(n), video);

  it('free: slots 0-2 today are accepted, the 4th clip today (slot 3) is denied', async () => {
    await seedPlan(testEnv, 'free1', { plan: 'free' });
    const storage = testEnv.authenticatedContext('free1').storage();
    for (const slot of ['0', '1', '2']) {
      // eslint-disable-next-line no-await-in-loop
      await assertSucceeds(put(storage, today('free1', slot)));
    }
    await assertFails(put(storage, today('free1', '3')));
    await assertFails(put(storage, today('free1', 'a')));
  });

  it('pro: the same 4th clip today is allowed, up to 15 (slots 0-9, a-e)', async () => {
    await seedPlan(testEnv, 'pro1', proUntil(Date.now() + 30 * DAY_MS));
    const storage = testEnv.authenticatedContext('pro1').storage();
    for (const slot of ['0', '1', '2', '3']) {
      // eslint-disable-next-line no-await-in-loop
      await assertSucceeds(put(storage, today('pro1', slot)));
    }
    await assertSucceeds(put(storage, today('pro1', '9')));
    await assertSucceeds(put(storage, today('pro1', 'e')));
    await assertFails(put(storage, today('pro1', 'f')), 'a 16th slot does not exist');
    await assertFails(put(storage, today('pro1', '10')));
  });

  it('pro: a 40 MiB clip is allowed; the same file is over the free cap', async () => {
    await seedPlan(testEnv, 'pro1', proUntil(Date.now() + 30 * DAY_MS));
    await seedPlan(testEnv, 'free1', { plan: 'free' });
    const pro = testEnv.authenticatedContext('pro1').storage();
    const free = testEnv.authenticatedContext('free1').storage();
    await assertSucceeds(put(pro, today('pro1', '0'), 40 * MB));
    await assertFails(put(free, today('free1', '0'), 40 * MB));
  });

  it('an expired Pro plan is free (planExpiresAt in the past), whatever `plan` says', async () => {
    await seedPlan(testEnv, 'old1', proUntil(Date.now() - DAY_MS));
    const storage = testEnv.authenticatedContext('old1').storage();
    await assertSucceeds(put(storage, today('old1', '0')));
    await assertFails(put(storage, today('old1', '3')));
  });

  it('no users doc at all is free', async () => {
    const storage = testEnv.authenticatedContext('nodoc').storage();
    await assertSucceeds(put(storage, today('nodoc', '2')));
    await assertFails(put(storage, today('nodoc', '3')));
  });

  it('a client that tried to grant itself Pro still gets the free cap', async () => {
    const db = testEnv.authenticatedContext('cheat').firestore();
    await assertFails(setDoc(doc(db, 'users/cheat'), { plan: 'pro' }));
    const storage = testEnv.authenticatedContext('cheat').storage();
    await assertFails(put(storage, today('cheat', '3')));
  });

  it('guest (anonymous): 5 lifetime clips at submissions/{uid}/guest/0-4, nothing else', async () => {
    const guest = testEnv
      .authenticatedContext('guest1', { firebase: { sign_in_provider: 'anonymous' } })
      .storage();
    for (const slot of ['0', '1', '2', '3', '4']) {
      // eslint-disable-next-line no-await-in-loop
      await assertSucceeds(put(guest, `submissions/guest1/guest/${slot}`));
    }
    await assertFails(put(guest, 'submissions/guest1/guest/5'), 'the 6th guest clip');
    await assertFails(put(guest, today('guest1', '0')), 'no daily slots for a guest');
    await assertFails(put(guest, 'submissions/guest1/guest/0'), 'no overwrite');
    await assertFails(put(guest, 'submissions/guest1/guest/1', 33 * MB));
  });

  it('a signed-in (non-anonymous) user cannot write the guest folder', async () => {
    const storage = testEnv.authenticatedContext('free1').storage();
    await assertFails(put(storage, 'submissions/free1/guest/0'));
  });
});
