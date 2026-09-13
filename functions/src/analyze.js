'use strict';

/**
 * Clip analysis: probing, and the three signals that choose the "moment" in a
 * clip — viewer taps, audio loudness, then visual change — with a last-resort
 * fallback to the end of the clip (which is where the reveal lives, per the
 * task copy).
 */

const {runFfprobe, runFfmpeg} = require('./ffmpeg');
const {warn} = require('./log');

/**
 * @typedef {object} ProbeResult
 * @property {number} durationSeconds
 * @property {number} width
 * @property {number} height
 * @property {boolean} hasAudio
 * @property {number} fps
 * @property {number} rotation degrees of display rotation metadata
 */

/**
 * ffprobe a media file.
 * @param {string} filePath
 * @returns {Promise<ProbeResult>}
 */
async function probe(filePath) {
  const {stdout} = await runFfprobe([
    '-v', 'error',
    '-print_format', 'json',
    '-show_format',
    '-show_streams',
    filePath,
  ]);
  let parsed;
  try {
    parsed = JSON.parse(stdout);
  } catch (err) {
    throw new Error(`ffprobe returned unparseable JSON for ${filePath}: ${err.message}`);
  }
  const streams = parsed.streams || [];
  const video = streams.find((s) => s.codec_type === 'video');
  const audio = streams.find((s) => s.codec_type === 'audio');
  if (!video) throw new Error(`no video stream in ${filePath}`);

  const durations = [
    parsed.format && parsed.format.duration,
    video.duration,
    audio && audio.duration,
  ]
    .map(Number)
    .filter((n) => Number.isFinite(n) && n > 0);

  const rotation = rotationOf(video);
  const swap = rotation === 90 || rotation === 270;

  return {
    durationSeconds: durations.length ? Math.max(...durations) : 0,
    width: swap ? Number(video.height) : Number(video.width),
    height: swap ? Number(video.width) : Number(video.height),
    hasAudio: Boolean(audio),
    fps: parseFps(video.avg_frame_rate || video.r_frame_rate),
    rotation,
  };
}

function rotationOf(video) {
  const tagged = video.tags && (video.tags.rotate || video.tags.Rotate);
  if (tagged) return ((Number(tagged) % 360) + 360) % 360;
  const matrix = (video.side_data_list || []).find((d) => d.rotation !== undefined);
  if (matrix) return ((Math.round(Number(matrix.rotation)) % 360) + 360) % 360;
  return 0;
}

function parseFps(rate) {
  if (!rate) return 30;
  const [num, den] = String(rate).split('/').map(Number);
  if (!den) return Number.isFinite(num) && num > 0 ? num : 30;
  const fps = num / den;
  return Number.isFinite(fps) && fps > 0 ? fps : 30;
}

/**
 * Per-second RMS loudness, and the loudest second.
 *
 * Uses `astats` reset once per 8000-sample block at 8 kHz — i.e. one stats
 * block per second of audio — printed by `ametadata`.
 *
 * @returns {Promise<null | {second:number, levelDb:number, medianDb:number, levels:Array}>}
 *   `null` when there is no audio, no finite levels, or the peak is not
 *   meaningfully above the body of the clip.
 */
async function analyzeAudioPeak(filePath, {minDbOverMedian = 3} = {}) {
  let out;
  try {
    const res = await runFfmpeg([
      '-i', filePath,
      '-vn',
      '-af',
      'aresample=8000,asetnsamples=n=8000:p=0,astats=metadata=1:reset=1,' +
        'ametadata=print:key=lavfi.astats.Overall.RMS_level:file=-',
      '-f', 'null',
      '-',
    ]);
    out = res.stdout;
  } catch (err) {
    warn(`[analyze] audio pass failed for ${filePath}: ${err.message.split('\n')[0]}`);
    return null;
  }

  const levels = [];
  let pendingTime = null;
  for (const line of out.split('\n')) {
    const timeMatch = line.match(/pts_time:([0-9.]+)/);
    if (timeMatch) {
      pendingTime = Number(timeMatch[1]);
      continue;
    }
    const valMatch = line.match(/lavfi\.astats\.Overall\.RMS_level=(-?[0-9.]+|-?inf|nan)/);
    if (valMatch && pendingTime !== null) {
      const value = Number(valMatch[1]);
      if (Number.isFinite(value)) levels.push({second: Math.floor(pendingTime), levelDb: value});
    }
  }
  if (!levels.length) return null;

  const sorted = [...levels].sort((a, b) => a.levelDb - b.levelDb);
  const medianDb = sorted[Math.floor(sorted.length / 2)].levelDb;
  const peak = sorted[sorted.length - 1];
  if (levels.length > 1 && peak.levelDb - medianDb < minDbOverMedian) return null;
  return {second: peak.second, levelDb: peak.levelDb, medianDb, levels};
}

