'use strict';

/**
 * WP-04 cost guards (audit 2026-11-05): nobody can force montage renders.
 *
 *   - a post under a made-up taskId / gameId, or in a game the poster is not
 *     in, never queues a montage;
 *   - each uid can queue at most MONTAGE_QUEUE_PER_UID_PER_DAY posts a day;
 *   - renderMontageNow needs the `admin` custom claim;
 *   - a post that lands mid-render leaves the montage pending.
 *
 * Runs against an in-memory Firestore (fake_firestore.js) with a stubbed
 * render: no emulator, no ffmpeg.
 */

const fs = require('fs');
const path = require('path');
const test = require('node:test');
const assert = require('node:assert/strict');

const {STARTER_TASK_IDS, montageDocId} = require('../src/contract');
const {
  MONTAGE_QUEUE_PER_UID_PER_DAY,
  admitPost,
  dayKey,
  isGameMember,
  isKnownStarterTask,
  requireAdmin,
  takeQuota,
} = require('../src/guards');
const pipeline = require('../src/pipeline');
const {makeFakeFirestore} = require('./fake_firestore');

const NOW = new Date('2026-11-05T12:00:00.000Z');

const GAME = {
  creatorId: 'host',
  playerIds: ['host', 'alice'],
  players: [{userId: 'host'}, {userId: 'alice'}],
  tasks: [{id: 'task-1'}, {id: 'task-2'}],
};

let postSeq = 0;
function videoPost(overrides = {}) {
  postSeq += 1;
  const userId = overrides.userId || 'alice';
  return {
    id: `p${postSeq}`,
    gameId: 'g1',
    taskId: 'task-1',
    userId,
    mediaType: 'video',
    videoStoragePath: `submissions/${userId}/20261105/${postSeq % 10}`,
    createdAt: NOW.toISOString(),
    ...overrides,
  };
}

// WP-11: friend-game montages need a Pro HOST; the default host is Pro.
const PRO_HOST = {plan: 'pro', planExpiresAt: new Date('2027-01-01T00:00:00Z')};

function setup(seed = {'games/g1': GAME, 'users/host': PRO_HOST}) {
  const db = makeFakeFirestore(seed);
  const renders = [];
  const render = async (gameId, taskId) => {
    renders.push({gameId, taskId});
  };
  const handle = (post, now = NOW) => pipeline.handleNewPost(post, {db, render, now: () => now});
  return {db, renders, handle};
}

// ---------------------------------------------------------------------------
// admitPost: what may queue a render at all
// ---------------------------------------------------------------------------

test('admitPost: a member posting to a real task of the game is admitted', () => {
  assert.deepEqual(admitPost({post: videoPost(), game: GAME}), {ok: true, reason: 'member'});
});

test('admitPost: a made-up taskId in a real game is refused', () => {
  const verdict = admitPost({post: videoPost({taskId: 'made-up'}), game: GAME});
  assert.deepEqual(verdict, {ok: false, reason: 'unknown-task'});
});

test('admitPost: a made-up gameId (no game doc) is refused', () => {
  assert.deepEqual(
    admitPost({post: videoPost({gameId: 'nope'}), game: null}),
    {ok: false, reason: 'no-game'},
  );
});

test('admitPost: someone else\'s game is refused', () => {
  assert.deepEqual(
    admitPost({post: videoPost({userId: 'mallory'}), game: GAME}),
    {ok: false, reason: 'not-a-member'},
  );
});

test('admitPost: a real Starter Pack id is admitted without a game', () => {
  const post = videoPost({gameId: 'whatever', taskId: 'starter-03'});
  assert.deepEqual(admitPost({post, game: null}), {ok: true, reason: 'starter'});
});

test('admitPost: a made-up starter-* id is refused', () => {
  const post = videoPost({gameId: 'whatever', taskId: 'starter-99-evil'});
  assert.deepEqual(admitPost({post, game: null}), {ok: false, reason: 'unknown-starter-task'});
});

