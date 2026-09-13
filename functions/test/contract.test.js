'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  montageDocId,
  finaleObjectPath,
  momentsObjectPath,
  publicUrl,
  storagePathFromUrl,
  objectPathForPost,
  isMontageablePost,
  selectClips,
  decideRender,
  clipFromPost,
} = require('../src/contract');

const BUCKET = 'taskmaster-app-3d480.firebasestorage.app';
const MINUTE = 60000;

test('montage doc id and object paths follow the contract', () => {
  assert.equal(montageDocId('g1', 'starter-01'), 'g1_starter-01');
  assert.equal(finaleObjectPath('g1', 'starter-01'), 'montages/g1/starter-01/finale.mp4');
  assert.equal(momentsObjectPath('g1', 'starter-01'), 'montages/g1/starter-01/moments.mp4');
});

test('publicUrl builds the anyone-can-read download URL', () => {
  assert.equal(
    publicUrl(BUCKET, 'montages/g1/starter-01/finale.mp4'),
    `https://firebasestorage.googleapis.com/v0/b/${BUCKET}` +
      '/o/montages%2Fg1%2Fstarter-01%2Ffinale.mp4?alt=media',
  );
});

test('storagePathFromUrl round-trips publicUrl and handles the GCS form', () => {
  const objectPath = 'submissions/uid123/20260912/3';
  assert.equal(storagePathFromUrl(publicUrl(BUCKET, objectPath)), objectPath);
  assert.equal(
    storagePathFromUrl(`https://storage.googleapis.com/${BUCKET}/house/starter-01.mp4`),
    'house/starter-01.mp4',
  );
  assert.equal(storagePathFromUrl('not a url'), null);
  assert.equal(storagePathFromUrl(null), null);
});

test('objectPathForPost prefers videoStoragePath, falls back to videoUrl', () => {
  assert.equal(objectPathForPost({videoStoragePath: 'submissions/u/2026/0'}), 'submissions/u/2026/0');
  assert.equal(
    objectPathForPost({videoUrl: publicUrl(BUCKET, 'submissions/u/2026/1')}),
    'submissions/u/2026/1',
  );
  assert.equal(objectPathForPost({}), null);
});

test('isMontageablePost keeps player videos only', () => {
  const base = {taskId: 't1', mediaType: 'video', videoStoragePath: 'submissions/u/d/0'};
  assert.equal(isMontageablePost(base, 't1'), true);
  assert.equal(isMontageablePost(base, 'other-task'), false);
  assert.equal(isMontageablePost({...base, mediaType: 'photo'}, 't1'), false);
  assert.equal(isMontageablePost({...base, mediaType: 'text'}, 't1'), false);
  assert.equal(isMontageablePost({...base, isHouse: true}, 't1'), false);
  assert.equal(isMontageablePost({...base, videoStoragePath: null}, 't1'), false);
  assert.equal(isMontageablePost(null, 't1'), false);
});

test('selectClips filters by task, orders by createdAt and caps the count', () => {
  const post = (id, taskId, createdAt, extra = {}) => ({
    id, taskId, createdAt, mediaType: 'video', videoStoragePath: `submissions/u/d/${id}`, ...extra,
  });
  const posts = [
    post('c', 't1', '2026-09-12T10:02:00.000Z'),
    post('a', 't1', '2026-09-12T10:00:00.000Z'),
    post('house', 't1', '2026-09-12T09:00:00.000Z', {isHouse: true}),
    post('other', 't2', '2026-09-12T10:01:00.000Z'),
    post('b', 't1', '2026-09-12T10:01:00.000Z'),
    {id: 'txt', taskId: 't1', mediaType: 'text', createdAt: '2026-09-12T10:03:00.000Z'},
  ];
  assert.deepEqual(selectClips(posts, {taskId: 't1'}).map((p) => p.id), ['a', 'b', 'c']);
  // The cap keeps the NEWEST clips.
  assert.deepEqual(selectClips(posts, {taskId: 't1', maxClips: 2}).map((p) => p.id), ['b', 'c']);
  assert.deepEqual(selectClips([], {taskId: 't1'}), []);
});

