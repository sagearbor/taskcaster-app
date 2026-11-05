'use strict';

/**
 * WP-11 clip retention sweep (functions/src/retention.js) over an in-memory
 * store that implements the same queries as firestoreRetentionStore:
 * `retainUntil <= now` ordered by retainUntil, and the legacy
 * `createdAt <= cutoff` walk ordered by (createdAt, id) after a cursor.
 */

const test = require('node:test');
const assert = require('node:assert/strict');

const {sweep} = require('../src/retention');
const {DAY_MS} = require('../src/plans');

const NOW = Date.parse('2026-11-05T12:00:00Z');
const silent = {info() {}, warn() {}, error() {}};

function makeStore({clips = {}, users = {}, posts = [], montagePostIds = []} = {}) {
  const c = new Map(Object.entries(clips).map(([id, d]) => [id, {...d}]));
  const reads = {due: 0, legacy: 0, users: 0, postsForPath: 0, inMontage: 0};
  let state = {};
  const expired = [];
  const ms = (v) => (v instanceof Date ? v.getTime() : v);
  return {
    clips: c,
    reads,
    expired,
    get state() {
      return state;
    },
    async dueClips(nowMs, limit) {
      reads.due += 1;
      return [...c.entries()]
        .filter(([, d]) => d.retainUntil !== undefined && d.retainUntil !== null && ms(d.retainUntil) <= nowMs)
        .sort((a, b) => ms(a[1].retainUntil) - ms(b[1].retainUntil))
        .slice(0, limit)
        .map(([id, clip]) => ({id, clip: {...clip}}));
    },
    async legacyClips(cutoffMs, cursor, limit) {
      reads.legacy += 1;
      return [...c.entries()]
        .filter(([, d]) => ms(d.createdAt) <= cutoffMs)
        .sort((a, b) => ms(a[1].createdAt) - ms(b[1].createdAt) || a[0].localeCompare(b[0]))
        .filter(([id, d]) => !cursor ||
          ms(d.createdAt) > cursor.createdAtMs ||
          (ms(d.createdAt) === cursor.createdAtMs && id > cursor.id))
        .slice(0, limit)
        .map(([id, clip]) => ({id, clip: {...clip}}));
    },
    async getState() {
      return {...state};
    },
    async setState(s) {
      state = {...state, ...s};
    },
    async getUser(uid) {
      reads.users += 1;
      return users[uid] || null;
    },
    async postsForPath(objectPath) {
      reads.postsForPath += 1;
      return posts.filter((p) => p.videoStoragePath === objectPath);
    },
    async inMontage(postId) {
      reads.inMontage += 1;
      return montagePostIds.includes(postId);
    },
    async setRetainUntil(id, at) {
      if (c.has(id)) c.get(id).retainUntil = at;
    },
    async markPostsExpired(ids) {
      expired.push(...ids);
    },
    async deleteClip(id) {
      c.delete(id);
    },
  };
}

function makeStorage() {
  const deleted = [];
  return {deleted, deleteObject: async (p) => deleted.push(p)};
}

/** A clips/{uid}_{day}_{slot} doc, created `daysAgo`, due per WP-11 stamping. */
function clip(uid, daysAgo, {slot = '0', legacy = false} = {}) {
  const createdAt = NOW - daysAgo * DAY_MS;
  return {
    uid, day: '20260101', slot,
    createdAt,
    ...(legacy ? {} : {retainUntil: createdAt + 90 * DAY_MS}),
    sourcePath: `submissions/${uid}/20260101/${slot}`,
    playbackPath: `submissions/${uid}/20260101/${slot}`,
    posterPath: `transcoded/${uid}/20260101/${slot}.jpg`,
    status: 'ready',
  };
}

const run = (store, storage, extra = {}) => sweep({store, storage, now: NOW, logger: silent, ...extra});

test('a free user\'s clip older than 90 days is deleted: object, poster, doc; posts marked expired', async () => {
  const store = makeStore({
    clips: {old: clip('f1', 100), young: clip('f1', 10, {slot: '1'})},
    users: {f1: {plan: 'free'}},
    posts: [{id: 'p1', videoStoragePath: 'submissions/f1/20260101/0', gradeCount: 1, gradeSum: 2}],
  });
  const storage = makeStorage();
  const stats = await run(store, storage);
  assert.equal(stats.deleted, 1);
  assert.deepEqual(storage.deleted, ['submissions/f1/20260101/0', 'transcoded/f1/20260101/0.jpg']);
  assert.equal(store.clips.has('old'), false);
  assert.equal(store.clips.has('young'), true, 'not due: never even read');
  assert.deepEqual(store.expired, ['p1']);
});

