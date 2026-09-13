'use strict';

/**
 * The data contract between the Flutter app, Storage and the montage renderer,
 * expressed as pure functions so every rule here is unit-testable without
 * Firebase.
 *
 * IN  — `feed_posts/{postId}`:
 *   gameId, taskId, taskTitle, userId, displayName, mediaType, videoUrl,
 *   videoStoragePath, videoDurationSeconds, clockOffsetSeconds, timerSeconds,
 *   elapsedSeconds, isLate, isHouse, createdAt (ISO string), tapSeconds.
 *
 * OUT — `montages/{gameId}_{taskId}`:
 *   {gameId, taskId, finaleUrl, momentsUrl, sourcePostIds, clipCount,
 *    status: 'pending'|'ready'|'failed', error?, updatedAt (ISO), version}
 *   plus the renderer's own bookkeeping: pendingCount, pendingSince, lockedAt.
 *
 * OUT — Storage: `montages/{gameId}/{taskId}/finale.mp4` and `moments.mp4`.
 */

/** Render as soon as this many un-montaged videos have landed. */
const RENDER_AT_CLIP_COUNT = 3;

/** …otherwise render once the first of them is this old. */
const SETTLE_MINUTES = 30;

/** A claim older than this is treated as a crashed run and may be retaken. */
const LOCK_MINUTES = 15;

/** Hard cap on clips per montage — bounds /tmp usage and render time. */
const MAX_CLIPS = 12;

/**
 * The scope a montage is rendered over. Starter Pack tasks (`starter-*`) are
 * played in a separate solo game per player, but the Arena shows them
 * cross-game by taskId, so their finale must splice EVERY player's clip: the
 * scope is the literal 'starter'. Any other task is scoped to its game.
 * The app applies the identical rule (Montage.idFor) to find the document.
 */
const STARTER_SCOPE = 'starter';
const isStarterTask = (taskId) => typeof taskId === 'string' && taskId.startsWith('starter-');
const montageScope = (gameId, taskId) => (isStarterTask(taskId) ? STARTER_SCOPE : gameId);

const montageDocId = (gameId, taskId) => `${montageScope(gameId, taskId)}_${taskId}`;

const finaleObjectPath = (gameId, taskId) =>
  `montages/${montageScope(gameId, taskId)}/${taskId}/finale.mp4`;
const momentsObjectPath = (gameId, taskId) =>
  `montages/${montageScope(gameId, taskId)}/${taskId}/moments.mp4`;

/**
 * The anyone-can-read download URL. `montages/` is world-readable in
 * storage.rules, so no token is needed.
 */
function publicUrl(bucket, objectPath) {
  return `https://firebasestorage.googleapis.com/v0/b/${bucket}/o/` +
    `${encodeURIComponent(objectPath)}?alt=media`;
}

/**
 * The bucket object path behind a Firebase download URL, or `null`.
 * Handles both the `/v0/b/<bucket>/o/<encoded>` and the
 * `storage.googleapis.com/<bucket>/<path>` forms.
 */
function storagePathFromUrl(url) {
  if (!url || typeof url !== 'string') return null;
  const firebase = url.match(/\/v0\/b\/[^/]+\/o\/([^?]+)/);
  if (firebase) {
    try {
      return decodeURIComponent(firebase[1]);
    } catch {
      return null;
    }
  }
  const gcs = url.match(/^https?:\/\/storage\.googleapis\.com\/[^/]+\/(.+?)(?:\?|$)/);
  if (gcs) {
    try {
      return decodeURIComponent(gcs[1]);
    } catch {
      return null;
    }
  }
  return null;
}

/** The bucket object path for a feed post's video, or `null` if it has none. */
function objectPathForPost(post) {
  if (post.videoStoragePath) return String(post.videoStoragePath);
  return storagePathFromUrl(post.videoUrl);
}

function timestampOf(value) {
  if (!value) return 0;
  if (typeof value === 'string') {
    const parsed = Date.parse(value);
    return Number.isFinite(parsed) ? parsed : 0;
  }
  if (value instanceof Date) return value.getTime();
  if (typeof value.toDate === 'function') return value.toDate().getTime();
  if (typeof value.seconds === 'number') return value.seconds * 1000;
  if (typeof value === 'number') return value;
  return 0;
}

/**
 * True when a feed post is a real player video that belongs in a montage.
 * House entries are excluded (they are the prompt, not an attempt).
 */
function isMontageablePost(post, taskId) {
  if (!post) return false;
  if (taskId !== undefined && post.taskId !== taskId) return false;
  if (post.mediaType !== 'video') return false;
  if (post.isHouse === true) return false;
  return Boolean(objectPathForPost(post));
}

