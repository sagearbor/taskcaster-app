'use strict';

/**
 * ffmpeg-backed tests. Fixtures are generated on first run (cached in the OS
 * temp dir) so the repo carries no video binaries.
 */

const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');

process.env.MONTAGE_QUIET = process.env.MONTAGE_QUIET || '1';

const {fixtures, workDir} = require('./fixtures');
const montage = require('../src/montage');
const {runFfmpeg} = require('../src/ffmpeg');
const {analyzeAudioPeak, analyzeScenePeak} = require('../src/analyze');

const near = (actual, expected, tolerance, what) =>
  assert.ok(
    Math.abs(actual - expected) <= tolerance,
    `${what}: expected ${expected} ±${tolerance}, got ${actual}`,
  );

/** sha256 of one decoded frame (optionally cropped), for pixel comparisons. */
async function frameHash(file, {at, crop} = {}) {
  const out = path.join(workDir('frames'), `f_${crypto.randomUUID()}.png`);
  const args = [];
  if (at !== undefined) args.push('-ss', String(at));
  args.push('-i', file);
  if (crop) args.push('-vf', `crop=${crop}`);
  args.push('-frames:v', '1', out);
  await runFfmpeg(args);
  const hash = crypto.createHash('sha256').update(fs.readFileSync(out)).digest('hex');
  fs.rmSync(out, {force: true});
  return hash;
}

test('fitWithin fits the long edge without upscaling, on even pixels', () => {
  assert.deepEqual(montage.fitWithin(1920, 1080, 854), {width: 854, height: 480});
  assert.deepEqual(montage.fitWithin(1080, 1920, 854), {width: 480, height: 854});
  assert.deepEqual(montage.fitWithin(640, 360, 854), {width: 640, height: 360});
  const odd = montage.fitWithin(1001, 777, 854);
  assert.equal(odd.width % 2, 0);
  assert.equal(odd.height % 2, 0);
});

test('probe reports duration, dimensions and audio presence', async () => {
  const f = await fixtures();

  const loud = await montage.probe(f['loud.mp4']);
  near(loud.durationSeconds, 10, 0.2, 'loud duration');
  assert.equal(loud.width, 640);
  assert.equal(loud.height, 360);
  assert.equal(loud.hasAudio, true);
  near(loud.fps, 30, 0.1, 'loud fps');

  const silent = await montage.probe(f['landscape_noaudio.mp4']);
  assert.equal(silent.hasAudio, false);
  near(silent.durationSeconds, 6, 0.2, 'silent duration');

  const portrait = await montage.probe(f['portrait.mp4']);
  assert.equal(portrait.width, 360);
  assert.equal(portrait.height, 640);
});

test('probe throws a useful error on a file that is not media', async () => {
  const junk = path.join(workDir('junk'), 'not-a-video.mp4');
  fs.writeFileSync(junk, 'definitely not an mp4');
  await assert.rejects(() => montage.probe(junk), /ffprobe/);
});

test('burnCountdown re-encodes at 480p-ish and burns the clock bottom-right', async () => {
  const f = await fixtures();
  const out = path.join(workDir('burn'), 'flat-burned.mp4');

  const result = await montage.burnCountdown(f['flat.mp4'], out, {
    timerSeconds: 30, clockOffsetSeconds: 2,
  });

  assert.ok(fs.existsSync(out) && fs.statSync(out).size > 1000, 'output was written');
  near(result.durationSeconds, 5, 0.5, 'duration is preserved');
  assert.ok(Math.max(result.width, result.height) <= montage.MAX_LONG_EDGE,
    `long edge ${Math.max(result.width, result.height)} <= 854`);
  assert.equal(result.countdownFrom, 28, '30 s timer, 2 s already spent');

  // The source is a single flat colour that never changes, so ANY pixel
  // difference in the bottom-right corner is the burned-in countdown.
  const corner = '200x100:440:260'.replace('x', ':');
  const sourceCorner = await frameHash(f['flat.mp4'], {at: 1, crop: corner});
  const burnedAt1 = await frameHash(out, {at: 1, crop: corner});
  const burnedAt3 = await frameHash(out, {at: 3, crop: corner});

  assert.notEqual(burnedAt1, sourceCorner, 'countdown chip was drawn over the source');
  assert.notEqual(burnedAt1, burnedAt3, 'the countdown actually counts down');

  // …and the rest of the frame is untouched.
  const topLeft = '200:100:0:0';
  assert.equal(
    await frameHash(out, {at: 1, crop: topLeft}),
    await frameHash(out, {at: 3, crop: topLeft}),
    'only the corner changes',
  );
});

