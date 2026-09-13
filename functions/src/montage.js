'use strict';

/**
 * The montage library. Pure ffmpeg + fs — no Firebase imports — so every step
 * is unit-testable on a laptop.
 *
 * Two products per task:
 *   `finale(clips)`  — the LAST 2 seconds of every clip, back to back. The
 *                      starter tasks are written so the last 2 s are the
 *                      reveal, which is exactly what the owner asked for.
 *   `moments(clips)` — one 3-second highlight per clip, chosen automatically
 *                      from viewer taps, then audio loudness, then visual
 *                      change, then the end of the clip.
 *
 * Both burn the TASK-CLOCK countdown into the bottom-right of every frame.
 */

const fs = require('fs');
const os = require('os');
const path = require('path');

const {runFfmpeg, hasDrawtext} = require('./ffmpeg');
const {probe, pickHighlight} = require('./analyze');
const {countdownSpec, FONT_FILE} = require('./countdown');
const {writeRoundedRectPng} = require('./badge');
const {fitText, drawtextLines} = require('./text');
const {log} = require('./log');

/** Portrait 4:5 canvas — matches the in-app feed and the house clips. */
const CANVAS = {width: 480, height: 600, fps: 30};

/** Max long edge for a single re-encoded clip (480p-ish, per VideoPolicy). */
const MAX_LONG_EDGE = 854;

const TITLE_SECONDS = 0.6;
const GAP_SECONDS = 0.4;

const VIDEO_ARGS = [
  '-c:v', 'libx264',
  '-profile:v', 'high',
  '-level', '3.1',
  '-preset', 'veryfast',
  '-crf', '24',
  '-pix_fmt', 'yuv420p',
  '-movflags', '+faststart',
];

const AUDIO_ARGS = ['-c:a', 'aac', '-b:a', '96k', '-ar', '44100', '-ac', '2'];

const SILENT_INPUT = ['-f', 'lavfi', '-i', 'anullsrc=channel_layout=stereo:sample_rate=44100'];

/** Round up to an even number (H.264 with yuv420p needs even dimensions). */
const even = (n) => Math.max(2, Math.round(n / 2) * 2);

function makeTmpDir(prefix) {
  return fs.mkdtempSync(path.join(os.tmpdir(), prefix));
}

function removeTmpDir(dir) {
  if (!dir || process.env.MONTAGE_KEEP_TMP === '1') return;
  try {
    fs.rmSync(dir, {recursive: true, force: true});
  } catch {
    /* best effort */
  }
}

/**
 * Fit `srcW x srcH` inside a box of `maxLongEdge` without upscaling.
 * @returns {{width:number, height:number}}
 */
function fitWithin(srcW, srcH, maxLongEdge) {
  const long = Math.max(srcW, srcH);
  const scale = long > maxLongEdge ? maxLongEdge / long : 1;
  return {width: even(srcW * scale), height: even(srcH * scale)};
}

/**
 * Countdown overlay pieces for a canvas: the rounded chip PNG (an extra ffmpeg
 * input) and the drawtext filters that go on top of it.
 *
 * @returns {null | {badgePath:string, overlay:string, drawtext:string, spec:object}}
 */
function countdownPieces({tmpDir, canvasW, canvasH, timerSeconds, clockOffsetSeconds, segmentStart, isLate, fontFile}) {
  const spec = countdownSpec({
    timerSeconds,
    clockOffsetSeconds,
    segmentStart,
    isLate,
    canvasW,
    canvasH,
    fontFile: fontFile || FONT_FILE,
  });
  if (!spec) return null;
  const badgePath = path.join(tmpDir, `badge_${spec.badge.width}x${spec.badge.height}.png`);
  if (!fs.existsSync(badgePath)) {
    writeRoundedRectPng(badgePath, spec.badge.width, spec.badge.height, {
      radius: spec.badge.radius,
      color: [12, 12, 18],
      alpha: 0.74,
    });
  }
  return {
    badgePath,
    overlay: `overlay=x=${spec.badge.x}:y=${spec.badge.y}`,
    drawtext: spec.filters,
    spec,
  };
}

/**
 * Re-encode one clip at 480p-ish with the task-clock countdown burned into the
 * bottom-right corner. Aspect ratio is preserved (no padding here).
 *
 * @param {string} input
 * @param {string} output
 * @param {object} opts
 * @param {number} [opts.timerSeconds]        the task timer
 * @param {number} [opts.clockOffsetSeconds]  task-clock seconds already spent
 *                                            when recording started
 * @param {boolean} [opts.isLate]
 * @param {number} [opts.width] max long edge (default 854)
 * @returns {Promise<{output:string, width:number, height:number, durationSeconds:number,
 *                    countdownFrom:number|null}>}
 */
