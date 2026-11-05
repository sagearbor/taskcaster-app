'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  houseWrites,
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

test('a non-house entry is refused', () => {
  assert.throws(() => houseWrites([{id: 'x', userId: 'u1', isHouse: false}], new Set()));
});

test('legacyCreatedAt converts ISO strings only', () => {
  assert.deepEqual(legacyCreatedAt('2026-09-01T10:00:00.000Z'), new Date('2026-09-01T10:00:00.000Z'));
  assert.equal(legacyCreatedAt('not a date'), null);
  assert.equal(legacyCreatedAt({seconds: 1}), null);
  assert.equal(legacyCreatedAt(undefined), null);
});