test('admitPost: house posts and non-video posts never queue', () => {
  assert.equal(admitPost({post: videoPost({userId: 'house'}), game: GAME}).ok, false);
  assert.equal(admitPost({post: videoPost({isHouse: true}), game: GAME}).ok, false);
  assert.equal(admitPost({post: videoPost({mediaType: 'photo'}), game: GAME}).ok, false);
});

test('isGameMember falls back to players[] and creatorId on older game docs', () => {
  assert.equal(isGameMember({players: [{userId: 'a'}]}, 'a'), true);
  assert.equal(isGameMember({creatorId: 'a'}, 'a'), true);
  assert.equal(isGameMember({playerIds: ['b']}, 'a'), false);
  assert.equal(isGameMember(null, 'a'), false);
});

test('STARTER_TASK_IDS matches the app\'s starter pack', () => {
  const dart = fs.readFileSync(
    path.join(__dirname, '../../lib/features/tasks/data/datasources/starter_pack_data.dart'),
    'utf8',
  );
  const ids = [...dart.matchAll(/id:\s*'(starter-[^']+)'/g)].map((m) => m[1]);
  assert.ok(ids.length >= 10, `expected the starter ids in the Dart file, got ${ids}`);
  assert.deepEqual([...STARTER_TASK_IDS].sort(), [...new Set(ids)].sort());
  for (const id of ids) assert.equal(isKnownStarterTask(id), true);
});

// ---------------------------------------------------------------------------
// onFeedPostCreated (handleNewPost) end to end
// ---------------------------------------------------------------------------

test('a post with a bogus taskId does not create a montage job', async () => {
  const {db, renders, handle} = setup();
  for (let i = 0; i < 3; i++) {
    // eslint-disable-next-line no-await-in-loop
    const result = await handle(videoPost({taskId: 'made-up'}));
    assert.equal(result.queued, false);
    assert.equal(result.reason, 'unknown-task');
  }
  assert.equal(db.peek(`montages/${montageDocId('g1', 'made-up')}`), null);
  assert.equal(renders.length, 0);
  // ...and it costs the poster no quota either.
  assert.equal(db.peek(`montage_quota/alice/days/${dayKey(NOW)}`), null);
});

test('WP-11: a FREE host\'s friend game never queues or renders a montage', async () => {
  const {db, renders, handle} = setup({'games/g1': GAME, 'users/host': {plan: 'free'}});
  for (const userId of ['alice', 'host', 'alice']) {
    // eslint-disable-next-line no-await-in-loop
    const result = await handle(videoPost({userId}));
    assert.deepEqual(result, {queued: false, reason: 'host-not-pro'});
  }
  assert.equal(renders.length, 0);
  assert.equal(db.peek(`montages/${montageDocId('g1', 'task-1')}`), null);
  assert.equal(db.peek(`montage_quota/alice/days/${dayKey(NOW)}`), null, 'no quota charged');
});

test('WP-11: a lapsed Pro host (expired planExpiresAt) is a free host', async () => {
  const lapsed = {plan: 'pro', planExpiresAt: new Date('2026-11-01T00:00:00Z')};
  const {renders, handle} = setup({'games/g1': GAME, 'users/host': lapsed});
  const result = await handle(videoPost());
  assert.equal(result.reason, 'host-not-pro');
  assert.equal(renders.length, 0);
});

test('WP-11: a free invitee posting in a PRO host\'s game queues the montage', async () => {
  const {renders, handle} = setup();
  for (let i = 0; i < 3; i++) {
    // eslint-disable-next-line no-await-in-loop
    const result = await handle(videoPost({userId: 'alice'}));
    assert.equal(result.queued, true);
  }
  assert.equal(renders.length, 1, 'every player in the Pro host\'s game gets the finale');
});