async function burnCountdown(input, output, opts = {}) {
  // Degrade, never fail: without drawtext the clip is still transcoded, the
  // countdown just isn't burned in (the app overlays it client-side).
  const burn = await hasDrawtext();
  const {timerSeconds, clockOffsetSeconds = 0, isLate = false, width = MAX_LONG_EDGE} = opts;
  const info = opts.probe || (await probe(input));
  const {width: outW, height: outH} = fitWithin(info.width, info.height, width);

  const tmpDir = opts.tmpDir || makeTmpDir('tc-burn-');
  const ownTmp = !opts.tmpDir;
  try {
    const cd = countdownPieces({
      tmpDir,
      canvasW: outW,
      canvasH: outH,
      timerSeconds,
      clockOffsetSeconds,
      segmentStart: 0,
      isLate,
      fontFile: opts.fontFile,
    });

    const inputs = ['-i', input];
    let chain = `[0:v]scale=${outW}:${outH}:flags=bicubic,setsar=1,fps=${opts.fps || CANVAS.fps}`;
    if (cd && burn) {
      inputs.push('-i', cd.badgePath);
      chain += `[base];[base][1:v]${cd.overlay}[boxed];[boxed]${cd.drawtext}`;
    }
    chain += ',format=yuv420p[v]';

    const args = [...inputs];
    let audioMap;
    if (info.hasAudio) {
      audioMap = '[a]';
      chain += ';[0:a]aformat=sample_fmts=fltp:sample_rates=44100:channel_layouts=stereo[a]';
    } else {
      args.push(...SILENT_INPUT);
      audioMap = `${cd ? '2' : '1'}:a`;
      args.push('-shortest');
    }

    await runFfmpeg([
      ...args,
      '-filter_complex', chain,
      '-map', '[v]',
      '-map', audioMap,
      ...VIDEO_ARGS,
      ...AUDIO_ARGS,
      output,
    ]);

    const outInfo = await probe(output);
    return {
      output,
      width: outInfo.width,
      height: outInfo.height,
      durationSeconds: outInfo.durationSeconds,
      countdownFrom: cd ? cd.spec.secondsAtStart : null,
    };
  } finally {
    if (ownTmp) removeTmpDir(tmpDir);
  }
}

/**
 * One montage segment: a slice of a clip, letterboxed onto the portrait canvas
 * with the countdown burned in, normalised so segments concatenate cleanly.
 *
 * @param {object} clip {path, timerSeconds, clockOffsetSeconds, isLate, hasAudio}
 * @param {string} output
 * @param {{start:number, duration:number, canvas:object, tmpDir:string}} opts
 */
async function renderSegment(clip, output, opts) {
  const {start, duration, canvas = CANVAS, tmpDir} = opts;
  const burn = await hasDrawtext();
  const cd = countdownPieces({
    tmpDir,
    canvasW: canvas.width,
    canvasH: canvas.height,
    timerSeconds: clip.timerSeconds,
    clockOffsetSeconds: clip.clockOffsetSeconds || 0,
    segmentStart: start,
    isLate: clip.isLate,
    fontFile: clip.fontFile,
  });

  const inputs = ['-ss', start.toFixed(3), '-t', duration.toFixed(3), '-i', clip.path];
  let chain =
    `[0:v]scale=${canvas.width}:${canvas.height}:force_original_aspect_ratio=decrease:flags=bicubic,` +
    `pad=${canvas.width}:${canvas.height}:(ow-iw)/2:(oh-ih)/2:color=0x0B0B10,setsar=1,fps=${canvas.fps},` +
    'setpts=PTS-STARTPTS';
  if (cd && burn) {
    inputs.push('-i', cd.badgePath);
    chain += `[base];[base][1:v]${cd.overlay}[boxed];[boxed]${cd.drawtext}`;
  }
  chain += ',format=yuv420p[v]';

  const args = [...inputs];
  let audioMap;
  if (clip.hasAudio !== false) {
    audioMap = '[a]';
    chain +=
      ';[0:a]aformat=sample_fmts=fltp:sample_rates=44100:channel_layouts=stereo,' +
      'asetpts=PTS-STARTPTS[a]';
  } else {
    args.push('-f', 'lavfi', '-t', duration.toFixed(3), '-i',
      'anullsrc=channel_layout=stereo:sample_rate=44100');
    audioMap = `${cd ? '2' : '1'}:a`;
  }

  await runFfmpeg([
    ...args,
    '-filter_complex', chain,
    '-map', '[v]',
    '-map', audioMap,
    '-t', duration.toFixed(3),
    ...VIDEO_ARGS,
    ...AUDIO_ARGS,
    output,
  ]);
  return {output, start, duration, countdownFrom: cd ? cd.spec.secondsAtStart : null};
}

