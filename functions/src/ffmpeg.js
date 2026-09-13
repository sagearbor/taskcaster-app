'use strict';

/**
 * ffmpeg / ffprobe binary resolution and process running.
 *
 * Binary choice, in order:
 *   1. `FFMPEG_PATH` / `FFPROBE_PATH` env vars (local overrides, e.g.
 *      /opt/homebrew/bin/ffmpeg).
 *   2. The `ffmpeg-static` / `ffprobe-static` npm packages, which is what runs
 *      in Cloud Functions.
 *
 * NOTE: Homebrew's ffmpeg is frequently built WITHOUT libfreetype, which means
 * no `drawtext` filter and therefore no burned-in countdown. `assertDrawtext()`
 * gives a clear error instead of a cryptic ffmpeg one.
 */

const {spawn} = require('child_process');
const {log} = require('./log');

let cachedFfmpeg = null;
let cachedFfprobe = null;

function ffmpegPath() {
  if (process.env.FFMPEG_PATH) return process.env.FFMPEG_PATH;
  if (cachedFfmpeg) return cachedFfmpeg;
  cachedFfmpeg = require('ffmpeg-static');
  if (!cachedFfmpeg) {
    throw new Error('ffmpeg binary not found: set FFMPEG_PATH or install ffmpeg-static');
  }
  return cachedFfmpeg;
}

function ffprobePath() {
  if (process.env.FFPROBE_PATH) return process.env.FFPROBE_PATH;
  if (cachedFfprobe) return cachedFfprobe;
  const mod = require('ffprobe-static');
  cachedFfprobe = typeof mod === 'string' ? mod : mod.path;
  if (!cachedFfprobe) {
    throw new Error('ffprobe binary not found: set FFPROBE_PATH or install ffprobe-static');
  }
  return cachedFfprobe;
}

/** Tail of a stderr blob, for error messages that stay readable in logs. */
function tail(text, lines = 20) {
  const rows = String(text || '').trim().split('\n');
  return rows.slice(-lines).join('\n');
}

/**
 * Run a binary, capturing stdout/stderr. Logs the full command line first so a
 * failure can be reproduced by hand from the Cloud Logging entry.
 *
 * @returns {Promise<{stdout: string, stderr: string}>}
 */
function runBinary(bin, args, {label = 'ffmpeg', timeoutMs = 480000} = {}) {
  log(`[${label}] ${bin} ${args.map(quoteForLog).join(' ')}`);
  return new Promise((resolve, reject) => {
    const child = spawn(bin, args, {stdio: ['ignore', 'pipe', 'pipe']});
    let stdout = '';
    let stderr = '';
    let timedOut = false;
    const timer = setTimeout(() => {
      timedOut = true;
      child.kill('SIGKILL');
    }, timeoutMs);

    child.stdout.on('data', (d) => {
      stdout += d.toString();
    });
    child.stderr.on('data', (d) => {
      stderr += d.toString();
      // Keep memory bounded on very chatty runs (astats/showinfo).
      if (stderr.length > 4 * 1024 * 1024) stderr = stderr.slice(-1024 * 1024);
    });
    child.on('error', (err) => {
      clearTimeout(timer);
      reject(new Error(`[${label}] failed to spawn ${bin}: ${err.message}`));
    });
    child.on('close', (code) => {
      clearTimeout(timer);
      if (timedOut) {
        reject(new Error(`[${label}] timed out after ${timeoutMs} ms\n${tail(stderr)}`));
        return;
      }
      if (code !== 0) {
        reject(new Error(`[${label}] exited ${code}\ncmd: ${bin} ${args.join(' ')}\n${tail(stderr)}`));
        return;
      }
      resolve({stdout, stderr});
    });
  });
}

function quoteForLog(arg) {
  return /[\s'"$]/.test(arg) ? `'${arg.replace(/'/g, "'\\''")}'` : arg;
}

const runFfmpeg = (args, opts = {}) =>
  runBinary(ffmpegPath(), ['-hide_banner', '-nostdin', '-y', ...args], {label: 'ffmpeg', ...opts});

const runFfprobe = (args, opts = {}) =>
  runBinary(ffprobePath(), ['-hide_banner', ...args], {label: 'ffprobe', ...opts});

let drawtextChecked = null;

/** Throws a helpful error when the resolved ffmpeg has no `drawtext` filter. */
async function assertDrawtext() {
  if (drawtextChecked !== null) {
    if (drawtextChecked) return;
    throw new Error(
      `ffmpeg at ${ffmpegPath()} has no drawtext filter (built without libfreetype). ` +
        'Unset FFMPEG_PATH to use the bundled ffmpeg-static binary.',
    );
  }
  const {stdout} = await runBinary(ffmpegPath(), ['-hide_banner', '-filters'], {label: 'ffmpeg-caps'});
  drawtextChecked = /\bdrawtext\b/.test(stdout);
  if (!drawtextChecked) return assertDrawtext();
  return undefined;
}

/**
 * Whether the ffmpeg in use can draw text. Cached after the first probe.
 * The renderers use this to DEGRADE rather than fail: without drawtext the
 * montage is still produced, just without the burned-in countdown / title
 * text (the app overlays the countdown client-side), and the montage doc
 * records `countdownBurned: false` so the gap is visible.
 * @returns {Promise<boolean>}
 */
async function hasDrawtext() {
  if (drawtextChecked !== null) return drawtextChecked;
  let stdout = '';
  let stderr = '';
  try {
    ({stdout, stderr} = await runBinary(ffmpegPath(), ['-hide_banner', '-filters'], {label: 'ffmpeg-caps'}));
  } catch (err) {
    log(`[ffmpeg-caps] probe failed: ${err.message}`);
    stdout = '';
  }
  drawtextChecked = /\bdrawtext\b/.test(stdout);
  if (!drawtextChecked) {
    log(
      `[ffmpeg-caps] no drawtext filter in ${ffmpegPath()}; rendering WITHOUT burned-in text. ` +
        `filters head: ${stdout.slice(0, 300).replace(/\s+/g, ' ')} | stderr: ${(stderr || '').slice(0, 300)}`,
    );
  }
  return drawtextChecked;
}

module.exports = {
  ffmpegPath,
  ffprobePath,
  runFfmpeg,
  runFfprobe,
  runBinary,
  assertDrawtext,
  hasDrawtext,
  tail,
};
