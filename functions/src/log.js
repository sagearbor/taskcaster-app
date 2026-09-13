'use strict';

/**
 * One logging seam for the whole montage pipeline, so tests can silence the
 * (very chatty) ffmpeg command log with MONTAGE_QUIET=1.
 */

function log(...args) {
  if (process.env.MONTAGE_QUIET === '1') return;
  console.log(...args);
}

function warn(...args) {
  if (process.env.MONTAGE_QUIET === '1') return;
  console.warn(...args);
}

module.exports = {log, warn};
