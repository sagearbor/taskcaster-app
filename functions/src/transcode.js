'use strict';

/**
 * Universal playback (audit WP-08): every player clip becomes a 720p H.264
 * SDR mp4 plus a poster JPEG, so an iPhone HEVC / HDR / Dolby Vision .MOV plays
 * on Android, Chrome, Firefox, Safari and iOS alike.
 *
 * Pure decisions + an ffmpeg runner + one orchestrator (`handleFinalized`)
 * whose Firebase access is injected, so all of it runs in unit tests without
 * Firebase. index.js holds the trigger glue and the real adapters.
 *
 * STORAGE LAYOUT (WP-11 and the retention sweep rely on this)
 *
 *   submissions/{uid}/{day}/{slot}       the clip. After a successful transcode
 *                                        the ORIGINAL BYTES ARE GONE: the
 *                                        object is replaced in place by the
 *                                        H.264 mp4 (custom metadata
 *                                        tcTranscoded='1').
 *   transcoded/{uid}/{day}/{slot}.jpg    the poster frame (public get).
 *
 *   Why in place rather than a second object at transcoded/...mp4 plus a
 *   delete: storage.rules makes the slot create-only (`resource == null`), and
 *   that is the whole daily cap (WP-04). Deleting the original would free the
 *   slot: the uploader walks slots 0..9 and would re-use it, so the cap would
 *   leak, the next clip would land on a path that is already "transcoded" and
 *   two posts would share one videoStoragePath. Replacing the bytes keeps the
 *   slot occupied, keeps every existing download URL (feed posts, game docs,
 *   already-shipped app builds) working and now pointing at H.264, and still
 *   stores one small file instead of the original. With Object Versioning on,
 *   the original lingers as a noncurrent version that the bucket lifecycle
 *   rule deletes after 1 day — exactly what a plain delete would do.
 *
 * CLIP METADATA — `clips/{uid}_{day}_{slot}` (server-only, Admin SDK)
 *
 *   uid, day, slot, sourcePath, sourceGeneration, sourceBytes,
 *   sourceContentType, gameId, taskId, status ('processing'|'ready'|'failed'),
 *   attempts, createdAt (server Timestamp, set once — the retention clock),
 *   retainUntil (when the WP-11 retention sweep next looks at it),
 *   lockedAt, and when ready: playbackPath, playbackUrl, posterPath,
 *   posterUrl, playbackGeneration, outputBytes, durationSeconds, width,
 *   height, sourceCodec, hdr, tonemapped, transcodedAt.
 *   An age-based sweep is `where('createdAt', '<', cutoff)` then delete
 *   playbackPath + posterPath + the doc; `uid` scopes it per user/plan.
 *
 * IDEMPOTENCY — never transcode the same object twice
 *
 *   1. Only `submissions/{uid}/{day}/{slot}` objects are considered (posters,
 *      montages and house clips fire the same trigger and are ignored).
 *   2. Our own in-place output carries tcTranscoded='1' and is ignored, so the
 *      replace does not loop.
 *   3. A transaction on the clip doc claims the work: a `ready` or `failed`
 *      doc is final, a fresh `processing` lock is someone else's, and a stale
 *      lock (crashed run) may be retaken at most MAX_ATTEMPTS times in total.
 *   4. The replace is conditional on the source generation (ifGenerationMatch),
 *      so a late duplicate can never clobber anything.
 */

const fs = require('fs');
const os = require('os');
const path = require('path');

const {runFfmpeg, runBinary, ffmpegPath} = require('./ffmpeg');
const {probe} = require('./analyze');
const {log} = require('./log');
const {LIMITS, FREE_RETENTION_DAYS, DAY_MS} = require('./plans');

const CLIPS = 'clips';

/** Upper bound of the output: 720p, either orientation. */
const MAX_SHORT_EDGE = 720;
const MAX_LONG_EDGE = 1280;

/** Output frame-rate ceiling; 60 fps iPhone clips are halved. */
const MAX_FPS = 30;