/**
 * The card that opens a montage: a kicker ("THE FINALE") over the task title.
 */
async function titleCard(output, opts) {
  const {
    kicker,
    title = '',
    canvas = CANVAS,
    duration = TITLE_SECONDS,
    tmpDir,
    accent = '0xFFC857',
    background = '0x0B0B10',
    fontFile = FONT_FILE,
  } = opts;

  const pad = Math.round(canvas.width * 0.09);
  const usable = canvas.width - pad * 2;
  const kickerFit = fitText(kicker, {width: usable, fontSize: Math.round(canvas.width * 0.105), maxLines: 2});
  const titleFit = fitText(title, {width: usable, fontSize: Math.round(canvas.width * 0.072), maxLines: 4});

  const kickerBlock = kickerFit.lines.length * kickerFit.fontSize * 1.28;
  const kickerCenter = canvas.height * 0.38;
  const titleCenter = kickerCenter + kickerBlock / 2 + Math.round(canvas.height * 0.055) +
    (titleFit.lines.length * titleFit.fontSize * 1.28) / 2;

  const filters = [
    drawtextLines(kickerFit.lines, {
      tmpDir, fontFile, fontSize: kickerFit.fontSize, color: accent, centerY: kickerCenter,
    }),
    drawtextLines(titleFit.lines, {
      tmpDir, fontFile, fontSize: titleFit.fontSize, color: '0xF2F2F7', centerY: titleCenter,
    }),
  ].filter(Boolean);

  // No drawtext -> a plain colour card (the montage still plays end to end).
  const textFilters = (await hasDrawtext()) ? filters : [];
  const chain = `[0:v]${[...textFilters, 'format=yuv420p'].join(',')}[v]`;

  await runFfmpeg([
    '-f', 'lavfi', '-i',
    `color=c=${background}:s=${canvas.width}x${canvas.height}:r=${canvas.fps}:d=${duration}`,
    ...SILENT_INPUT,
    '-filter_complex', chain,
    '-map', '[v]',
    '-map', '1:a',
    '-t', String(duration),
    ...VIDEO_ARGS,
    ...AUDIO_ARGS,
    output,
  ]);
  return output;
}

/** The short black beat between clips. */
async function gapCard(output, {canvas = CANVAS, duration = GAP_SECONDS} = {}) {
  await runFfmpeg([
    '-f', 'lavfi', '-i',
    `color=c=0x000000:s=${canvas.width}x${canvas.height}:r=${canvas.fps}:d=${duration}`,
    ...SILENT_INPUT,
    '-map', '0:v',
    '-map', '1:a',
    '-t', String(duration),
    '-vf', 'setsar=1,format=yuv420p',
    ...VIDEO_ARGS,
    ...AUDIO_ARGS,
    output,
  ]);
  return output;
}

/** Concatenate pre-normalised segments (concat demuxer + a final re-encode). */
async function concatSegments(files, output, {tmpDir}) {
  if (!files.length) throw new Error('concatSegments: nothing to concatenate');
  const listPath = path.join(tmpDir, `concat_${Date.now()}.txt`);
  fs.writeFileSync(
    listPath,
    files.map((f) => `file '${path.resolve(f).replace(/'/g, "'\\''")}'`).join('\n'),
    'utf8',
  );
  await runFfmpeg([
    '-f', 'concat',
    '-safe', '0',
    '-i', listPath,
    ...VIDEO_ARGS,
    ...AUDIO_ARGS,
    output,
  ]);
  return output;
}

/**
 * Normalise the caller's clip descriptors: probe anything missing so the rest
 * of the pipeline can trust `durationSeconds` / `hasAudio`.
 */
async function hydrate(clips) {
  return Promise.all(
    clips.map(async (clip) => {
      const needsProbe = clip.durationSeconds === undefined || clip.hasAudio === undefined ||
        clip.width === undefined;
      const info = needsProbe ? await probe(clip.path) : null;
      return {
        ...clip,
        durationSeconds: clip.durationSeconds !== undefined && clip.durationSeconds > 0
          ? clip.durationSeconds
          : (info ? info.durationSeconds : 0),
        hasAudio: clip.hasAudio !== undefined ? clip.hasAudio : (info ? info.hasAudio : false),
        width: clip.width !== undefined ? clip.width : (info ? info.width : CANVAS.width),
        height: clip.height !== undefined ? clip.height : (info ? info.height : CANVAS.height),
      };
    }),
  );
}