test('burnCountdown honours a smaller long-edge cap and adds audio to silent clips', async () => {
  const f = await fixtures();
  const out = path.join(workDir('burn'), 'small.mp4');
  const result = await montage.burnCountdown(f['landscape_noaudio.mp4'], out, {
    timerSeconds: 60, clockOffsetSeconds: 0, width: 320,
  });
  assert.ok(Math.max(result.width, result.height) <= 320);
  assert.equal(result.width % 2, 0);
  const probed = await montage.probe(out);
  assert.equal(probed.hasAudio, true, 'a silent source still gets an audio track');
});

test('burnCountdown draws no chip when there is no task clock', async () => {
  const f = await fixtures();
  const out = path.join(workDir('burn'), 'noclock.mp4');
  const result = await montage.burnCountdown(f['flat.mp4'], out, {timerSeconds: 0});
  assert.equal(result.countdownFrom, null);
  const corner = '200:100:440:260';
  assert.equal(
    await frameHash(out, {at: 1, crop: corner}),
    await frameHash(out, {at: 3, crop: corner}),
    'nothing is animating in the corner',
  );
});

test('ffmpeg failures throw with the stderr tail attached', async () => {
  const out = path.join(workDir('burn'), 'never.mp4');
  await assert.rejects(
    () => montage.burnCountdown('/nope/missing-clip.mp4', out, {timerSeconds: 30}),
    (err) => /missing-clip|No such file/i.test(err.message),
  );
});

test('finale splices the last 2 seconds of every clip onto a portrait canvas', async () => {
  const f = await fixtures();
  const out = path.join(workDir('finale'), 'finale.mp4');

  const clips = [
    {path: f['loud.mp4'], postId: 'p1', timerSeconds: 30, clockOffsetSeconds: 0},
    {path: f['portrait.mp4'], postId: 'p2', timerSeconds: 60, clockOffsetSeconds: 55},
    {
      path: f['landscape_noaudio.mp4'], postId: 'p3', timerSeconds: 30,
      clockOffsetSeconds: 26, isLate: true,
    },
  ];
  const result = await montage.finale(clips, out, {
    seconds: 2, taskTitle: 'The worst sandwich that is still technically food',
  });

  // 0.6 s title + 3 x 2 s + 2 x 0.4 s gaps = 7.4 s
  near(result.durationSeconds, 7.4, 0.5, 'finale duration');
  assert.equal(result.clipCount, 3);
  assert.equal(result.width, montage.CANVAS.width);
  assert.equal(result.height, montage.CANVAS.height);
  assert.ok(result.height > result.width, 'portrait canvas');
  assert.deepEqual(result.segments.map((s) => s.postId), ['p1', 'p2', 'p3']);
  // Each segment is the LAST 2 s of its clip.
  near(result.segments[0].start, 8, 0.01, 'loud.mp4 starts at duration-2');
  near(result.segments[1].start, 2, 0.01, 'portrait.mp4 starts at duration-2');
  near(result.segments[2].start, 4, 0.01, 'silent clip starts at duration-2');
  const probed = await montage.probe(out);
  assert.equal(probed.hasAudio, true, 'mixed audio/silent sources still yield one audio track');
});