/**
 * Absolute clip ceiling (seconds): the Pro cap (plans.js LIMITS.pro). The
 * cap actually applied is the uploader's PLAN cap (deps.capSecondsFor, read
 * from users/{uid} on the server), which the upload's `clipCapSeconds`
 * metadata may only shorten, never lengthen.
 */
const MAX_CLIP_SECONDS = LIMITS.pro.clipSeconds;

/** The cap when no plan lookup is wired (or it fails): the free cap. */
const DEFAULT_CLIP_SECONDS = LIMITS.free.clipSeconds;

/**
 * Sanity bound on the source, a little over the largest upload storage.rules
 * allows (the Pro cap).
 */
const MAX_SOURCE_BYTES = LIMITS.pro.maxUploadBytes + 4 * 1024 * 1024;

/** A `processing` claim older than this is a crashed run. */
const LOCK_MINUTES = 10;

/** Total claims per clip, crashes included. Bounds CPU spent on a bad file. */
const MAX_ATTEMPTS = 2;

/** Metadata key marking our own output. */
const MARKER = 'tcTranscoded';

const VIDEO_ARGS = [
  '-c:v', 'libx264',
  '-profile:v', 'high',
  '-level', '4.0',
  '-preset', 'veryfast',
  '-crf', '26',
  '-pix_fmt', 'yuv420p',
  '-color_primaries', 'bt709',
  '-color_trc', 'bt709',
  '-colorspace', 'bt709',
  '-color_range', 'tv',
  '-movflags', '+faststart',
];

const AUDIO_ARGS = ['-c:a', 'aac', '-b:a', '96k', '-ar', '44100', '-ac', '2'];

const HDR_TRANSFERS = new Set(['smpte2084', 'arib-std-b67']);

// ---------------------------------------------------------------------------
// Pure decisions
// ---------------------------------------------------------------------------

/**
 * `submissions/{uid}/{day}/{slot}` -> its parts, or null for any other path.
 * Segments are deliberately loose (WP-11 adds `submissions/{uid}/guest/{n}`
 * and letter slots); storage.rules is what restricts what can be written.
 */
function parseSubmissionPath(name) {
  if (typeof name !== 'string') return null;
  const m = name.match(/^submissions\/([A-Za-z0-9_-]{1,128})\/([A-Za-z0-9-]{1,16})\/([A-Za-z0-9-]{1,8})$/);
  if (!m) return null;
  return {uid: m[1], day: m[2], slot: m[3]};
}

const clipDocId = ({uid, day, slot}) => `${uid}_${day}_${slot}`;

const posterObjectPath = ({uid, day, slot}) => `transcoded/${uid}/${day}/${slot}.jpg`;

/**
 * Should this finalized object be transcoded at all? Cheap, no I/O: this runs
 * for EVERY object written to the bucket.
 * @returns {{handle: boolean, reason: string, parts?: object}}
 */
function shouldTranscode(object) {
  if (!object || !object.name) return {handle: false, reason: 'no-object'};
  const parts = parseSubmissionPath(object.name);
  if (!parts) return {handle: false, reason: 'not-a-submission'};
  const meta = object.metadata || {};
  if (meta[MARKER] === '1') return {handle: false, reason: 'own-output'};
  const contentType = String(object.contentType || '');
  if (!contentType.startsWith('video/')) return {handle: false, reason: 'not-video'};
  const size = Number(object.size) || 0;
  if (size <= 0) return {handle: false, reason: 'empty'};
  if (size > MAX_SOURCE_BYTES) return {handle: false, reason: 'too-large'};
  return {handle: true, reason: 'ok', parts};
}

/**
 * The claim decision for a clip doc, inside the claim transaction.
 * @param {object|null} existing clip doc data, or null
 * @param {string} generation the source object's generation
 * @param {number} nowMs
 * @returns {{claim: boolean, reason: string, attempts?: number}}
 */
