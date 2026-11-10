'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  houseWrites,
  startingGrade,
  legacyCreatedAt,
  loadHousePosts,
  HOUSE_CREATED_AT,
} = require('../scripts/seed_house_posts');

const house = (id, extra = {}) => ({
  id,
  userId: 'house',
  isHouse: true,
  taskId: id.replace('house-', ''),
  text: 'seed copy',
  ...extra,
});

test('house_posts.json loads and every entry is a house post', () => {
  const posts = loadHousePosts();
  assert.ok(posts.length > 0);
  for (const p of posts) {
    assert.equal(p.userId, 'house');
    assert.equal(p.isHouse, true);
    assert.match(p.id, /^house-/);
  }
});

test('a missing house post is created with zeroed counters and the fixed date', () => {
  const [w] = houseWrites([house('house-a')], new Set());
  assert.equal(w.id, 'house-a');
  assert.equal(w.merge, false);
  assert.equal(w.data.gradeCount, 0);
  assert.equal(w.data.gradeSum, 0);
  assert.deepEqual(w.data.graderIds, []);
  assert.equal(w.data.tapCount, 0);
  assert.deepEqual(w.data.tapSeconds, {});
  assert.equal(w.data.boosted, false);
  assert.deepEqual(w.data.createdAt, HOUSE_CREATED_AT);
  assert.equal('id' in w.data, false);
});

test('an existing house post is refreshed by merge, never touching counters', () => {
  const [w] = houseWrites(
    [house('house-a', {gradeCount: 9, graderIds: ['x'], createdAt: 'x', boosted: true})],
    new Set(['house-a']),
  );
  assert.equal(w.merge, true);
  assert.equal(w.data.text, 'seed copy');
  for (const key of ['gradeCount', 'gradeSum', 'graderIds', 'tapCount', 'tapSeconds', 'boosted', 'createdAt']) {
    assert.equal(key in w.data, false, key);
  }
});

test('a missing house post starts with the JSON grade; an existing one keeps its own', () => {
  const posts = [
    house('house-a', {gradeCount: 12, gradeSum: 44}),
    house('house-a-1', {gradeCount: 7, gradeSum: 25}),
  ];
  const [old, fresh] = houseWrites(posts, new Set(['house-a']));
  assert.equal(old.merge, true);
  assert.equal('gradeCount' in old.data, false);
  assert.equal('gradeSum' in old.data, false);
  assert.equal(fresh.merge, false);
  assert.equal(fresh.data.gradeCount, 7);
  assert.equal(fresh.data.gradeSum, 25);
  assert.deepEqual(fresh.data.graderIds, []);
});

test('startingGrade accepts only a sane 1-5 pair', () => {
  assert.deepEqual(startingGrade({gradeCount: 4, gradeSum: 9}), {gradeCount: 4, gradeSum: 9});
  assert.deepEqual(startingGrade({gradeCount: 4, gradeSum: 21}), {gradeCount: 0, gradeSum: 0});
  assert.deepEqual(startingGrade({gradeCount: 4, gradeSum: 3}), {gradeCount: 0, gradeSum: 0});
  assert.deepEqual(startingGrade({gradeCount: -1, gradeSum: 0}), {gradeCount: 0, gradeSum: 0});
  assert.deepEqual(startingGrade({}), {gradeCount: 0, gradeSum: 0});
});

test('house_posts.json: four per starter task, entry 0 keeps the legacy id, no ART on a video', () => {
  const posts = loadHousePosts();
  const byTask = new Map();
  for (const p of posts) {
    if (!byTask.has(p.taskId)) byTask.set(p.taskId, []);
    byTask.get(p.taskId).push(p);
  }
  assert.equal(byTask.size, 10);
  for (const [taskId, list] of byTask) {
    assert.deepEqual(list.map((p) => p.id),
      [`house-${taskId}`, `house-${taskId}-1`, `house-${taskId}-2`, `house-${taskId}-3`]);
    assert.equal(new Set(list.map((p) => p.displayName)).size, 4, taskId);
    assert.equal(new Set(list.map((p) => p.stamp)).size, 4, taskId);
    for (const p of list) {
      if (p.mediaType === 'video') assert.notEqual(p.stamp, 'ART', p.id);
      const start = startingGrade(p);
      assert.ok(start.gradeCount >= 4 && start.gradeCount <= 30, p.id);
    }
  }
  // Re-seeding over a fully seeded store only merges: idempotent.
  const all = new Set(posts.map((p) => p.id));
  assert.ok(houseWrites(posts, all).every((w) => w.merge));
});

test('a non-house entry is refused', () => {
  assert.throws(() => houseWrites([{id: 'x', userId: 'u1', isHouse: false}], new Set()));
});

test('legacyCreatedAt converts ISO strings only', () => {
  assert.deepEqual(legacyCreatedAt('2026-09-01T10:00:00.000Z'), new Date('2026-09-01T10:00:00.000Z'));
  assert.equal(legacyCreatedAt('not a date'), null);
  assert.equal(legacyCreatedAt({seconds: 1}), null);
  assert.equal(legacyCreatedAt(undefined), null);
});