/** Shared build for finale/moments: title card, segments, gaps, concat. */
async function buildMontage(clips, output, opts) {
  await hasDrawtext(); // probe once up front (cached); never throws
  const {
    kicker,
    taskTitle = '',
    canvas = CANVAS,
    titleSeconds = TITLE_SECONDS,
    gapSeconds = GAP_SECONDS,
    chooseWindow,
  } = opts;

  if (!clips || !clips.length) throw new Error(`${kicker}: no clips to montage`);

  const tmpDir = opts.tmpDir || makeTmpDir('tc-montage-');
  const ownTmp = !opts.tmpDir;
  try {
    const hydrated = await hydrate(clips);
    const parts = [];
    const used = [];

    const titlePath = path.join(tmpDir, 'title.mp4');
    await titleCard(titlePath, {
      kicker, title: taskTitle, canvas, duration: titleSeconds, tmpDir,
      accent: opts.accent,
    });
    parts.push(titlePath);

    const gapPath = path.join(tmpDir, 'gap.mp4');
    if (hydrated.length > 1 && gapSeconds > 0) {
      await gapCard(gapPath, {canvas, duration: gapSeconds});
    }

    for (let i = 0; i < hydrated.length; i += 1) {
      const clip = hydrated[i];
      // eslint-disable-next-line no-await-in-loop
      const window = await chooseWindow(clip, i);
      if (!window || window.duration <= 0.05) {
        log(`[montage] skipping clip ${clip.postId || clip.path}: nothing usable`);
        continue;
      }
      if (parts.length > 1 && gapSeconds > 0) parts.push(gapPath);
      const segPath = path.join(tmpDir, `seg_${i}.mp4`);
      // eslint-disable-next-line no-await-in-loop
      await renderSegment(clip, segPath, {
        start: window.start,
        duration: window.duration,
        canvas,
        tmpDir,
      });
      parts.push(segPath);
      used.push({
        postId: clip.postId,
        path: clip.path,
        start: window.start,
        duration: window.duration,
        signal: window.signal,
      });
    }

    if (!used.length) throw new Error(`${kicker}: every clip was too short to use`);

    await concatSegments(parts, output, {tmpDir});
    const info = await probe(output);
    return {
      output,
      clipCount: used.length,
      segments: used,
      durationSeconds: info.durationSeconds,
      width: info.width,
      height: info.height,
    };
  } finally {
    if (ownTmp) removeTmpDir(tmpDir);
  }
}

/**
 * THE FINALE — the last `seconds` of every clip, in `createdAt` order.
 *
 * @param {Array<{path:string, postId?:string, timerSeconds?:number,
 *                clockOffsetSeconds?:number, isLate?:boolean}>} clips
 * @param {string} output
 * @param {{seconds?:number, taskTitle?:string, canvas?:object}} [options]
 */
async function finale(clips, output, options = {}) {
  const seconds = options.seconds || 2;
  return buildMontage(clips, output, {
    ...options,
    kicker: options.kicker || 'THE FINALE',
    accent: options.accent || '0xFFC857',
    chooseWindow: (clip) => {
      const duration = Math.min(seconds, clip.durationSeconds || 0);
      if (duration <= 0.05) return null;
      return {start: Math.max(0, (clip.durationSeconds || 0) - duration), duration, signal: 'end'};
    },
  });
}

/**
 * MOMENTS — one automatically chosen highlight per clip.
 *
 * @param {Array} clips same shape as `finale`, plus optional `tapSeconds`
 * @param {string} output
 * @param {{seconds?:number, taskTitle?:string, analyzeAudio?:Function,
 *          analyzeScene?:Function}} [options]
 */
async function moments(clips, output, options = {}) {
  const seconds = options.seconds || 3;
  return buildMontage(clips, output, {
    ...options,
    kicker: options.kicker || 'MOMENTS',
    accent: options.accent || '0x6EE7B7',
    chooseWindow: async (clip) => {
      const duration = Math.min(seconds, clip.durationSeconds || 0);
      if (duration <= 0.05) return null;
      const pick = await pickHighlight(clip, {
        seconds: duration,
        analyzeAudio: options.analyzeAudio,
        analyzeScene: options.analyzeScene,
      });
      log(`[montage] moment for ${clip.postId || clip.path}: ` +
        `${pick.start.toFixed(2)}s via ${pick.signal}`);
      return {start: pick.start, duration, signal: pick.signal};
    },
  });
}

module.exports = {
  CANVAS,
  MAX_LONG_EDGE,
  TITLE_SECONDS,
  GAP_SECONDS,
  burnCountdown,
  renderSegment,
  titleCard,
  gapCard,
  concatSegments,
  finale,
  moments,
  probe,
  pickHighlight,
  fitWithin,
  makeTmpDir,
  removeTmpDir,
  countdownPieces,
};