function decideClaim(existing, generation, nowMs) {
  if (!existing) return {claim: true, reason: 'new', attempts: 1};
  if (existing.status === 'ready') return {claim: false, reason: 'already-transcoded'};
  if (existing.status === 'failed') return {claim: false, reason: 'already-failed'};
  if (existing.sourceGeneration && String(existing.sourceGeneration) !== String(generation)) {
    // A different object at a path we have already seen. Slots are
    // create-only, so this should not happen; refuse rather than guess.
    return {claim: false, reason: 'generation-mismatch'};
  }
  const attempts = Number(existing.attempts) || 0;
  const lockedAt = millisOf(existing.lockedAt);
  if (existing.status === 'processing' && lockedAt && nowMs - lockedAt < LOCK_MINUTES * 60000) {
    return {claim: false, reason: 'in-progress'};
  }
  if (attempts >= MAX_ATTEMPTS) return {claim: false, reason: 'attempts-exhausted'};
  return {claim: true, reason: 'retake-stale', attempts: attempts + 1};
}

function millisOf(value) {
  if (!value) return 0;
  if (typeof value === 'number') return value;
  if (typeof value === 'string') return Date.parse(value) || 0;
  if (value instanceof Date) return value.getTime();
  if (typeof value.toMillis === 'function') return value.toMillis();
  if (typeof value.seconds === 'number') return value.seconds * 1000;
  return 0;
}

/**
 * The output duration cap: the plan's server cap (bounded by
 * MAX_CLIP_SECONDS), shortened by a sane metadata cap.
 */
function clipCapSeconds(metadata, serverCap = DEFAULT_CLIP_SECONDS) {
  let cap = Number(serverCap);
  if (!Number.isFinite(cap) || cap < 1) cap = DEFAULT_CLIP_SECONDS;
  cap = Math.min(cap, MAX_CLIP_SECONDS);
  const requested = Number(metadata && metadata.clipCapSeconds);
  if (Number.isFinite(requested) && requested >= 1 && requested < cap) {
    return requested;
  }
  return cap;
}

const even = (n) => Math.max(2, Math.round(n / 2) * 2);

/** Fit inside 720p (short edge <= 720, long edge <= 1280), never upscaling. */
function fit720(width, height) {
  const w = Number(width) || 0;
  const h = Number(height) || 0;
  if (w <= 0 || h <= 0) return {width: 1280, height: 720};
  const long = Math.max(w, h);
  const short = Math.min(w, h);
  const scale = Math.min(1, MAX_LONG_EDGE / long, MAX_SHORT_EDGE / short);
  return {width: even(w * scale), height: even(h * scale)};
}

/** True for PQ (HDR10 / Dolby Vision) and HLG sources. */
function isHdr(info) {
  return HDR_TRANSFERS.has(String(info && info.colorTransfer));
}

/** Needs a primaries conversion even when it is not HDR (wide-gamut SDR). */
function isWideGamut(info) {
  return String(info && info.colorPrimaries) === 'bt2020';
}

/**
 * The -vf chain. HDR goes through zscale + tonemap (hable) to BT.709 SDR;
 * without zscale it degrades to a plain matrix conversion (washed out, but
 * still H.264 that plays everywhere).
 */
function videoFilter({info, width, height, zscale}) {
  const fpsCap = Number(info && info.fps) > MAX_FPS + 0.5 ? `,fps=${MAX_FPS}` : '';
  if ((isHdr(info) || isWideGamut(info)) && zscale) {
    // Resize in the FIRST zscale so the float/linear steps run at 720p, not 4K.
    const chain = isHdr(info)
      ? `zscale=w=${width}:h=${height}:t=linear:npl=100,format=gbrpf32le,` +
        'zscale=p=bt709,tonemap=tonemap=hable:desat=0,' +
        'zscale=t=bt709:m=bt709:r=tv'
      : `zscale=w=${width}:h=${height}:p=bt709:t=bt709:m=bt709:r=tv`;
    return `${chain},format=yuv420p,setsar=1${fpsCap}`;
  }
  return `scale=${width}:${height}:flags=bicubic:out_color_matrix=bt709:out_range=tv,` +
    `format=yuv420p,setsar=1${fpsCap}`;
}

