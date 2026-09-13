'use strict';

/**
 * `pickHighlight`'s decision logic, with MOCKED analyzers so the signal
 * priority is tested without ffmpeg. The real analyzers get their own
 * (ffmpeg-backed) assertions in montage.test.js.
 */

const test = require('node:test');
const assert = require('node:assert/strict');

const {tapWindow, pickHighlight} = require('../src/analyze');

const neverAudio = async () => null;
const neverScene = async () => null;
const audioAt = (second) => async () => ({second, levelDb: -8, medianDb: -40});
const sceneAt = (second) => async () => ({second, at: second, score: 0.5});

test('tapWindow needs a bucket with at least two taps', () => {
  assert.equal(tapWindow({3: 1}, {durationSeconds: 10}), null);
  assert.equal(tapWindow({3: 1, 7: 1}, {durationSeconds: 10}), null);
  assert.ok(tapWindow({3: 2}, {durationSeconds: 10}));
});

test('tapWindow finds the densest three-second window', () => {
  const window = tapWindow({1: 1, 6: 3, 7: 2, 12: 1}, {seconds: 3, durationSeconds: 15});
  assert.equal(window.taps, 5);
  assert.ok(window.start >= 5 && window.start <= 6, `start was ${window.start}`);
  assert.equal(window.center, window.start + 1.5);
});

test('tapWindow ignores junk input', () => {
  assert.equal(tapWindow(null, {}), null);
  assert.equal(tapWindow({}, {}), null);
  assert.equal(tapWindow('nope', {}), null);
  assert.equal(tapWindow({abc: 5}, {}), null);
  assert.equal(tapWindow({'-2': 5}, {}), null);
});

test('pickHighlight prefers taps over every other signal', async () => {
  const pick = await pickHighlight(
    {path: 'x.mp4', durationSeconds: 12, tapSeconds: {8: 3}},
    {seconds: 3, analyzeAudio: audioAt(1), analyzeScene: sceneAt(2)},
  );
  assert.equal(pick.signal, 'taps');
  assert.ok(pick.start >= 6 && pick.start <= 9, `start was ${pick.start}`);
});

test('pickHighlight falls to audio when taps are absent or too sparse', async () => {
  for (const tapSeconds of [undefined, {4: 1}]) {
    // eslint-disable-next-line no-await-in-loop
    const pick = await pickHighlight(
      {path: 'x.mp4', durationSeconds: 12, tapSeconds},
      {seconds: 3, analyzeAudio: audioAt(6), analyzeScene: sceneAt(2)},
    );
    assert.equal(pick.signal, 'audio');
    assert.equal(pick.center, 6.5);
    assert.equal(pick.start, 5);
  }
});

test('pickHighlight falls to the scene signal when there is no usable audio', async () => {
  const pick = await pickHighlight(
    {path: 'x.mp4', durationSeconds: 12},
    {seconds: 3, analyzeAudio: neverAudio, analyzeScene: sceneAt(8)},
  );
  assert.equal(pick.signal, 'scene');
  assert.equal(pick.start, 6.5);
});

test('pickHighlight skips the audio pass entirely for a silent clip', async () => {
  let audioCalls = 0;
  const pick = await pickHighlight(
    {path: 'x.mp4', durationSeconds: 12, hasAudio: false},
    {
      seconds: 3,
      analyzeAudio: async () => {
        audioCalls += 1;
        return {second: 1};
      },
      analyzeScene: sceneAt(9),
    },
  );
  assert.equal(audioCalls, 0);
  assert.equal(pick.signal, 'scene');
});

test('pickHighlight falls back to the end of the clip — where the reveal is', async () => {
  const pick = await pickHighlight(
    {path: 'x.mp4', durationSeconds: 12},
    {seconds: 3, analyzeAudio: neverAudio, analyzeScene: neverScene},
  );
  assert.equal(pick.signal, 'fallback');
  assert.equal(pick.start, 9);
  assert.equal(pick.center, 10.5);
});

test('pickHighlight clamps the window inside the clip', async () => {
  const nearEnd = await pickHighlight(
    {path: 'x.mp4', durationSeconds: 6},
    {seconds: 3, analyzeAudio: audioAt(5), analyzeScene: neverScene},
  );
  assert.equal(nearEnd.start, 3, 'cannot run past the end');

  const nearStart = await pickHighlight(
    {path: 'x.mp4', durationSeconds: 6},
    {seconds: 3, analyzeAudio: audioAt(0), analyzeScene: neverScene},
  );
  assert.equal(nearStart.start, 0, 'cannot start before zero');

  const tooShort = await pickHighlight(
    {path: 'x.mp4', durationSeconds: 1.5},
    {seconds: 3, analyzeAudio: audioAt(0), analyzeScene: neverScene},
  );
  assert.equal(tooShort.start, 0);
});