/**
 * The biggest frame-to-frame visual change (scene score).
 *
 * @returns {Promise<null | {second:number, score:number}>}
 */
async function analyzeScenePeak(filePath, {minScore = 0.12} = {}) {
  let out;
  try {
    const res = await runFfmpeg([
      '-i', filePath,
      '-an',
      '-vf',
      "scale=160:-2,fps=10,select='gt(scene\\,0)',metadata=print:key=lavfi.scene_score:file=-",
      '-f', 'null',
      '-',
    ]);
    out = res.stdout;
  } catch (err) {
    warn(`[analyze] scene pass failed for ${filePath}: ${err.message.split('\n')[0]}`);
    return null;
  }

  let best = null;
  let pendingTime = null;
  for (const line of out.split('\n')) {
    const timeMatch = line.match(/pts_time:([0-9.]+)/);
    if (timeMatch) {
      pendingTime = Number(timeMatch[1]);
      continue;
    }
    const valMatch = line.match(/lavfi\.scene_score=([0-9.eE+-]+)/);
    if (valMatch && pendingTime !== null) {
      const score = Number(valMatch[1]);
      // The first frame has nothing to compare against; ignore t=0.
      if (Number.isFinite(score) && pendingTime > 0.001 && (!best || score > best.score)) {
        best = {second: Math.floor(pendingTime), score, at: pendingTime};
      }
    }
  }
  if (!best || best.score < minScore) return null;
  return best;
}

/**
 * The densest `seconds`-wide window of viewer taps.
 *
 * @param {object} tapSeconds second-bucket -> tap count, e.g. {"3": 2, "7": 1}
 * @returns {null | {center:number, taps:number, start:number}}
 *   `null` unless some bucket has at least `minTapsInBucket` taps, which is the
 *   rule from the brief (one stray tap is noise).
 */
function tapWindow(tapSeconds, {seconds = 3, durationSeconds = 0, minTapsInBucket = 2} = {}) {
  if (!tapSeconds || typeof tapSeconds !== 'object') return null;
  const buckets = [];
  for (const [key, value] of Object.entries(tapSeconds)) {
    const second = Number(key);
    const count = Number(value);
    if (Number.isFinite(second) && second >= 0 && Number.isFinite(count) && count > 0) {
      buckets.push({second: Math.floor(second), count});
    }
  }
  if (!buckets.length) return null;
  if (!buckets.some((b) => b.count >= minTapsInBucket)) return null;

  const lastBucket = Math.max(...buckets.map((b) => b.second));
  const span = Math.max(Math.ceil(durationSeconds) || 0, lastBucket + 1);
  const maxStart = Math.max(0, span - seconds);

  let best = null;
  for (let start = 0; start <= maxStart; start += 1) {
    const taps = buckets
      .filter((b) => b.second >= start && b.second < start + seconds)
      .reduce((sum, b) => sum + b.count, 0);
    if (!best || taps > best.taps) best = {start, taps};
  }
  if (!best || best.taps === 0) return null;
  return {start: best.start, taps: best.taps, center: best.start + seconds / 2};
}

/**
 * Choose the highlight window of a clip.
 *
 * Signal order (first that fires wins):
 *   `taps` -> `audio` -> `scene` -> `fallback` (the last `seconds`, the reveal).
 *
 * The analyzers are injectable so the decision logic is unit-testable without
 * running ffmpeg.
 *
 * @param {{path:string, durationSeconds:number, tapSeconds?:object}} clip
 * @returns {Promise<{start:number, center:number, seconds:number, signal:string}>}
 */
async function pickHighlight(clip, options = {}) {
  const seconds = options.seconds || 3;
  const duration = Number(clip.durationSeconds) || 0;
  const analyzeAudio = options.analyzeAudio || analyzeAudioPeak;
  const analyzeScene = options.analyzeScene || analyzeScenePeak;

  const clamp = (center, signal) => {
    const maxStart = Math.max(0, duration - seconds);
    const start = Math.min(Math.max(0, center - seconds / 2), maxStart);
    return {start, center: start + seconds / 2, seconds, signal};
  };

  const taps = tapWindow(clip.tapSeconds, {seconds, durationSeconds: duration});
  if (taps) return clamp(taps.center, 'taps');

  if (clip.hasAudio !== false) {
    const audio = await analyzeAudio(clip.path);
    if (audio) return clamp(audio.second + 0.5, 'audio');
  }

  const scene = await analyzeScene(clip.path);
  if (scene) return clamp(scene.at !== undefined ? scene.at : scene.second + 0.5, 'scene');

  return clamp(Math.max(0, duration) - seconds / 2, 'fallback');
}

module.exports = {
  probe,
  analyzeAudioPeak,
  analyzeScenePeak,
  tapWindow,
  pickHighlight,
  parseFps,
};
