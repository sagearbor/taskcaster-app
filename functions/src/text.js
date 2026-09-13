'use strict';

/**
 * Text helpers for burned-in captions: greedy word wrapping (we have no font
 * metrics server-side, so we approximate from the font size) and centred
 * multi-line `drawtext` filters.
 *
 * Each line is written to its own text file and drawn with its own `drawtext`.
 * Two reasons:
 *   1. ffmpeg 6 has no `text_align`, so a multi-line drawtext is left-aligned
 *      inside a centred block — per-line drawtext gives true centring.
 *   2. `textfile=` sidesteps ffmpeg's filter-argument escaping entirely, so
 *      apostrophes, colons and commas in task titles are safe.
 */

const fs = require('fs');
const path = require('path');

/** Rough advance width of one glyph in Fredoka, as a fraction of font size. */
const GLYPH_RATIO = 0.54;

/** Characters that fit across `pixels` at `fontSize`. */
function charsPerLine(pixels, fontSize) {
  return Math.max(6, Math.floor(pixels / (fontSize * GLYPH_RATIO)));
}

/**
 * Greedy word wrap. Words longer than the limit are hard-split.
 * @returns {string[]}
 */
function wrapText(text, maxChars) {
  const words = String(text || '').trim().split(/\s+/).filter(Boolean);
  const lines = [];
  let current = '';
  for (const word of words) {
    if (word.length > maxChars) {
      if (current) {
        lines.push(current);
        current = '';
      }
      for (let i = 0; i < word.length; i += maxChars) lines.push(word.slice(i, i + maxChars));
      continue;
    }
    const candidate = current ? `${current} ${word}` : word;
    if (candidate.length <= maxChars) {
      current = candidate;
    } else {
      if (current) lines.push(current);
      current = word;
    }
  }
  if (current) lines.push(current);
  return lines;
}

/**
 * Wrap `text` into at most `maxLines`, shrinking the font until it fits.
 * @returns {{lines: string[], fontSize: number}}
 */
function fitText(text, {width, fontSize, maxLines = 4, minFontSize = 14}) {
  let size = fontSize;
  let lines = wrapText(text, charsPerLine(width, size));
  while (lines.length > maxLines && size > minFontSize) {
    size = Math.max(minFontSize, Math.round(size * 0.9));
    lines = wrapText(text, charsPerLine(width, size));
  }
  return {lines, fontSize: size};
}

let fileCounter = 0;

/**
 * Centred multi-line drawtext filters.
 *
 * @param {string[]} lines
 * @param {object} opts
 * @param {string} opts.tmpDir   where the per-line text files go
 * @param {string} opts.fontFile
 * @param {number} opts.fontSize
 * @param {string} [opts.color]
 * @param {number} [opts.centerY] y of the vertical centre of the block, px
 * @param {number} [opts.lineSpacing] multiplier of fontSize (default 1.28)
 * @param {string} [opts.enable]  ffmpeg enable expression
 * @param {string} [opts.xExpr]   default: horizontally centred
 * @returns {string} comma-joined drawtext filters ('' when there is no text)
 */
function drawtextLines(lines, opts) {
  const {
    tmpDir,
    fontFile,
    fontSize,
    color = 'white',
    centerY,
    lineSpacing = 1.28,
    enable,
    xExpr = '(w-tw)/2',
    shadow = true,
  } = opts;
  const clean = (lines || []).filter((l) => String(l).trim().length);
  if (!clean.length) return '';

  const step = fontSize * lineSpacing;
  const blockHeight = step * clean.length;
  const top = centerY - blockHeight / 2;

  return clean
    .map((line, i) => {
      fileCounter += 1;
      const file = path.join(tmpDir, `txt_${process.pid}_${fileCounter}.txt`);
      fs.writeFileSync(file, line, 'utf8');
      const parts = [
        `drawtext=fontfile=${fontFile}`,
        `textfile=${file}`,
        'expansion=none',
        `fontsize=${Math.round(fontSize)}`,
        `fontcolor=${color}`,
        `x=${xExpr}`,
        `y=${Math.round(top + i * step)}`,
      ];
      if (shadow) parts.push('shadowcolor=0x000000@0.45', 'shadowx=0', 'shadowy=2');
      if (enable) parts.push(`enable='${enable}'`);
      return parts.join(':');
    })
    .join(',');
}

module.exports = {wrapText, fitText, charsPerLine, drawtextLines, GLYPH_RATIO};
