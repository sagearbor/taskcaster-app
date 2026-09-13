'use strict';

// Montage scope: Starter Pack tasks are rendered across every player's solo
// game (scope 'starter'); game tasks are scoped to their game. The Dart side
// (Montage.idFor) applies the identical rule, so these ids are a contract.
const test = require('node:test');
const assert = require('node:assert/strict');

const {montageDocId, montageScope, isStarterTask, STARTER_SCOPE} = require('../src/contract');

test('starter tasks scope to the literal starter, regardless of game', () => {
  assert.equal(isStarterTask('starter-01-v2'), true);
  assert.equal(isStarterTask('starter-03'), true);
  assert.equal(isStarterTask('task-7'), false);
  assert.equal(isStarterTask(undefined), false);
  assert.equal(montageScope('game-a', 'starter-01-v2'), STARTER_SCOPE);
  assert.equal(montageScope('game-b', 'starter-01-v2'), STARTER_SCOPE);
  assert.equal(montageDocId('game-a', 'starter-01-v2'), 'starter_starter-01-v2');
  assert.equal(montageDocId('game-b', 'starter-01-v2'), montageDocId('game-a', 'starter-01-v2'));
});

test('game tasks keep their game scope', () => {
  assert.equal(montageScope('game-a', 'task-7'), 'game-a');
  assert.equal(montageDocId('game-a', 'task-7'), 'game-a_task-7');
  assert.notEqual(montageDocId('game-a', 'task-7'), montageDocId('game-b', 'task-7'));
});