test('a keeper (graded 4+ or in a montage) is kept for a year, and not re-read until then', async () => {
  const store = makeStore({
    clips: {graded: clip('f1', 100), montaged: clip('f1', 100, {slot: '1'}), ancient: clip('f1', 400, {slot: '2'})},
    users: {f1: {plan: 'free'}},
    posts: [
      {id: 'g', videoStoragePath: 'submissions/f1/20260101/0', gradeCount: 2, gradeSum: 9},
      {id: 'm', videoStoragePath: 'submissions/f1/20260101/1', gradeCount: 0, gradeSum: 0},
      {id: 'a', videoStoragePath: 'submissions/f1/20260101/2', gradeCount: 1, gradeSum: 5},
    ],
    montagePostIds: ['m'],
  });
  const storage = makeStorage();
  await run(store, storage);
  assert.equal(store.clips.has('graded'), true);
  assert.equal(store.clips.has('montaged'), true);
  assert.equal(store.clips.has('ancient'), false, 'a keeper is still gone after one year');
  assert.equal(store.clips.get('graded').retainUntil, NOW - 100 * DAY_MS + 365 * DAY_MS);

  // The next day nothing is due: zero clip work, one cheap query.
  const before = {...store.reads};
  const stats = await sweep({store, storage, now: NOW + DAY_MS, logger: silent});
  assert.equal(stats.examined, 0);
  assert.equal(store.reads.postsForPath, before.postsForPath);
});

test('an active Pro user\'s clips are kept; rechecked at the end of the paid period', async () => {
  const exp = NOW + 20 * DAY_MS;
  const store = makeStore({clips: {a: clip('p1', 500), b: clip('p1', 200, {slot: '1'})},
    users: {p1: {plan: 'pro', planExpiresAt: new Date(exp)}}});
  const stats = await run(store, makeStorage());
  assert.equal(stats.kept, 2);
  assert.equal(stats.deleted, 0);
  assert.ok(store.clips.get('a').retainUntil > exp);
  assert.equal(store.reads.users, 1, 'one user read per uid per run');
  assert.equal(store.reads.postsForPath, 0, 'no keeper lookups for a Pro user');
});

test('after a lapse: 90 days of grace, then free rules; never a year past the lapse', async () => {
  const exp = NOW + 20 * DAY_MS;
  const store = makeStore({clips: {a: clip('p1', 500)}, users: {p1: {plan: 'pro', planExpiresAt: new Date(exp)}}});
  const storage = makeStorage();
  await run(store, storage);
  // The plan lapses at exp (the EXPIRATION webhook ran).
  const lapsedUser = {plan: 'free', planLapsedAt: new Date(exp)};
  const at = (days) => exp + days * DAY_MS;
  const sweepAt = (when) => sweep({store, storage, now: when, logger: silent});
  store.getUser = async () => lapsedUser;
  await sweepAt(at(1));
  assert.equal(store.clips.has('a'), true, 'grace period');
  assert.equal(store.clips.get('a').retainUntil, at(90));
  await sweepAt(at(89));
  assert.equal(store.clips.has('a'), true);
  await sweepAt(at(90));
  assert.equal(store.clips.has('a'), false);
});

test('resubscribing during the grace period keeps the clips', async () => {
  const store = makeStore({clips: {a: clip('p1', 500)},
    users: {p1: {plan: 'free', planLapsedAt: new Date(NOW - 10 * DAY_MS)}}});
  await run(store, makeStorage());
  const due = store.clips.get('a').retainUntil;
  store.getUser = async () => ({plan: 'pro', planExpiresAt: new Date(due + 30 * DAY_MS)});
  await sweep({store, storage: makeStorage(), now: due, logger: silent});
  assert.equal(store.clips.has('a'), true);
});

test('legacy clips (no retainUntil) are walked once by createdAt, cursor persisted', async () => {
  const clips = {};
  for (let i = 0; i < 5; i++) clips[`l${i}`] = clip(`u${i}`, 100 + i, {legacy: true});
  clips.young = clip('u9', 5, {legacy: true});
  const store = makeStore({clips, users: {u0: {plan: 'pro', planExpiresAt: null}}});
  const storage = makeStorage();
  const stats = await run(store, storage, {pageSize: 2, legacyPages: 10});
  assert.equal(stats.legacyExamined, 5);
  assert.equal(store.clips.has('l0'), true, 'pro user, kept and now stamped');
  assert.ok(store.clips.get('l0').retainUntil > NOW);
  for (const id of ['l1', 'l2', 'l3', 'l4']) assert.equal(store.clips.has(id), false);
  assert.equal(store.clips.has('young'), true);
  assert.ok(store.state.legacyCursor);

  // A second run does not walk them again.
  const again = await run(store, storage, {pageSize: 2, legacyPages: 10});
  assert.equal(again.legacyExamined, 0);
});

test('idempotent: a Storage failure leaves the clip due, the next run finishes the job', async () => {
  const store = makeStore({clips: {a: clip('f1', 100)}, users: {f1: {plan: 'free'}}});
  let fail = true;
  const storage = {deleted: [], async deleteObject(p) {
    if (fail) throw new Error('gcs 503');
    this.deleted.push(p);
  }};
  const first = await run(store, storage);
  assert.equal(first.failed, 1);
  assert.equal(store.clips.has('a'), true);
  fail = false;
  await sweep({store, storage, now: NOW + DAY_MS, logger: silent});
  assert.equal(store.clips.has('a'), false);
});

test('bounded: at most maxPages x pageSize clips per run', async () => {
  const clips = {};
  for (let i = 0; i < 30; i++) clips[`c${i}`] = clip('f1', 100, {slot: String(i)});
  const store = makeStore({clips, users: {f1: {plan: 'free'}}});
  const stats = await run(store, makeStorage(), {pageSize: 5, maxPages: 2});
  assert.equal(stats.examined, 10);
  assert.equal(store.clips.size, 20);
});