test('WP-11: Starter Pack montages stay free (no host check)', async () => {
  const {renders, handle} = setup({});
  const starter = [...STARTER_TASK_IDS][0];
  for (let i = 0; i < 3; i++) {
    // eslint-disable-next-line no-await-in-loop
    await handle(videoPost({userId: `u${i}`, gameId: `solo-${i}`, taskId: starter}));
  }
  assert.equal(renders.length, 1);
});

test('three posts under a made-up gameId never render', async () => {
  const {db, renders, handle} = setup();
  for (let i = 0; i < 3; i++) {
    // eslint-disable-next-line no-await-in-loop
    await handle(videoPost({gameId: 'fake-game', taskId: 'fake-task'}));
  }
  assert.equal(renders.length, 0);
  assert.equal(db.peek(`montages/${montageDocId('fake-game', 'fake-task')}`), null);
});

test('three real posts by members queue and render once', async () => {
  const {db, renders, handle} = setup();
  await handle(videoPost({userId: 'alice'}));
  await handle(videoPost({userId: 'host'}));
  const third = await handle(videoPost({userId: 'alice'}));
  assert.equal(third.queued, true);
  assert.equal(third.rendered, true);
  assert.deepEqual(renders, [{gameId: 'g1', taskId: 'task-1'}]);
  const doc = db.peek(`montages/${montageDocId('g1', 'task-1')}`);
  assert.equal(doc.status, 'pending');
  assert.equal(doc.pendingCount, 3);
});

test('a starter-task post queues without a game doc', async () => {
  const {db, handle} = setup({});
  const result = await handle(videoPost({gameId: 'solo-123', taskId: 'starter-03'}));
  assert.equal(result.queued, true);
  assert.equal(db.peek('montages/starter_starter-03').pendingCount, 1);
});

// ---------------------------------------------------------------------------
// Per-uid daily quota
// ---------------------------------------------------------------------------

test('takeQuota stops at the limit', () => {
  assert.deepEqual(takeQuota(0), {ok: true, count: 1});
  assert.deepEqual(
    takeQuota(MONTAGE_QUEUE_PER_UID_PER_DAY - 1),
    {ok: true, count: MONTAGE_QUEUE_PER_UID_PER_DAY},
  );
  assert.equal(takeQuota(MONTAGE_QUEUE_PER_UID_PER_DAY).ok, false);
  assert.equal(takeQuota(undefined).ok, true);
});

test('one uid can queue at most the daily quota; the next UTC day resets it', async () => {
  const {db, handle} = setup();
  const results = [];
  for (let i = 0; i < MONTAGE_QUEUE_PER_UID_PER_DAY + 3; i++) {
    // Spread over two tasks so the montage doc never renders/locks mid-test.
    // eslint-disable-next-line no-await-in-loop
    results.push(await handle(videoPost({taskId: i % 2 ? 'task-1' : 'task-2'})));
  }
  const queued = results.filter((r) => r.queued).length;
  assert.equal(queued, MONTAGE_QUEUE_PER_UID_PER_DAY);
  assert.deepEqual(
    results.slice(MONTAGE_QUEUE_PER_UID_PER_DAY).map((r) => r.reason),
    ['quota', 'quota', 'quota'],
  );
  assert.equal(
    db.peek(`montage_quota/alice/days/${dayKey(NOW)}`).count,
    MONTAGE_QUEUE_PER_UID_PER_DAY,
  );

  // A different uid is unaffected.
  assert.equal((await handle(videoPost({userId: 'host'}))).queued, true);

  // Tomorrow alice has a fresh allowance.
  const tomorrow = new Date(NOW.getTime() + 24 * 3600 * 1000);
  assert.equal((await handle(videoPost(), tomorrow)).queued, true);
});

// ---------------------------------------------------------------------------
// renderMontageNow: admin claim only
// ---------------------------------------------------------------------------

