'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  formatClock, remainingAtStart, countdownGeometry, countdownSpec,
} = require('../src/countdown');
const {wrapText, fitText, charsPerLine} = require('../src/text');
const {roundedRectPng} = require('../src/badge');

test('formatClock renders m:ss', () => {
  assert.equal(formatClock(27), '0:27');
  assert.equal(formatClock(7), '0:07');
  assert.equal(formatClock(60), '1:00');
  assert.equal(formatClock(95), '1:35');
  assert.equal(formatClock(0), '0:00');
  assert.equal(formatClock(-5), '0:00');
  assert.equal(formatClock(29.9), '0:29');
  assert.equal(formatClock(null), '0:00');
});

test('remainingAtStart counts the TASK clock down, not the clip', () => {
  assert.equal(remainingAtStart({timerSeconds: 30, clockOffsetSeconds: 0}), 30);
  assert.equal(remainingAtStart({timerSeconds: 30, clockOffsetSeconds: 4}), 26);
  // A montage segment that starts 8 s into the clip is 8 s further down the clock.
  assert.equal(remainingAtStart({timerSeconds: 30, clockOffsetSeconds: 4, segmentStart: 8}), 18);
  // Never negative.
  assert.equal(remainingAtStart({timerSeconds: 30, clockOffsetSeconds: 40}), 0);
  // No timer and not late -> nothing to draw (-1 is the sentinel).
  assert.equal(remainingAtStart({}), -1);
  assert.equal(remainingAtStart({timerSeconds: 0}), -1);
  // No timer but late -> LATE.
  assert.equal(remainingAtStart({isLate: true}), 0);
});

test('countdownGeometry pins the chip to the bottom-right with a margin', () => {
  const g = countdownGeometry(480, 600);
  assert.ok(g.badgeX + g.badgeW < 480, 'chip fits horizontally');
  assert.ok(g.badgeY + g.badgeH < 600, 'chip fits vertically');
  assert.equal(g.badgeX, 480 - g.badgeW - g.margin);
  assert.equal(g.badgeY, 600 - g.badgeH - g.margin);
  assert.ok(g.fontSize >= 18 && g.fontSize <= 64);
  // Bigger canvas -> bigger chip.
  assert.ok(countdownGeometry(854, 1080).fontSize > g.fontSize);
});

test('countdownSpec builds white, red and LATE layers for a running clock', () => {
  const spec = countdownSpec({
    timerSeconds: 30, clockOffsetSeconds: 0, canvasW: 480, canvasH: 600,
  });
  assert.equal(spec.secondsAtStart, 30);
  const layers = spec.filters.split('drawtext=').length - 1;
  assert.equal(layers, 3, 'white + red + LATE');
  assert.match(spec.filters, /fontcolor=0xFFFFFF/);
  assert.match(spec.filters, /fontcolor=0xFF4D4D/);
  assert.match(spec.filters, /text='LATE'/);
  // Turns red with 10 s left: 30 - 10 = 20.
  assert.match(spec.filters, /enable='lt\(t\\,20\)'/);
  assert.match(spec.filters, /enable='gte\(t\\,20\)\*lt\(t\\,30\)'/);
  assert.match(spec.filters, /enable='gte\(t\\,30\)'/);
  // Colons and commas inside the expression are escaped for ffmpeg's parser.
  assert.ok(!/[^\\]:d}/.test(spec.filters), 'eif colons are escaped');
});

test('countdownSpec drops the white layer when the clock starts under 10 s', () => {
  const spec = countdownSpec({
    timerSeconds: 30, clockOffsetSeconds: 24, canvasW: 480, canvasH: 600,
  });
  assert.equal(spec.secondsAtStart, 6);
  assert.equal(spec.filters.split('drawtext=').length - 1, 2, 'red + LATE only');
  assert.ok(!spec.filters.includes('0xFFFFFF'));
});

test('countdownSpec shows a permanent LATE when the clock has already run out', () => {
  const spec = countdownSpec({
    timerSeconds: 30, clockOffsetSeconds: 45, canvasW: 480, canvasH: 600,
  });
  assert.equal(spec.secondsAtStart, 0);
  assert.equal(spec.filters.split('drawtext=').length - 1, 1);
  assert.match(spec.filters, /text='LATE':enable='1'/);
});

test('countdownSpec draws nothing when there is no clock', () => {
  assert.equal(countdownSpec({canvasW: 480, canvasH: 600}), null);
  assert.equal(countdownSpec({timerSeconds: 0, canvasW: 480, canvasH: 600}), null);
  assert.ok(countdownSpec({isLate: true, canvasW: 480, canvasH: 600}));
});

test('wrapText wraps greedily and hard-splits monster words', () => {
  assert.deepEqual(wrapText('the worst sandwich that is still food', 12), [
    'the worst', 'sandwich', 'that is', 'still food',
  ]);
  assert.deepEqual(wrapText('supercalifragilistic', 8), ['supercal', 'ifragili', 'stic']);
  assert.deepEqual(wrapText('   ', 10), []);
  assert.deepEqual(wrapText(null, 10), []);
});

test('fitText shrinks the font until the text fits the line budget', () => {
  const long = 'The face of someone who has just remembered the oven is on in another country';
  const big = fitText(long, {width: 400, fontSize: 40, maxLines: 4});
  assert.ok(big.lines.length <= 4);
  assert.ok(big.fontSize < 40, 'font was reduced to fit');
  const short = fitText('Hi', {width: 400, fontSize: 40, maxLines: 4});
  assert.deepEqual(short.lines, ['Hi']);
  assert.equal(short.fontSize, 40, 'short text keeps the requested size');
});

test('charsPerLine never returns a uselessly small budget', () => {
  assert.ok(charsPerLine(400, 30) > 10);
  assert.equal(charsPerLine(10, 200), 6);
});

test('roundedRectPng emits a valid RGBA PNG with rounded corners', () => {
  const png = roundedRectPng(60, 40, {radius: 12, color: [10, 10, 20], alpha: 0.8});
  assert.deepEqual([...png.subarray(0, 8)], [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  assert.equal(png.subarray(12, 16).toString('ascii'), 'IHDR');
  assert.equal(png.readUInt32BE(16), 60);
  assert.equal(png.readUInt32BE(20), 40);
  assert.equal(png[24], 8, 'bit depth 8');
  assert.equal(png[25], 6, 'colour type RGBA');
  assert.equal(png.subarray(png.length - 8, png.length - 4).toString('ascii'), 'IEND');
});