/**
 * Pick and order the clips for one task's montage.
 *
 * Deliberately takes ALL of a game's posts: the renderer queries on `gameId`
 * alone so Firestore needs no composite index, and filters here.
 *
 * @param {Array<object>} posts documents (with `id`) from `feed_posts`
 * @param {{taskId:string, maxClips?:number}} opts
 * @returns {Array<object>} oldest-first, capped at `maxClips` (keeping the
 *   most recent ones when there are too many)
 */
function selectClips(posts, {taskId, maxClips = MAX_CLIPS} = {}) {
  const usable = (posts || [])
    .filter((p) => isMontageablePost(p, taskId))
    .sort((a, b) => timestampOf(a.createdAt) - timestampOf(b.createdAt));
  return usable.length > maxClips ? usable.slice(usable.length - maxClips) : usable;
}

/**
 * Should `montages/{id}` be rendered right now?
 *
 * Rules (from the brief):
 *   - only `pending` docs render;
 *   - `pendingCount >= 3` renders immediately (the room is clearly playing);
 *   - otherwise wait until the first pending post is `SETTLE_MINUTES` old, so
 *     a slow trickle still gets a montage;
 *   - a fresh claim by another instance blocks a second render.
 *
 * Pure: `now` is injected, no clock reads, no Firebase types.
 *
 * @param {object|null} doc the montage document data (or null when missing)
 * @param {number|Date} now
 * @returns {{render: boolean, reason: string}}
 */
function decideRender(doc, now, opts = {}) {
  const {
    minClips = RENDER_AT_CLIP_COUNT,
    settleMinutes = SETTLE_MINUTES,
    lockMinutes = LOCK_MINUTES,
  } = opts;
  const nowMs = now instanceof Date ? now.getTime() : Number(now);

  if (!doc) return {render: false, reason: 'no-doc'};
  if (doc.status !== 'pending') return {render: false, reason: 'not-pending'};

  const lockedAt = timestampOf(doc.lockedAt);
  if (lockedAt && nowMs - lockedAt < lockMinutes * 60000) {
    return {render: false, reason: 'locked'};
  }

  const pendingCount = Number(doc.pendingCount) || 0;
  if (pendingCount >= minClips) return {render: true, reason: 'threshold'};

  const pendingSince = timestampOf(doc.pendingSince);
  if (pendingCount > 0 && pendingSince && nowMs - pendingSince >= settleMinutes * 60000) {
    return {render: true, reason: 'settled'};
  }

  return {render: false, reason: 'waiting'};
}

/**
 * The `montages/{id}` update a newly created video post produces.
 *
 * Pure, so the "3 posts render now, fewer wait for the settle window" rule can
 * be exercised end to end in a unit test with no Firestore.
 *
 * @param {object|null} existing current document data (null when it is new)
 * @param {object} post the feed post
 * @param {string} nowIso ISO timestamp for this write
 * @returns {object} fields to merge into the montage doc
 */
function applyNewPost(existing, post, nowIso) {
  const pendingCount = (Number(existing && existing.pendingCount) || 0) + 1;
  const update = {
    gameId: post.gameId,
    taskId: post.taskId,
    taskTitle: post.taskTitle || (existing && existing.taskTitle) || '',
    status: 'pending',
    pendingCount,
    pendingSince: (existing && existing.pendingSince) || nowIso,
    updatedAt: nowIso,
  };
  if (!existing) {
    update.version = 0;
    update.clipCount = 0;
    update.sourcePostIds = [];
  }
  return update;
}

/**
 * The clip descriptor the montage library wants, from a feed post.
 * @param {object} post
 * @param {string} localPath where the clip was downloaded to
 */
function clipFromPost(post, localPath) {
  return {
    path: localPath,
    postId: post.id,
    timerSeconds: Number(post.timerSeconds) || 0,
    clockOffsetSeconds: Number(post.clockOffsetSeconds) || 0,
    isLate: post.isLate === true,
    tapSeconds: post.tapSeconds || null,
    durationSeconds: Number(post.videoDurationSeconds) > 0
      ? Number(post.videoDurationSeconds)
      : undefined,
    displayName: post.displayName || '',
  };
}

module.exports = {
  RENDER_AT_CLIP_COUNT,
  SETTLE_MINUTES,
  LOCK_MINUTES,
  MAX_CLIPS,
  montageDocId,
  montageScope,
  isStarterTask,
  STARTER_SCOPE,
  finaleObjectPath,
  momentsObjectPath,
  publicUrl,
  storagePathFromUrl,
  objectPathForPost,
  isMontageablePost,
  selectClips,
  decideRender,
  applyNewPost,
  clipFromPost,
  timestampOf,
};
