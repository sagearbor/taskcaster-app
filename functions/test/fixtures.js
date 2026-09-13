'use strict';

/**
 * Test fixtures, generated with ffmpeg itself so the repo carries no binaries.
 *
 * They are cached in a stable temp directory, so a second `npm test` run skips
 * the (slow) generation step. Set FIXTURES_FRESH=1 to rebuild.
 */

const fs = require('fs');
const os = require('os');
const path = require('path');

const {runFfmpeg} = require('../src/ffmpeg');

const DIR = path.join(os.tmpdir(), 'taskcaster-montage-fixtures-v2');

const V = ['-c:v', 'libx264', '-preset', 'veryfast', '-crf', '22', '-pix_fmt', 'yuv420p'];
const A = ['-c:a', 'aac', '-b:a', '96k', '-ar', '44100', '-ac', '2'];

/**
 * `loud.mp4` — 10 s landscape 640x360 with a LOUD 1-second burst at t=6.
 * The rest of the clip is a quiet tone, so the audio analyzer has an obvious
 * peak to find.
 */
async function makeLoud(out) {
  await runFfmpeg([
    '-f', 'lavfi', '-i', 'testsrc2=s=640x360:r=30:d=10',
    '-f', 'lavfi', '-i', 'sine=f=300:r=44100:d=10',
    '-filter_complex', "[1:a]volume='if(between(t\\,6\\,7)\\,1.0\\,0.02)':eval=frame[a]",
    '-map', '0:v', '-map', '[a]', '-t', '10', ...V, ...A, out,
  ]);
}

/**
 * `scene.mp4` — 10 s portrait 320x400, NO audio, a hard colour cut at t=8.
 * Forces the pipeline past the audio signal and onto the scene signal.
 */
async function makeScene(out) {
  await runFfmpeg([
    '-f', 'lavfi', '-i', 'color=c=0x1133AA:s=320x400:r=15:d=8',
    '-f', 'lavfi', '-i', 'color=c=0xDD3311:s=320x400:r=15:d=2',
    '-filter_complex', '[0:v][1:v]concat=n=2:v=1:a=0[v]',
    '-map', '[v]', '-an', '-t', '10', ...V, out,
  ]);
}

/** `portrait.mp4` — 4 s portrait 360x640 with audio. */
async function makePortrait(out) {
  await runFfmpeg([
    '-f', 'lavfi', '-i', 'testsrc2=s=360x640:r=30:d=4',
    '-f', 'lavfi', '-i', 'sine=f=440:r=44100:d=4',
    '-map', '0:v', '-map', '1:a', '-t', '4', ...V, ...A, out,
  ]);
}

/** `landscape_noaudio.mp4` — 6 s landscape 640x360, no audio stream at all. */
async function makeLandscapeNoAudio(out) {
  await runFfmpeg([
    '-f', 'lavfi', '-i', 'testsrc2=s=640x360:r=30:d=6',
    '-an', '-t', '6', ...V, out,
  ]);
}

/**
 * `flat.mp4` — 5 s of a single solid colour with silent audio. Nothing in the
 * frame ever changes, so any pixel difference in an output comes from the
 * burned-in overlay and nothing else.
 */
async function makeFlat(out) {
  await runFfmpeg([
    '-f', 'lavfi', '-i', 'color=c=0x2E7D32:s=640x360:r=30:d=5',
    '-f', 'lavfi', '-i', 'anullsrc=channel_layout=stereo:sample_rate=44100',
    '-map', '0:v', '-map', '1:a', '-t', '5', ...V, ...A, out,
  ]);
}

/** `tall.mp4` — 8 s portrait 480x854 with audio, used for the tap window. */
async function makeTall(out) {
  await runFfmpeg([
    '-f', 'lavfi', '-i', 'testsrc2=s=480x854:r=30:d=8',
    '-f', 'lavfi', '-i', 'sine=f=220:r=44100:d=8',
    '-map', '0:v', '-map', '1:a', '-t', '8', ...V, ...A, out,
  ]);
}

const BUILDERS = {
  'loud.mp4': makeLoud,
  'scene.mp4': makeScene,
  'portrait.mp4': makePortrait,
  'landscape_noaudio.mp4': makeLandscapeNoAudio,
  'flat.mp4': makeFlat,
  'tall.mp4': makeTall,
};

let ready = null;

/**
 * Build (or reuse) every fixture.
 * @returns {Promise<Record<string, string>>} name -> absolute path
 */
function fixtures() {
  if (ready) return ready;
  ready = (async () => {
    if (process.env.FIXTURES_FRESH === '1') fs.rmSync(DIR, {recursive: true, force: true});
    fs.mkdirSync(DIR, {recursive: true});
    const paths = {};
    for (const [name, build] of Object.entries(BUILDERS)) {
      const out = path.join(DIR, name);
      if (!fs.existsSync(out) || fs.statSync(out).size === 0) {
        // eslint-disable-next-line no-await-in-loop
        await build(out);
      }
      paths[name] = out;
    }
    return paths;
  })();
  return ready;
}

/** A scratch directory for a single test file's outputs. */
function workDir(name) {
  const dir = path.join(DIR, 'out', name);
  fs.mkdirSync(dir, {recursive: true});
  return dir;
}

module.exports = {fixtures, workDir, FIXTURE_DIR: DIR};