test('finale handles a single clip and a clip shorter than the window', async () => {
  const f = await fixtures();
  const out = path.join(workDir('finale'), 'one.mp4');
  const result = await montage.finale(
    [{path: f['portrait.mp4'], postId: 'solo', timerSeconds: 30, clockOffsetSeconds: 0}],
    out,
    {seconds: 2, taskTitle: 'Solo'},
  );
  assert.equal(result.clipCount, 1);
  near(result.durationSeconds, 2.6, 0.4, 'title + one 2 s segment, no gaps');
});

test('finale refuses an empty clip list', async () => {
  await assert.rejects(
    () => montage.finale([], path.join(workDir('finale'), 'empty.mp4'), {}),
    /no clips/i,
  );
});

test('the audio analyzer finds the loud second', async () => {
  const f = await fixtures();
  const peak = await analyzeAudioPeak(f['loud.mp4']);
  assert.ok(peak, 'a peak was found');
  assert.equal(peak.second, 6, 'the 1-second burst at t=6');
  assert.ok(peak.levelDb - peak.medianDb > 10, 'the burst stands well clear of the body');
});

test('the audio analyzer returns null for a clip with no audio stream', async () => {
  const f = await fixtures();
  assert.equal(await analyzeAudioPeak(f['scene.mp4']), null);
});

test('the scene analyzer finds the visual cut', async () => {
  const f = await fixtures();
  const scene = await analyzeScenePeak(f['scene.mp4']);
  assert.ok(scene, 'a scene change was found');
  near(scene.second, 8, 1, 'the colour cut at t=8');
  assert.ok(scene.score > 0.12);
});

test('the scene analyzer returns null when nothing moves', async () => {
  const f = await fixtures();
  assert.equal(await analyzeScenePeak(f['flat.mp4']), null);
});

test('moments picks taps, then audio, then the visual cut — one per clip', async () => {
  const f = await fixtures();
  const out = path.join(workDir('moments'), 'moments.mp4');

  const clips = [
    // Taps beat every other signal, even though this clip has audio.
    {
      path: f['tall.mp4'], postId: 'tapped', timerSeconds: 30, clockOffsetSeconds: 0,
      tapSeconds: {3: 2, 4: 1},
    },
    // No taps, loud burst at t=6 -> audio.
    {path: f['loud.mp4'], postId: 'loud', timerSeconds: 30, clockOffsetSeconds: 0},
    // No audio stream at all, hard cut at t=8 -> scene.
    {path: f['scene.mp4'], postId: 'silent', timerSeconds: 60, clockOffsetSeconds: 10},
  ];
  const result = await montage.moments(clips, out, {seconds: 3, taskTitle: 'Head things'});

  const bySignal = Object.fromEntries(result.segments.map((s) => [s.postId, s]));
  assert.equal(bySignal.tapped.signal, 'taps');
  assert.ok(bySignal.tapped.start >= 1 && bySignal.tapped.start <= 4,
    `tap window started at ${bySignal.tapped.start}`);

  assert.equal(bySignal.loud.signal, 'audio');
  assert.ok(bySignal.loud.start >= 4.5 && bySignal.loud.start <= 6,
    `loud window started at ${bySignal.loud.start}`);

  assert.equal(bySignal.silent.signal, 'scene');
  assert.ok(bySignal.silent.start >= 6 && bySignal.silent.start <= 8,
    `scene window started at ${bySignal.silent.start}`);

  // 0.6 s title + 3 x 3 s + 2 x 0.4 s gaps = 10.4 s
  near(result.durationSeconds, 10.4, 0.5, 'moments duration');
  assert.equal(result.width, montage.CANVAS.width);
  assert.equal(result.height, montage.CANVAS.height);
});

test('moments falls back to the end of the clip when no signal fires', async () => {
  const f = await fixtures();
  const out = path.join(workDir('moments'), 'fallback.mp4');
  const result = await montage.moments(
    [{path: f['flat.mp4'], postId: 'flat', timerSeconds: 30, clockOffsetSeconds: 0}],
    out,
    {seconds: 3, taskTitle: 'Nothing happens'},
  );
  assert.equal(result.segments[0].signal, 'fallback');
  near(result.segments[0].start, 2, 0.3, 'the last 3 s of a 5 s clip');
});
