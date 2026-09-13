'use strict';

/**
 * The burned-in TASK-CLOCK countdown, bottom-right of every video.
 *
 * Owner's rule: "always have a countdown timer in the bottom right if video
 * added, so we could show last 2 seconds spliced together."
 *
 * The clock counts the TASK timer down, not the clip: at clip time `t` the
 * player had `timerSeconds - clockOffsetSeconds - t` seconds left. It turns red
 * in the last 10 s and reads LATE once it hits zero.
 */

const path = require('path');

const FONT_FILE = process.env.MONTAGE_FONT || path.join(__dirname, '..', 'assets', 'Fredoka.ttf');

/** `95` -> `"1:35"`, `7` -> `"0:07"`. Negative clamps to `"0:00"`. */
function formatClock(seconds) {
  const s = Math.max(0, Math.floor(Number(seconds) || 0));
  const mm = Math.floor(s / 60);
  const ss = s % 60;
  return `${mm}:${ss < 10 ? '0' : ''}${ss}`;
}

/**
 * Escape a value for use inside a single-quoted ffmpeg filter option.
 * Verified against ffmpeg 6: `:` and `,` must be backslash-escaped even inside
 * quotes, otherwise the option parser splits mid-expression.
 */
function escapeFilterValue(value) {
  return String(value)
    .replace(/\\/g, '\\\\')
    .replace(/:/g, '\\:')
    .replace(/,/g, '\\,')
    .replace(/'/g, '’'); // a straight quote cannot survive the parser; use a curly one
}

const RED = '0xFF4D4D';
const WHITE = '0xFFFFFF';

/**
 * Geometry of the countdown chip for a given canvas.
 * @returns {{fontSize:number, badgeW:number, badgeH:number, badgeX:number,
 *            badgeY:number, radius:number, margin:number}}
 */
function countdownGeometry(canvasW, canvasH) {
  const fontSize = Math.max(18, Math.round(Math.min(canvasW, canvasH) * 0.072));
  const badgeW = Math.round(fontSize * 2.9);
  const badgeH = Math.round(fontSize * 1.6);
  const margin = Math.round(fontSize * 0.62);
  return {
    fontSize,
    badgeW,
    badgeH,
    margin,
    radius: Math.round(badgeH * 0.34),
    badgeX: canvasW - badgeW - margin,
    badgeY: canvasH - badgeH - margin,
  };
}

/**
 * Seconds left on the task clock at the first frame of a segment.
 *
 * @param {object} p
 * @param {number} [p.timerSeconds]  the task timer
 * @param {number} [p.clockOffsetSeconds] seconds of task clock already spent
 *   when recording started
 * @param {number} [p.segmentStart] seconds into the CLIP this segment begins
 * @param {boolean} [p.isLate]
 * @returns {number} seconds remaining at t=0 of the segment; 0 means "LATE"
 */
function remainingAtStart({timerSeconds, clockOffsetSeconds = 0, segmentStart = 0, isLate = false}) {
  const timer = Number(timerSeconds);
  if (!Number.isFinite(timer) || timer <= 0) return isLate ? 0 : -1; // -1 = no clock to show
  const spent = (Number(clockOffsetSeconds) || 0) + (Number(segmentStart) || 0);
  return Math.max(0, timer - spent);
}

/**
 * The drawtext filters that paint the countdown, plus the chip geometry.
 *
 * @returns {null | {filters: string, geometry: object, badge: object}}
 *   `null` when there is no clock to draw (no timer and not late).
 */
function countdownSpec({
  timerSeconds,
  clockOffsetSeconds = 0,
  segmentStart = 0,
  isLate = false,
  canvasW,
  canvasH,
  fontFile = FONT_FILE,
}) {
  const t0 = remainingAtStart({timerSeconds, clockOffsetSeconds, segmentStart, isLate});
  if (t0 < 0) return null;

  const g = countdownGeometry(canvasW, canvasH);
  const layers = [];

  const base = (extra) =>
    [
      `drawtext=fontfile=${fontFile}`,
      `fontsize=${extra.fontSize}`,
      `fontcolor=${extra.color}`,
      `x=${g.badgeX}+(${g.badgeW}-tw)/2`,
      `y=${g.badgeY}+(${g.badgeH}-th)/2`,
      `text='${extra.text}'`,
      `enable='${extra.enable}'`,
      'box=0',
      'shadowcolor=0x000000@0.55',
      'shadowx=0',
      'shadowy=2',
    ].join(':');

  if (t0 > 0) {
    // max(0, t0 - t), evaluated per frame by drawtext's %{eif:} expansion.
    const R = `max(0\\,${t0}-t)`;
    const clock = `%{eif\\:floor(${R}/60)\\:d}\\:%{eif\\:mod(floor(${R})\\,60)\\:d\\:2}`;
    const redFrom = Math.max(0, t0 - 10);
    if (t0 > 10) {
      layers.push(
        base({fontSize: g.fontSize, color: WHITE, text: clock, enable: `lt(t\\,${redFrom})`}),
      );
    }
    layers.push(
      base({
        fontSize: g.fontSize,
        color: RED,
        text: clock,
        enable: `gte(t\\,${redFrom})*lt(t\\,${t0})`,
      }),
    );
  }
  layers.push(
    base({
      fontSize: Math.round(g.fontSize * 0.82),
      color: RED,
      text: 'LATE',
      enable: t0 > 0 ? `gte(t\\,${t0})` : '1',
    }),
  );

  return {
    filters: layers.join(','),
    geometry: g,
    secondsAtStart: t0,
    badge: {
      width: g.badgeW,
      height: g.badgeH,
      radius: g.radius,
      x: g.badgeX,
      y: g.badgeY,
    },
  };
}

module.exports = {
  formatClock,
  escapeFilterValue,
  countdownGeometry,
  countdownSpec,
  remainingAtStart,
  FONT_FILE,
};