/** ffmpeg args for the clip. Strips all container metadata (GPS, device). */
function transcodeArgs({input, output, info, maxSeconds, zscale}) {
  const {width, height} = fit720(info.width, info.height);
  return [
    // Bounded threads: Cloud Run can report the host's cores, and every
    // decoder frame thread holds full-resolution (up to 4K 10-bit) frames.
    '-threads', '2',
    '-i', input,
    '-map', '0:v:0',
    '-map', '0:a:0?',
    '-map_metadata', '-1',
    '-map_chapters', '-1',
    '-t', String(maxSeconds),
    '-vf', videoFilter({info, width, height, zscale}),
    ...VIDEO_ARGS,
    '-threads', '2',
    ...AUDIO_ARGS,
    output,
  ];
}

/** ffmpeg args for the poster: one frame from the (already SDR) output. */
function posterArgs({input, output, durationSeconds}) {
  const d = Number(durationSeconds) || 0;
  const at = d > 0 ? Math.min(1, d / 3) : 0;
  return ['-ss', at.toFixed(3), '-i', input, '-frames:v', '1', '-q:v', '5', output];
}

// ---------------------------------------------------------------------------
// ffmpeg
// ---------------------------------------------------------------------------

let zscaleChecked = null;

/** Whether the resolved ffmpeg has zscale + tonemap (libzimg). Cached. */
async function hasZscale() {
  if (zscaleChecked !== null) return zscaleChecked;
  try {
    const {stdout} = await runBinary(ffmpegPath(), ['-hide_banner', '-filters'], {label: 'ffmpeg-caps'});
    zscaleChecked = /\bzscale\b/.test(stdout) && /\btonemap\b/.test(stdout);
  } catch {
    zscaleChecked = false;
  }
  if (!zscaleChecked) log('[transcode] no zscale/tonemap in ffmpeg; HDR clips will not be tone-mapped');
  return zscaleChecked;
}

/**
 * Transcode one local file into `outDir`: `clip.mp4` + `poster.jpg`.
 * @returns {Promise<{videoPath:string, posterPath:string, source:object,
 *   output:object, hdr:boolean, tonemapped:boolean}>}
 */
async function transcodeFile(input, outDir, {maxSeconds = DEFAULT_CLIP_SECONDS, timeoutMs} = {}) {
  // ~4 s of encode per output second on 1 vCPU for a 4K HEVC source, plus slack.
  if (!timeoutMs) timeoutMs = Math.max(240000, maxSeconds * 8000);
  const source = await probe(input);
  const zscale = await hasZscale();
  const videoPath = path.join(outDir, 'clip.mp4');
  const posterPath = path.join(outDir, 'poster.jpg');
  await runFfmpeg(transcodeArgs({input, output: videoPath, info: source, maxSeconds, zscale}), {timeoutMs});
  const output = await probe(videoPath);
  await runFfmpeg(posterArgs({input: videoPath, output: posterPath, durationSeconds: output.durationSeconds}), {
    timeoutMs: 30000,
  });
  const hdr = isHdr(source);
  return {videoPath, posterPath, source, output, hdr, tonemapped: hdr && zscale};
}

// ---------------------------------------------------------------------------
// Orchestration
// ---------------------------------------------------------------------------

/**
 * Handle one `storage.object.finalized` event end to end.
 *
 * @param {object} object the CloudEvent's StorageObjectData
 *   ({name, bucket, generation, contentType, size, metadata})
 * @param {object} deps
 * @param {object} deps.store   clip doc + feed post access (see firestoreClipStore)
 * @param {object} deps.storage object access (see index.js gcsClipStorage)
 * @param {Function} [deps.transcode] defaults to transcodeFile (tests mock it)
 * @param {Function} [deps.capSecondsFor] async ({uid, day, slot}) -> the
 *   uploader's plan cap in seconds (WP-11); a failure falls back to the free cap
 * @param {number} [deps.nowMs]
 * @param {object} [deps.logger]
 * @returns {Promise<{status:string, reason?:string}>}
 */
