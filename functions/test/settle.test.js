'use strict';

/**
 * The trigger's settle logic, exercised end to end against an in-memory
 * montage document and a MOCKED render — no Firebase, no ffmpeg.
 *
 * This is the same pair of pure functions `onFeedPostCreated` and
 * `renderPendingMontages` use (`applyNewPost` + `decideRender`), so the rules
 * being asserted here are the rules that ship.
 */

const test = require('node:test');
const assert = require('node:assert/strict');

const {applyNewPost, decideRender} = require('../src/contract');

const MINUTE = 60000;

/** A tiny stand-in for the montage document + the trigger around it. */
function makeTaskQueue(startMs) {
  let doc = null;
  let clock = startMs;
  const renders = [];
  const render = () => {
    renders.push({at: clock, pendingCount: doc.pendingCount});
    doc = {
      ...doc,
      status: 'ready',
      version: (doc.version || 0) + 1,
      clipCount: doc.pendingCount,
      pendingCount: 0,
      pendingSince: null,
      lockedAt: null,
    };
  };

  return {
    get doc() {
      return doc;
    },
    renders,
    advance(minutes) {
      clock += minutes * MINUTE;
    },
    /** `onFeedPostCreated` for one video post. */
    post(overrides = {}) {
      const nowIso = new Date(clock).toISOString();
      const update = applyNewPost(doc, {
        gameId: 'g1', taskId: 'starter-05', taskTitle: 'The worst sandwich', ...overrides,
      }, nowIso);
      doc = {...(doc || {}), ...update};
      const decision = decideRender(doc, clock);
      if (decision.render) render();
      return decision;
    },
    /** One tick of `renderPendingMontages`. */
    tick() {
      const decision = decideRender(doc, clock);
      if (decision.render) render();
      return decision;
    },
  };
}

test('three video posts render the montage immediately', () => {
  const q = makeTaskQueue(Date.parse('2026-09-12T12:00:00.000Z'));
  assert.equal(q.post().reason, 'waiting');
  assert.equal(q.renders.length, 0);
  assert.equal(q.post().reason, 'waiting');
  assert.equal(q.renders.length, 0);

  const third = q.post();
  assert.deepEqual(third, {render: true, reason: 'threshold'});
  assert.equal(q.renders.length, 1);
  assert.equal(q.renders[0].pendingCount, 3);
  assert.equal(q.doc.status, 'ready');
  assert.equal(q.doc.version, 1);
  assert.equal(q.doc.clipCount, 3);
});

test('fewer than three posts stay pending until the 30-minute settle window', () => {
  const q = makeTaskQueue(Date.parse('2026-09-12T12:00:00.000Z'));
  q.post();
  q.post();
  assert.equal(q.doc.status, 'pending');
  assert.equal(q.doc.pendingCount, 2);

  q.advance(29);
  assert.deepEqual(q.tick(), {render: false, reason: 'waiting'});
  assert.equal(q.renders.length, 0);

  q.advance(1); // 30 minutes since the FIRST of the two posts
  assert.deepEqual(q.tick(), {render: true, reason: 'settled'});
  assert.equal(q.renders.length, 1);
  assert.equal(q.renders[0].pendingCount, 2);
});

test('the scheduler is a no-op once a montage is ready', () => {
  const q = makeTaskQueue(Date.parse('2026-09-12T12:00:00.000Z'));
  q.post();
  q.post();
  q.post();
  assert.equal(q.renders.length, 1);
  for (let i = 0; i < 6; i += 1) {
    q.advance(10);
    assert.deepEqual(q.tick(), {render: false, reason: 'not-pending'});
  }
  assert.equal(q.renders.length, 1);
});

test('a late fourth post re-opens the window and re-renders after the settle', () => {
  const q = makeTaskQueue(Date.parse('2026-09-12T12:00:00.000Z'));
  q.post();
  q.post();
  q.post();
  assert.equal(q.doc.version, 1);

  q.advance(45);
  assert.equal(q.post().reason, 'waiting');
  assert.equal(q.doc.status, 'pending');
  assert.equal(q.doc.pendingCount, 1);

  q.advance(31);
  assert.deepEqual(q.tick(), {render: true, reason: 'settled'});
  assert.equal(q.renders.length, 2);
  assert.equal(q.doc.version, 2);
});

test('pendingSince is pinned to the first post of a window, not the latest', () => {
  const start = Date.parse('2026-09-12T12:00:00.000Z');
  const q = makeTaskQueue(start);
  q.post();
  q.advance(20);
  q.post();
  assert.equal(Date.parse(q.doc.pendingSince), start);
  q.advance(10); // 30 min since the first post, only 10 since the second
  assert.equal(q.tick().render, true);
});

test('applyNewPost seeds a brand-new montage doc with contract defaults', () => {
  const update = applyNewPost(null, {
    gameId: 'g1', taskId: 'starter-01', taskTitle: 'Egg on a spoon',
  }, '2026-09-12T12:00:00.000Z');
  assert.deepEqual(update, {
    gameId: 'g1',
    taskId: 'starter-01',
    taskTitle: 'Egg on a spoon',
    status: 'pending',
    pendingCount: 1,
    pendingSince: '2026-09-12T12:00:00.000Z',
    updatedAt: '2026-09-12T12:00:00.000Z',
    version: 0,
    clipCount: 0,
    sourcePostIds: [],
  });
  // An existing doc is not re-seeded.
  const second = applyNewPost({...update, version: 3}, {gameId: 'g1', taskId: 'starter-01'},
    '2026-09-12T12:05:00.000Z');
  assert.equal(second.version, undefined);
  assert.equal(second.pendingCount, 2);
  assert.equal(second.pendingSince, '2026-09-12T12:00:00.000Z');
  assert.equal(second.taskTitle, 'Egg on a spoon');
});
