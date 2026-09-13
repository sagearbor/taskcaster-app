#!/usr/bin/env node
'use strict';

/**
 * Render the six HOUSE video clips ("Greg's assistant") straight from the
 * starter-task spec, using the same ffmpeg/drawtext plumbing as the server
 * montage pipeline — so the countdown chip on a house clip is pixel-identical
 * to the one burned into a player's clip.
 *
 * Each clip: 7 s, 480x600 (4:5), a distinct background colour, the house text
 * wrapped and centred in Fredoka, the task countdown in the bottom-right
 * (clockOffset 0), and the REVEAL word landing big in the last 2 seconds —
 * which is exactly the slice the automatic finale montage takes.
 *
 * Usage:
 *   node scripts/house_clips/make_house_clips.js [--source FILE] [--out DIR]
 *
 * Outputs `<out>/starter-XX.mp4`, ready to upload to `house/<taskId>.mp4`.
 */

const fs = require('fs');
const os = require('os');
const path = require('path');

const FUNCTIONS = path.join(__dirname, '..', '..', 'functions');
const {runFfmpeg, assertDrawtext} = require(path.join(FUNCTIONS, 'src', 'ffmpeg'));
const {countdownSpec, FONT_FILE} = require(path.join(FUNCTIONS, 'src', 'countdown'));
const {writeRoundedRectPng} = require(path.join(FUNCTIONS, 'src', 'badge'));
const {fitText, drawtextLines} = require(path.join(FUNCTIONS, 'src', 'text'));

const CANVAS = {width: 480, height: 600, fps: 30};
const DURATION = 7;
const REVEAL_AT = 5; // the reveal owns the last 2 s — the finale's slice

/** A distinct, pleasant ground per task. White text sits well on all of them. */
const COLOURS = {
  'starter-01': '0x2F6F5E', // egg / spoon — deep teal
  'starter-02': '0xA9542B', // tower — terracotta
  'starter-05': '0x7A3B5E', // sandwich — plum
  'starter-08': '0x2B5D8A', // head things — ocean blue
  'starter-09': '0x9A3B33', // oven face — brick
  'starter-10': '0x3E4A89', // autobiography — indigo
};

const REVEAL_COLOUR = '0xFFD166';
const TEXT_COLOUR = '0xFFFFFF';

const SOURCE_CANDIDATES = [
  path.join(__dirname, '..', '..', 'tmp', 'round8-starter-tasks.md'),
  path.join(__dirname, '..', '..', '..', '..', '..', 'tmp', 'round8-starter-tasks.md'),
  '/Users/sagearbor/projects/githubs/taskcaster-app/tmp/round8-starter-tasks.md',
];

const DEFAULT_OUT = '/Users/sagearbor/projects/githubs/taskcaster-app/tmp/house_clips';

// ---------------------------------------------------------------------------
// Spec parsing — the markdown is the source of truth for text, reveal, timer
// ---------------------------------------------------------------------------

/**
 * @returns {Array<{taskId:string, title:string, timerSeconds:number,
 *                  text:string, reveal:string}>}
 */
function parseSpec(markdown) {
  const tasks = new Map();

  // "## starter-01 — Egg on a spoon, … · VIDEO · 30 s"
  const headerRe = /^##\s+(starter-\d+)\s+—\s+(.+?)\s+·\s+(VIDEO|PHOTO|TEXT)\s+·\s+(\d+)\s*s\s*$/gm;
  for (const m of markdown.matchAll(headerRe)) {
    tasks.set(m[1], {
      taskId: m[1],
      title: m[2].trim(),
      mediaType: m[3].toLowerCase(),
      timerSeconds: Number(m[4]),
    });
  }

  // '- starter-01: "Egg made it 4 steps." (reveal: "SPLAT")'
  const houseRe = /^-\s+(starter-\d+):\s*"([\s\S]*?)"\s*\(reveal:\s*"([^"]+)"\)\s*$/gm;
  const out = [];
  for (const m of markdown.matchAll(houseRe)) {
    const task = tasks.get(m[1]);
    if (!task) {
      throw new Error(`house entry for ${m[1]} has no task header in the spec`);
    }
    if (task.mediaType !== 'video') continue;
    out.push({...task, text: m[2].replace(/\s+/g, ' ').trim(), reveal: m[3].trim()});
  }
  return out;
}

function findSource(explicit) {
  const candidates = explicit ? [explicit] : SOURCE_CANDIDATES;
  for (const candidate of candidates) {
    if (fs.existsSync(candidate)) return candidate;
  }
  throw new Error(`starter-task spec not found. Tried:\n  ${candidates.join('\n  ')}`);
}

// ---------------------------------------------------------------------------
// Render
// ---------------------------------------------------------------------------