async function handleFinalized(object, deps) {
  const {store, storage, transcode = transcodeFile, capSecondsFor, nowMs = Date.now(), logger = console} = deps;
  const decision = shouldTranscode(object);
  if (!decision.handle) return {status: 'skipped', reason: decision.reason};

  const {parts} = decision;
  const docId = clipDocId(parts);
  const meta = object.metadata || {};
  const generation = String(object.generation || '');

  const claim = await store.claim(docId, generation, nowMs, {
    uid: parts.uid,
    day: parts.day,
    slot: parts.slot,
    sourcePath: object.name,
    sourceGeneration: generation,
    sourceBytes: Number(object.size) || 0,
    sourceContentType: String(object.contentType || ''),
    gameId: typeof meta.gameId === 'string' ? meta.gameId : null,
    taskId: typeof meta.taskId === 'string' ? meta.taskId : null,
  });
  if (!claim.claimed) return {status: 'skipped', reason: claim.reason};

  const workDir = fs.mkdtempSync(path.join(os.tmpdir(), 'transcode-'));
  try {
    const input = path.join(workDir, 'source');
    await storage.download(object.name, input, generation);

    let serverCap = DEFAULT_CLIP_SECONDS;
    if (capSecondsFor) {
      try {
        serverCap = await capSecondsFor(parts);
      } catch (err) {
        logger.warn('transcode: plan lookup failed, using the free cap', {path: object.name, error: err.message});
      }
    }
    const result = await transcode(input, workDir, {maxSeconds: clipCapSeconds(meta, serverCap)});

    // Replace first: if the clip was deleted meanwhile (account deletion),
    // the generation precondition fails here and no orphan poster is written.
    const posterPath = posterObjectPath(parts);
    const replaced = await storage.replaceInPlace(object.name, result.videoPath, {
      ifGenerationMatch: generation,
      metadata: {
        [MARKER]: '1',
        tcSourceGeneration: generation,
        tcSourceContentType: String(object.contentType || ''),
        tcSourceCodec: result.source.codec || '',
        tcHdr: result.hdr ? '1' : '0',
      },
    });

    await storage.uploadPoster(result.posterPath, posterPath);

    const outputBytes = fs.statSync(result.videoPath).size;
    const playbackUrl = storage.publicUrl(object.name);
    const posterUrl = storage.publicUrl(posterPath);
    const durationSeconds = Math.round(result.output.durationSeconds * 100) / 100;

    await store.complete(docId, {
      status: 'ready',
      playbackPath: object.name,
      playbackUrl,
      playbackGeneration: replaced && replaced.generation ? String(replaced.generation) : null,
      posterPath,
      posterUrl,
      outputBytes,
      durationSeconds,
      width: result.output.width,
      height: result.output.height,
      sourceCodec: result.source.codec || null,
      hdr: result.hdr,
      tonemapped: result.tonemapped,
    });

    // Posts written before the transcode finished. A post written after it
    // picks the URLs up in onFeedPostCreated (applyClipToPost).
    const postIds = await store.postIdsForPath(object.name);
    for (const postId of postIds) {
      // eslint-disable-next-line no-await-in-loop
      await store.updatePost(postId, postPlaybackFields({playbackUrl, posterUrl, outputBytes, durationSeconds}));
    }

    logger.info('transcode: ready', {
      path: object.name, hdr: result.hdr, tonemapped: result.tonemapped,
      sourceBytes: Number(object.size) || 0, outputBytes, posts: postIds.length,
    });
    return {status: 'ready', posts: postIds.length};
  } catch (err) {
    logger.error('transcode: failed', {path: object.name, error: err.message});
    await store.fail(docId, String(err.message).slice(0, 1500)).catch(() => {});
    return {status: 'failed', reason: err.message};
  } finally {
    try {
      fs.rmSync(workDir, {recursive: true, force: true});
    } catch {
      /* best effort */
    }
  }
}

/** The feed-post fields a finished transcode sets. Server-only fields. */
function postPlaybackFields({playbackUrl, posterUrl, outputBytes, durationSeconds}) {
  return {
    playbackUrl,
    posterUrl,
    videoContentType: 'video/mp4',
    videoBytes: outputBytes,
    videoDurationSeconds: durationSeconds,
  };
}

