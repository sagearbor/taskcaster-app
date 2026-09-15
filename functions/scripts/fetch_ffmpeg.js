'use strict';

/**
 * Fetch a libfreetype-enabled static ffmpeg into `functions/bin/`.
 *
 * WHY THIS EXISTS
 * ---------------
 * The montage pipeline burns a countdown clock into the bottom-right of every
 * clip and renders a title card for the finale. Both are `drawtext` filters,
 * and `drawtext` only exists in an ffmpeg built with libfreetype. The binary
 * that `ffmpeg-static` downloads for linux-x64 is built WITHOUT it, so every
 * cloud render silently degraded to "no burned-in text" (montage docs recorded
 * `countdownBurned: false`). See tmp/wrapups/20260913-0045-*.yaml, findings.
 *
 * This script runs as an npm `postinstall`, which means it runs inside the
 * Cloud Build step that packages the function (the same mechanism
 * `ffmpeg-static` itself uses to fetch its binary), so the freetype build ends
 * up in the deployed image without being committed to git.
 *
 * WHY THIS BUILD
 * --------------
 * BtbN/FFmpeg-Builds, pinned to a dated autobuild tag. GitHub release assets on
 * a dated tag are immutable and GitHub publishes the sha256 we verify against,
 * so this fetch is reproducible indefinitely. Two alternatives were rejected:
 *   - `@ffmpeg-installer/linux-x64` (a one-line dependency, freetype enabled)
 *     ships ffmpeg 4.1 from December 2018. This binary parses untrusted
 *     user-uploaded video, so a five-year downgrade from the ffmpeg 6.x running
 *     today is the wrong trade.
 *   - johnvansickle's `ffmpeg-release-amd64-static.tar.xz` is half the size and
 *     freetype-enabled, but the URL is a moving "latest" pointer: the pinned
 *     sha256 would break the day upstream publishes a new patch release.
 *
 * FAILURE BEHAVIOUR
 * -----------------
 * Never fails the install. On any error (no network, missing `xz`, hash
 * mismatch) it warns and leaves `bin/` empty; `src/ffmpeg.js` then falls back
 * to `ffmpeg-static` and rendering degrades exactly as it does today rather
 * than breaking the deploy. `countdownBurned` on the montage doc is the signal
 * that says which path actually ran.
 */

const crypto = require('crypto');
const fs = require('fs');
const https = require('https');
const os = require('os');
const path = require('path');
const {execFileSync} = require('child_process');

const BUILD = {
  url:
    'https://github.com/BtbN/FFmpeg-Builds/releases/download/autobuild-2026-09-14-13-17/' +
    'ffmpeg-n8.1.2-52-g5a03dfa0f6-linux64-gpl-8.1.tar.xz',
  sha256: '0a0c3002405807439bf558fab62f70ba4c958ff1fef8cb2676be75a9aab2e0b4',
  member: 'ffmpeg-n8.1.2-52-g5a03dfa0f6-linux64-gpl-8.1/bin/ffmpeg',
};

const BIN_DIR = path.join(__dirname, '..', 'bin');
const TARGET = path.join(BIN_DIR, 'ffmpeg');

function warn(message) {
  process.stdout.write(`[fetch-ffmpeg] ${message}\n`);
}

/** GET with redirect following (GitHub release assets redirect to a CDN). */
function download(url, dest, redirectsLeft = 5) {
  return new Promise((resolve, reject) => {
    https
      .get(url, {headers: {'user-agent': 'taskcaster-functions'}}, (res) => {
        const {statusCode, headers} = res;
        if (statusCode >= 300 && statusCode < 400 && headers.location) {
          res.resume();
          if (redirectsLeft === 0) return reject(new Error('too many redirects'));
          return resolve(download(new URL(headers.location, url).toString(), dest, redirectsLeft - 1));
        }
        if (statusCode !== 200) {
          res.resume();
          return reject(new Error(`HTTP ${statusCode} for ${url}`));
        }
        const hash = crypto.createHash('sha256');
        const file = fs.createWriteStream(dest);
        res.on('data', (chunk) => hash.update(chunk));
        res.pipe(file);
        file.on('error', reject);
        file.on('finish', () => file.close(() => resolve(hash.digest('hex'))));
      })
      .on('error', reject);
  });
}

async function main() {
  if (process.platform !== 'linux' || process.arch !== 'x64') {
    // Local dev (macOS/arm64) keeps using ffmpeg-static or $FFMPEG_PATH.
    warn(`skipping on ${process.platform}/${process.arch}; only the linux-x64 runtime needs this build`);
    return;
  }
  if (fs.existsSync(TARGET) && fs.statSync(TARGET).size > 1024 * 1024) {
    warn('bin/ffmpeg already present, skipping download');
    return;
  }

  const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'ffmpeg-fetch-'));
  const tarball = path.join(scratch, 'ffmpeg.tar.xz');
  try {
    warn(`downloading ${BUILD.url}`);
    const digest = await download(BUILD.url, tarball);
    if (digest !== BUILD.sha256) {
      throw new Error(`sha256 mismatch: got ${digest}, expected ${BUILD.sha256}`);
    }
    warn('sha256 verified; extracting ffmpeg');
    // `--strip-components=2` drops "<release>/bin/" so the file lands as ./ffmpeg.
    execFileSync('tar', ['-xJf', tarball, '-C', scratch, '--strip-components=2', BUILD.member], {
      stdio: 'inherit',
    });
    fs.mkdirSync(BIN_DIR, {recursive: true});
    fs.copyFileSync(path.join(scratch, 'ffmpeg'), TARGET);
    fs.chmodSync(TARGET, 0o755);
    warn(`installed ${TARGET} (${fs.statSync(TARGET).size} bytes)`);
  } catch (err) {
    warn(`FAILED (${err.message}); falling back to ffmpeg-static, montages will have no burned-in text`);
  } finally {
    fs.rmSync(scratch, {recursive: true, force: true});
  }
}

main().catch((err) => {
  warn(`unexpected error: ${err && err.message}`);
});
