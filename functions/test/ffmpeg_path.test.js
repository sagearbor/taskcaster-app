'use strict';

// Binary resolution order: $FFMPEG_PATH > functions/bin/ffmpeg (the
// libfreetype build fetched by scripts/fetch_ffmpeg.js) > ffmpeg-static.
//
// The middle entry is the whole point of round 9: the linux-x64 binary that
// ffmpeg-static downloads has no drawtext filter, so every cloud montage
// rendered with no burned-in countdown. These tests pin the precedence and the
// pinned-build metadata so a future edit cannot quietly drop back to
// ffmpeg-static (which would silently return `countdownBurned: false`).

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');
const assert = require('node:assert/strict');

const FFMPEG_JS = require.resolve('../src/ffmpeg');
const BIN = path.join(__dirname, '..', 'bin', 'ffmpeg');

/**
 * Run `body` against a pristine copy of src/ffmpeg.js (it memoises the
 * resolved path) with `env` applied for the duration of the call.
 */
function withFreshFfmpegModule(env, body) {
  const saved = {FFMPEG_PATH: process.env.FFMPEG_PATH, FFPROBE_PATH: process.env.FFPROBE_PATH};
  for (const key of Object.keys(saved)) delete process.env[key];
  Object.assign(process.env, env);
  delete require.cache[FFMPEG_JS];
  try {
    return body(require('../src/ffmpeg'));
  } finally {
    for (const key of Object.keys(saved)) {
      if (saved[key] === undefined) delete process.env[key];
      else process.env[key] = saved[key];
    }
    delete require.cache[FFMPEG_JS];
  }
}

test('FFMPEG_PATH wins over everything else', () => {
  const fake = path.join(os.tmpdir(), 'not-a-real-ffmpeg');
  withFreshFfmpegModule({FFMPEG_PATH: fake}, ({ffmpegPath}) => {
    assert.equal(ffmpegPath(), fake);
  });
});

test('with no override, the bundled freetype build is preferred over ffmpeg-static', () => {
  const resolved = withFreshFfmpegModule({}, ({ffmpegPath}) => ffmpegPath());
  if (fs.existsSync(BIN)) {
    // The runtime case: fetch_ffmpeg.js installed the freetype build.
    assert.equal(resolved, BIN, 'bin/ffmpeg exists but was not chosen');
  } else {
    // Local dev on macOS: fetch_ffmpeg.js skips, ffmpeg-static is the fallback.
    assert.equal(resolved, require('ffmpeg-static'));
  }
});

test('the pinned build is an immutable, digest-verified release asset', () => {
  const source = fs.readFileSync(path.join(__dirname, '..', 'scripts', 'fetch_ffmpeg.js'), 'utf8');
  const url = /url:\s*\n?\s*'([^']+)'\s*\+\s*\n?\s*'([^']+)'/.exec(source);
  assert.ok(url, 'could not find the pinned download URL');
  const full = url[1] + url[2];
  assert.match(full, /^https:\/\/github\.com\/BtbN\/FFmpeg-Builds\/releases\/download\//);
  assert.doesNotMatch(full, /\/latest\//, 'a moving "latest" tag is not reproducible');
  assert.match(full, /autobuild-\d{4}-\d{2}-\d{2}/, 'pin a dated autobuild tag');
  assert.match(source, /sha256:\s*'[0-9a-f]{64}'/, 'the download must be sha256-verified');
});

test('the fetcher never fails an install', () => {
  const source = fs.readFileSync(path.join(__dirname, '..', 'scripts', 'fetch_ffmpeg.js'), 'utf8');
  assert.doesNotMatch(source, /process\.exit\([1-9]/, 'a non-zero exit would break the deploy');
  assert.match(source, /catch\s*\(err\)/, 'download failures must be caught and warned about');
});