/**
 * For a newly created feed post: if its clip has already been transcoded,
 * the fields to copy onto it, else null. Pure.
 */
function playbackFieldsForPost(post, clip) {
  if (!post || post.mediaType !== 'video' || post.playbackUrl) return null;
  if (!clip || clip.status !== 'ready' || !clip.playbackUrl) return null;
  return postPlaybackFields({
    playbackUrl: clip.playbackUrl,
    posterUrl: clip.posterUrl || null,
    outputBytes: clip.outputBytes,
    durationSeconds: clip.durationSeconds,
  });
}

/**
 * onFeedPostCreated helper: copy a finished transcode onto a post that was
 * created after it (the post usually lands first, but not always).
 */
async function applyClipToPost(post, {store}) {
  const parts = parseSubmissionPath(post && post.videoStoragePath);
  if (!parts || post.mediaType !== 'video') return {applied: false, reason: 'not-a-clip'};
  const clip = await store.getClip(clipDocId(parts));
  const fields = playbackFieldsForPost(post, clip);
  if (!fields) return {applied: false, reason: clip ? `clip-${clip.status}` : 'no-clip'};
  await store.updatePost(post.id, fields);
  return {applied: true, fields};
}

// ---------------------------------------------------------------------------
// Firestore adapter
// ---------------------------------------------------------------------------

/**
 * The clip store over the Admin SDK.
 * @param {{db: object, FieldValue: object, feedPosts?: string}} opts
 */
function firestoreClipStore({db, FieldValue, feedPosts = 'feed_posts'}) {
  const ref = (id) => db.collection(CLIPS).doc(id);
  return {
    async claim(docId, generation, nowMs, fields) {
      return db.runTransaction(async (tx) => {
        const snap = await tx.get(ref(docId));
        const existing = snap.exists ? snap.data() : null;
        const d = decideClaim(existing, generation, nowMs);
        if (!d.claim) return {claimed: false, reason: d.reason};
        tx.set(ref(docId), {
          ...fields,
          status: 'processing',
          attempts: d.attempts,
          lockedAt: new Date(nowMs).toISOString(),
          // createdAt is the retention clock; retainUntil is when the WP-11
          // sweep (retention.js) first looks at the clip.
          ...(existing ? {} : {
            createdAt: FieldValue.serverTimestamp(),
            retainUntil: new Date(nowMs + FREE_RETENTION_DAYS * DAY_MS),
          }),
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
        return {claimed: true, reason: d.reason};
      });
    },
    async complete(docId, data) {
      await ref(docId).set({
        ...data,
        lockedAt: null,
        error: FieldValue.delete(),
        transcodedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    },
    async fail(docId, error) {
      await ref(docId).set({
        status: 'failed',
        error,
        lockedAt: null,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    },
    async getClip(docId) {
      const snap = await ref(docId).get();
      return snap.exists ? snap.data() : null;
    },
    async postIdsForPath(objectPath) {
      const snap = await db.collection(feedPosts).where('videoStoragePath', '==', objectPath).get();
      return snap.docs.map((d) => d.id);
    },
    async updatePost(postId, fields) {
      try {
        // update(), not set(merge): a post the author deleted must stay gone.
        await db.collection(feedPosts).doc(postId).update(fields);
      } catch (err) {
        if (err && (err.code === 5 || err.code === 'not-found')) return;
        throw err;
      }
    },
  };
}

module.exports = {
  CLIPS,
  MARKER,
  MAX_CLIP_SECONDS,
  DEFAULT_CLIP_SECONDS,
  MAX_SOURCE_BYTES,
  MAX_ATTEMPTS,
  LOCK_MINUTES,
  parseSubmissionPath,
  clipDocId,
  posterObjectPath,
  shouldTranscode,
  decideClaim,
  clipCapSeconds,
  fit720,
  isHdr,
  videoFilter,
  transcodeArgs,
  posterArgs,
  hasZscale,
  transcodeFile,
  handleFinalized,
  playbackFieldsForPost,
  applyClipToPost,
  firestoreClipStore,
};
