'use strict';

/**
 * A tiny dependency-free RGBA PNG writer, used for the dark ROUNDED box that
 * sits behind the burned-in countdown. ffmpeg's `drawtext=box=1` can only draw
 * a hard rectangle, so we generate the rounded chip ourselves and `overlay` it.
 *
 * Only what we need: 8-bit RGBA, no interlacing, one IDAT.
 */

const zlib = require('zlib');
const fs = require('fs');

const CRC_TABLE = (() => {
  const table = new Int32Array(256);
  for (let n = 0; n < 256; n += 1) {
    let c = n;
    for (let k = 0; k < 8; k += 1) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c;
  }
  return table;
})();

function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i += 1) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length, 0);
  const typeBuf = Buffer.from(type, 'ascii');
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(Buffer.concat([typeBuf, data])), 0);
  return Buffer.concat([len, typeBuf, data, crc]);
}

/**
 * Encode raw RGBA pixel data (width * height * 4 bytes) as a PNG buffer.
 */
function encodePng(width, height, rgba) {
  const raw = Buffer.alloc((width * 4 + 1) * height);
  for (let y = 0; y < height; y += 1) {
    raw[y * (width * 4 + 1)] = 0; // filter type: none
    rgba.copy(raw, y * (width * 4 + 1) + 1, y * width * 4, (y + 1) * width * 4);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 6; // colour type RGBA
  ihdr[10] = 0;
  ihdr[11] = 0;
  ihdr[12] = 0;
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw, {level: 9})),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

/** Coverage of the rounded-rect at a pixel, supersampled 3x3 for smooth edges. */
function coverage(px, py, width, height, radius) {
  let hits = 0;
  for (let sy = 0; sy < 3; sy += 1) {
    for (let sx = 0; sx < 3; sx += 1) {
      const x = px + (sx + 0.5) / 3;
      const y = py + (sy + 0.5) / 3;
      const cx = Math.min(Math.max(x, radius), width - radius);
      const cy = Math.min(Math.max(y, radius), height - radius);
      const dx = x - cx;
      const dy = y - cy;
      if (dx * dx + dy * dy <= radius * radius) hits += 1;
    }
  }
  return hits / 9;
}

/**
 * A rounded rectangle as a PNG buffer.
 *
 * @param {number} width
 * @param {number} height
 * @param {object} [opts]
 * @param {number} [opts.radius] corner radius, px (clamped to half the short edge)
 * @param {number[]} [opts.color] [r, g, b] 0-255
 * @param {number} [opts.alpha] 0..1 fill opacity
 */
function roundedRectPng(width, height, {radius = 16, color = [16, 16, 20], alpha = 0.72} = {}) {
  const w = Math.max(1, Math.round(width));
  const h = Math.max(1, Math.round(height));
  const r = Math.max(0, Math.min(radius, Math.min(w, h) / 2));
  const [red, green, blue] = color;
  const rgba = Buffer.alloc(w * h * 4);
  for (let y = 0; y < h; y += 1) {
    for (let x = 0; x < w; x += 1) {
      const a = Math.round(coverage(x, y, w, h, r) * alpha * 255);
      const i = (y * w + x) * 4;
      rgba[i] = red;
      rgba[i + 1] = green;
      rgba[i + 2] = blue;
      rgba[i + 3] = a;
    }
  }
  return encodePng(w, h, rgba);
}

/** Write a rounded-rect PNG to `filePath` and return the path. */
function writeRoundedRectPng(filePath, width, height, opts) {
  fs.writeFileSync(filePath, roundedRectPng(width, height, opts));
  return filePath;
}

module.exports = {roundedRectPng, writeRoundedRectPng, encodePng, crc32};
