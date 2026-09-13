'use strict';

// Degrade-don't-fail: when the ffmpeg in use has NO drawtext filter (the
// Homebrew build on this Mac is exactly that, and so was the first Functions
// image), a finale must still render end to end — just without burned-in
// text — and hasDrawtext() must report false so the montage doc can say so.
//
// The env override is set BEFORE the modules load; node:test runs each file
// in its own process, so this cannot leak into the other test files.
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const assert = require('node:assert/strict');

const NO_DRAWTEXT_FFMPEG = '/opt/homebrew/bin/ffmpeg';
const NO_DRAWTEXT_FFPROBE = '/opt/homebrew/bin/ffprobe';
const available = fs.existsSync(NO_DRAWTEXT_FFMPEG) && fs.existsSync(NO_DRAWTEXT_FFPROBE);
if (available) {
  process.env.FFMPEG_PATH = NO_DRAWTEXT_FFMPEG;
  process.env.FFPROBE_PATH = NO_DRAWTEXT_FFPROBE;
}

const {fixtures, workDir} = require('./fixtures');
const montage = require('../src/montage');
const {hasDrawtext} = require('../src/ffmpeg');

test('a drawtext-less ffmpeg still renders a finale (no burned-in text)', {skip: !available && 'no Homebrew ffmpeg here'}, async () => {
  const {execFileSync} = require('node:child_process');
  const filters = execFileSync(NO_DRAWTEXT_FFMPEG, ['-hide_banner', '-filters']).toString();
  if (/\bdrawtext\b/.test(filters)) {
    // Not a valid fixture for this test on this machine; nothing to prove.
    return;
  }
  assert.equal(await hasDrawtext(), false, 'capability probe reports no drawtext');

  const f = await fixtures();
  const out = path.join(workDir('fallback'), 'finale-nodrawtext.mp4');
  const clips = [
    {path: f['loud.mp4'], postId: 'p1', timerSeconds: 30, clockOffsetSeconds: 0},
    {path: f['portrait.mp4'], postId: 'p2', timerSeconds: 60, clockOffsetSeconds: 55},
  ];
  const result = await montage.finale(clips, out, {seconds: 2, taskTitle: 'Egg on a spoon'});
  assert.ok(fs.existsSync(out) && fs.statSync(out).size > 0, 'output written');
  // 0.6 s title + 2 x 2 s + 1 x 0.4 s gap = 5.0 s
  assert.ok(Math.abs(result.durationSeconds - 5.0) < 0.5, `duration ${result.durationSeconds}`);
  assert.equal(result.clipCount, 2);
  const probed = await montage.probe(out);
  assert.equal(probed.width, montage.CANVAS.width);
  assert.equal(probed.height, montage.CANVAS.height);
});