test('requireAdmin: no auth -> unauthenticated, no admin claim -> permission-denied', () => {
  assert.throws(() => requireAdmin({}), (err) => err.code === 'unauthenticated');
  assert.throws(
    () => requireAdmin({auth: {uid: 'guest', token: {firebase: {sign_in_provider: 'anonymous'}}}}),
    (err) => err.code === 'permission-denied',
  );
  assert.throws(
    () => requireAdmin({auth: {uid: 'u', token: {admin: 'true'}}}),
    (err) => err.code === 'permission-denied',
  );
  assert.doesNotThrow(() => requireAdmin({auth: {uid: 'ops', token: {admin: true}}}));
});

test('renderMontageNow without the admin claim -> permission-denied (exported callable)', async () => {
  // Requiring index.js runs initializeApp() with no credentials; nothing here
  // touches Firestore because the guard throws first.
  const {renderMontageNow} = require('../src/index');
  await assert.rejects(
    renderMontageNow.run({
      auth: {uid: 'guest', token: {}},
      data: {gameId: 'g1', taskId: 'task-1', force: true},
    }),
    (err) => err.code === 'permission-denied',
  );
  await assert.rejects(
    renderMontageNow.run({data: {gameId: 'g1', taskId: 'task-1'}}),
    (err) => err.code === 'unauthenticated',
  );
});

// ---------------------------------------------------------------------------
// Finalize: a post arriving mid-render keeps the montage pending
// ---------------------------------------------------------------------------

test('a post arriving mid-render leaves the montage pending', async () => {
  const {db, renders, handle} = setup();
  const ref = pipeline.montageRef(db, 'g1', 'task-1');
  const docPath = `montages/${montageDocId('g1', 'task-1')}`;

  // Three posts queue; the stubbed render does nothing, so drive the real
  // claim -> (a post lands) -> finalize sequence by hand.
  for (const uid of ['alice', 'host', 'alice']) {
    // eslint-disable-next-line no-await-in-loop
    await handle(videoPost({userId: uid}));
  }
  assert.equal(renders.length, 1);

  const claimedAt = new Date(NOW.getTime() + 1000);
  const claim = await pipeline.claim(db, ref, {now: () => claimedAt});
  assert.equal(claim.claimed, true);
  assert.equal(claim.pendingCount, 3);

  // ffmpeg is busy; a fourth clip lands. The doc is locked, so no new render.
  const late = await handle(videoPost({userId: 'host'}), new Date(NOW.getTime() + 2000));
  assert.equal(late.queued, true);
  assert.equal(late.decision.reason, 'locked');
  assert.equal(renders.length, 1);
  assert.equal(db.peek(docPath).pendingCount, 4);

  const written = await pipeline.finalize(db, ref, {finaleUrl: 'u', version: 1}, claim);
  assert.equal(written.status, 'pending');
  const doc = db.peek(docPath);
  assert.equal(doc.status, 'pending');
  assert.equal(doc.pendingCount, 1);
  assert.equal(doc.pendingSince, claimedAt.toISOString());
  assert.equal(doc.lockedAt, null);
  assert.equal(doc.finaleUrl, 'u', 'the finished render is still published');
});

test('finalize with no newcomers marks the montage ready and empties the queue', async () => {
  const {db, handle} = setup();
  const ref = pipeline.montageRef(db, 'g1', 'task-1');
  for (const uid of ['alice', 'host', 'alice']) {
    // eslint-disable-next-line no-await-in-loop
    await handle(videoPost({userId: uid}));
  }
  const claim = await pipeline.claim(db, ref, {now: () => NOW});
  await pipeline.finalize(db, ref, {version: 1}, claim);
  const doc = db.peek(`montages/${montageDocId('g1', 'task-1')}`);
  assert.equal(doc.status, 'ready');
  assert.equal(doc.pendingCount, 0);
  assert.equal(doc.pendingSince, null);
  assert.equal(doc.lockedAt, null);
});