/** Render one house clip. @returns {Promise<{path:string, bytes:number}>} */
async function renderHouseClip(task, {outDir, tmpDir}) {
  const background = COLOURS[task.taskId] || '0x333A45';
  const pad = Math.round(CANVAS.width * 0.09);
  const usable = CANVAS.width - pad * 2;

  // Before the reveal: the house line, centred and large.
  const big = fitText(task.text, {width: usable, fontSize: 44, maxLines: 5, minFontSize: 22});
  // After the reveal: the same line, smaller, pushed up to make room.
  const small = fitText(task.text, {width: usable, fontSize: 27, maxLines: 6, minFontSize: 16});
  const revealFit = fitText(task.reveal, {width: usable, fontSize: 78, maxLines: 2, minFontSize: 34});

  const beforeReveal = `lt(t\\,${REVEAL_AT})`;
  const afterReveal = `gte(t\\,${REVEAL_AT})`;

  const filters = [
    // A "HOUSE" tag, so the clip reads as the house entry even out of context.
    drawtextLines(['HOUSE · GREG’S ASSISTANT'], {
      tmpDir,
      fontFile: FONT_FILE,
      fontSize: 19,
      color: '0xFFFFFF@0.72',
      centerY: Math.round(CANVAS.height * 0.075),
    }),
    drawtextLines(big.lines, {
      tmpDir,
      fontFile: FONT_FILE,
      fontSize: big.fontSize,
      color: TEXT_COLOUR,
      centerY: Math.round(CANVAS.height * 0.46),
      enable: beforeReveal,
    }),
    drawtextLines(small.lines, {
      tmpDir,
      fontFile: FONT_FILE,
      fontSize: small.fontSize,
      color: '0xFFFFFF@0.8',
      centerY: Math.round(CANVAS.height * 0.26),
      enable: afterReveal,
    }),
    drawtextLines(revealFit.lines, {
      tmpDir,
      fontFile: FONT_FILE,
      fontSize: revealFit.fontSize,
      color: REVEAL_COLOUR,
      centerY: Math.round(CANVAS.height * 0.6),
      enable: afterReveal,
    }),
  ].filter(Boolean);

  // The countdown chip, identical to the server montage pass.
  const cd = countdownSpec({
    timerSeconds: task.timerSeconds,
    clockOffsetSeconds: 0,
    canvasW: CANVAS.width,
    canvasH: CANVAS.height,
  });
  const badgePath = path.join(tmpDir, `badge_${task.taskId}.png`);
  writeRoundedRectPng(badgePath, cd.badge.width, cd.badge.height, {
    radius: cd.badge.radius,
    color: [12, 12, 18],
    alpha: 0.74,
  });

  const chain =
    `[0:v]${filters.join(',')}[txt];` +
    `[txt][1:v]overlay=x=${cd.badge.x}:y=${cd.badge.y}[boxed];` +
    `[boxed]${cd.filters},format=yuv420p[v]`;

  const out = path.join(outDir, `${task.taskId}.mp4`);
  await runFfmpeg([
    '-f', 'lavfi', '-i',
    `color=c=${background}:s=${CANVAS.width}x${CANVAS.height}:r=${CANVAS.fps}:d=${DURATION}`,
    '-i', badgePath,
    '-f', 'lavfi', '-i', 'anullsrc=channel_layout=stereo:sample_rate=44100',
    '-filter_complex', chain,
    '-map', '[v]',
    '-map', '2:a',
    '-t', String(DURATION),
    '-c:v', 'libx264',
    '-profile:v', 'high',
    '-level', '3.1',
    '-preset', 'slow',
    '-crf', '26',
    '-pix_fmt', 'yuv420p',
    '-movflags', '+faststart',
    '-c:a', 'aac', '-b:a', '64k', '-ar', '44100', '-ac', '2',
    out,
  ]);

  return {path: out, bytes: fs.statSync(out).size};
}

// ---------------------------------------------------------------------------

function parseArgs(argv) {
  const args = {source: null, out: DEFAULT_OUT};
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === '--source') args.source = argv[i + 1];
    if (argv[i] === '--out') args.out = argv[i + 1];
  }
  return args;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  await assertDrawtext();

  const source = findSource(args.source);
  const tasks = parseSpec(fs.readFileSync(source, 'utf8'));
  if (!tasks.length) throw new Error(`no house video entries parsed from ${source}`);

  fs.mkdirSync(args.out, {recursive: true});
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'house-clips-'));

  console.log(`spec:   ${source}`);
  console.log(`output: ${args.out}`);
  console.log(`clips:  ${tasks.length}\n`);

  const results = [];
  for (const task of tasks) {
    // eslint-disable-next-line no-await-in-loop
    const result = await renderHouseClip(task, {outDir: args.out, tmpDir});
    results.push({...result, task});
    console.log(
      `  ${task.taskId}  ${String(task.timerSeconds).padStart(3)} s timer  ` +
        `reveal "${task.reveal}"  ${(result.bytes / 1024).toFixed(1)} KB`,
    );
  }

  fs.rmSync(tmpDir, {recursive: true, force: true});

  const total = results.reduce((sum, r) => sum + r.bytes, 0);
  console.log(`\n${results.length} clips, ${(total / 1024).toFixed(1)} KB total`);
  const over = results.filter((r) => r.bytes > 1024 * 1024);
  if (over.length) {
    console.error(`WARNING: ${over.length} clip(s) over 1 MB`);
    process.exitCode = 1;
  }
}

if (require.main === module) {
  main().catch((err) => {
    console.error(err.message);
    process.exit(1);
  });
}

module.exports = {parseSpec, renderHouseClip, COLOURS, CANVAS, DURATION, REVEAL_AT};