test('decideRender: three clips render immediately', () => {
  const now = Date.parse('2026-09-12T12:00:00.000Z');
  const doc = {
    status: 'pending', pendingCount: 3, pendingSince: '2026-09-12T11:59:00.000Z',
  };
  assert.deepEqual(decideRender(doc, now), {render: true, reason: 'threshold'});
});

test('decideRender: fewer than three clips wait', () => {
  const now = Date.parse('2026-09-12T12:00:00.000Z');
  for (const pendingCount of [1, 2]) {
    const doc = {status: 'pending', pendingCount, pendingSince: '2026-09-12T11:55:00.000Z'};
    assert.deepEqual(
      decideRender(doc, now), {render: false, reason: 'waiting'},
      `pendingCount=${pendingCount}`,
    );
  }
});

test('decideRender: a lone clip renders once the settle window passes', () => {
  const since = Date.parse('2026-09-12T11:00:00.000Z');
  const doc = {status: 'pending', pendingCount: 1, pendingSince: new Date(since).toISOString()};
  assert.equal(decideRender(doc, since + 29 * MINUTE).render, false);
  assert.deepEqual(decideRender(doc, since + 30 * MINUTE), {render: true, reason: 'settled'});
  assert.deepEqual(decideRender(doc, since + 90 * MINUTE), {render: true, reason: 'settled'});
});

test('decideRender: only pending docs render', () => {
  const now = Date.now();
  assert.deepEqual(decideRender(null, now), {render: false, reason: 'no-doc'});
  for (const status of ['ready', 'failed']) {
    assert.deepEqual(
      decideRender({status, pendingCount: 9}, now), {render: false, reason: 'not-pending'},
    );
  }
});

test('decideRender: a fresh claim blocks a second render, a stale one does not', () => {
  const now = Date.parse('2026-09-12T12:00:00.000Z');
  const doc = (lockedAt) => ({
    status: 'pending', pendingCount: 5, pendingSince: '2026-09-12T11:00:00.000Z', lockedAt,
  });
  assert.deepEqual(
    decideRender(doc(new Date(now - 60000).toISOString()), now),
    {render: false, reason: 'locked'},
  );
  assert.deepEqual(
    decideRender(doc(new Date(now - 20 * MINUTE).toISOString()), now),
    {render: true, reason: 'threshold'},
  );
});

test('decideRender accepts Firestore Timestamps and Dates for the clock fields', () => {
  const since = Date.parse('2026-09-12T11:00:00.000Z');
  const asTimestamp = {seconds: since / 1000, nanoseconds: 0};
  const doc = {status: 'pending', pendingCount: 1, pendingSince: asTimestamp};
  assert.equal(decideRender(doc, since + 31 * MINUTE).render, true);
  const withDate = {status: 'pending', pendingCount: 1, pendingSince: new Date(since)};
  assert.equal(decideRender(withDate, new Date(since + 31 * MINUTE)).render, true);
});

test('clipFromPost maps the feed-post fields the renderer needs', () => {
  const clip = clipFromPost({
    id: 'p1',
    timerSeconds: 30,
    clockOffsetSeconds: 4,
    isLate: true,
    tapSeconds: {3: 2},
    videoDurationSeconds: 12.5,
    displayName: 'Sage',
  }, '/tmp/p1.mp4');
  assert.deepEqual(clip, {
    path: '/tmp/p1.mp4',
    postId: 'p1',
    timerSeconds: 30,
    clockOffsetSeconds: 4,
    isLate: true,
    tapSeconds: {3: 2},
    durationSeconds: 12.5,
    displayName: 'Sage',
  });
  // Missing/typeless fields degrade to safe defaults, and an unknown duration
  // stays undefined so the renderer probes for it.
  const bare = clipFromPost({id: 'p2'}, '/tmp/p2.mp4');
  assert.equal(bare.timerSeconds, 0);
  assert.equal(bare.clockOffsetSeconds, 0);
  assert.equal(bare.isLate, false);
  assert.equal(bare.durationSeconds, undefined);
});
