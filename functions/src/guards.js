'use strict';

/**
 * Cost guards for the montage pipeline (audit 2026-11-05, WP-04).
 *
 * Every montage is a 2 GiB, up-to-540 s ffmpeg run, and the project's hard
 * rule is zero ongoing cost behind a budget alarm. Before these guards, any
 * anonymous guest could:
 *   - post three videos under a made-up taskId and get a render on demand;
 *   - call `renderMontageNow` with `force` as often as they liked.
 *
 * The rules here are pure (no Firebase), so each one is unit-tested, and the
 * Firestore glue in `index.js` / `pipeline.js` only wires them up.
 */

const {HttpsError} = require('firebase-functions/v2/https');

const {STARTER_TASK_IDS, isMontageablePost, isStarterTask} = require('./contract');

/**
 * Montage-queue admissions per uid per UTC day. A post past this still lands
 * in the feed and is still spliced into the next render of its task (renders
 * read every post for the task); it just does not count toward triggering one.
 * So the cap bounds how many renders one uid can provoke, not what they see.
 */
const MONTAGE_QUEUE_PER_UID_PER_DAY = 5;

/** Collection holding the per-uid counters: montage_quota/{uid}/days/{yyyyMMdd}. */
const MONTAGE_QUOTA = 'montage_quota';

/** yyyyMMdd in UTC. Same key as storage.rules and VideoPolicy.dayKey(). */
function dayKey(date) {
  const d = date instanceof Date ? date : new Date(date);
  const two = (n) => String(n).padStart(2, '0');
  return `${d.getUTCFullYear()}${two(d.getUTCMonth() + 1)}${two(d.getUTCDate())}`;
}

/** True only for a real Starter Pack task id (not just any `starter-*`). */
function isKnownStarterTask(taskId) {
  return isStarterTask(taskId) && STARTER_TASK_IDS.has(taskId);
}

/**
 * Is `uid` a participant in `game`? `playerIds` is the flat list the rules use;
 * `players[].userId` and `creatorId` cover older game documents written before
 * `playerIds` existed.
 */
function isGameMember(game, uid) {
  if (!game || !uid) return false;
  if (Array.isArray(game.playerIds) && game.playerIds.includes(uid)) return true;
  if (Array.isArray(game.players) && game.players.some((p) => p && p.userId === uid)) {
    return true;
  }
  return game.creatorId === uid;
}

/**
 * Should this new feed post be allowed to queue (and so eventually trigger) a
 * montage render?
 *
 * A post qualifies when it is a montageable video by a real user AND either
 *   - its taskId is one of the Starter Pack ids (rendered once, shared by
 *     everyone, in the fixed 'starter' scope), or
 *   - the poster is a member of `games/{gameId}` (passed in as `game`; null
 *     when the doc does not exist).
 * Anything else — a made-up taskId, a made-up gameId, someone else's game — is
 * ignored: the post still shows in the feed, it just never costs a render.
 *
 * @param {{post: object, game: object|null}} args
 * @returns {{ok: boolean, reason: string}}
 */
function admitPost({post, game}) {
  if (!isMontageablePost(post)) return {ok: false, reason: 'not-montageable'};
  if (!post.gameId || !post.taskId) return {ok: false, reason: 'missing-ids'};
  if (!post.userId || post.userId === 'house') return {ok: false, reason: 'no-user'};
  if (isStarterTask(post.taskId)) {
    return isKnownStarterTask(post.taskId)
      ? {ok: true, reason: 'starter'}
      : {ok: false, reason: 'unknown-starter-task'};
  }
  if (!game) return {ok: false, reason: 'no-game'};
  if (!isGameMember(game, post.userId)) return {ok: false, reason: 'not-a-member'};
  const tasks = Array.isArray(game.tasks) ? game.tasks : null;
  if (tasks && !tasks.some((t) => t && t.id === post.taskId)) {
    return {ok: false, reason: 'unknown-task'};
  }
  return {ok: true, reason: 'member'};
}

/**
 * The quota verdict for one more admission, given how many this uid already
 * has today.
 * @returns {{ok: boolean, count: number}} `count` is the value to store.
 */
function takeQuota(used, limit = MONTAGE_QUEUE_PER_UID_PER_DAY) {
  const n = Number(used) || 0;
  if (n >= limit) return {ok: false, count: n};
  return {ok: true, count: n + 1};
}

/**
 * Gate for debug / operator callables. Requires a signed-in caller with the
 * `admin` custom claim (set with the Admin SDK: setCustomUserClaims(uid,
 * {admin: true})). Anonymous guests can never hold it.
 * @throws {HttpsError} unauthenticated | permission-denied
 */
function requireAdmin(request) {
  const auth = request && request.auth;
  if (!auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  if (!auth.token || auth.token.admin !== true) {
    throw new HttpsError('permission-denied', 'Admins only.');
  }
}

module.exports = {
  MONTAGE_QUEUE_PER_UID_PER_DAY,
  MONTAGE_QUOTA,
  dayKey,
  isKnownStarterTask,
  isGameMember,
  admitPost,
  takeQuota,
  requireAdmin,
};
