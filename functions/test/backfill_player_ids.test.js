'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {playerIdsFor, backfillPlan} = require('../scripts/backfill_player_ids');

const player = (userId) => ({userId, displayName: userId, totalScore: 0});

test('derives playerIds from players[] in roster order', () => {
  assert.deepEqual(playerIdsFor({players: [player('a'), player('b')]}), ['a', 'b']);
});

test('leaves a game that already has playerIds alone (idempotent)', () => {
  assert.equal(playerIdsFor({players: [player('a')], playerIds: ['a']}), null);
  assert.equal(playerIdsFor({players: [player('a')], playerIds: []}), null);
});

test('drops duplicates and malformed entries; no players gives []', () => {
  assert.deepEqual(
    playerIdsFor({players: [player('a'), null, {displayName: 'x'}, player('a'), player('b')]}),
    ['a', 'b'],
  );
  assert.deepEqual(playerIdsFor({}), []);
});

test('backfillPlan lists only the games that need it', () => {
  const plan = backfillPlan([
    {id: 'legacy', data: {players: [player('a'), player('b')]}},
    {id: 'modern', data: {players: [player('c')], playerIds: ['c']}},
  ]);
  assert.deepEqual(plan, [{id: 'legacy', playerIds: ['a', 'b']}]);
});
