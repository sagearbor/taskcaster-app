'use strict';

/**
 * The Firestore side of the montage queue: admitting a new post, claiming a
 * render, and finalizing it. Split out of index.js so the transactions can be
 * exercised against an in-memory Firestore (test/fake_firestore.js) with no
 * emulator and no ffmpeg.
 *
 * `db` is anything with the Admin SDK's `collection().doc()` and
 * `runTransaction(fn)` surface.
 */

const {
  montageDocId,
  isMontageablePost,
  isStarterTask,
  decideRender,
  applyNewPost,
  finalizeBookkeeping,
} = require('./contract');
const {MONTAGE_QUOTA, admitPost, takeQuota, dayKey} = require('./guards');
const {hostMayMontage} = require('./entitlements');

const MONTAGES = 'montages';
const GAMES = 'games';

const montageRef = (db, gameId, taskId) =>
  db.collection(MONTAGES).doc(montageDocId(gameId, taskId));

const quotaRef = (db, uid, now) =>
  db.collection(MONTAGE_QUOTA).doc(uid).collection('days').doc(dayKey(now));

/**
 * Admit the post (real starter task, or the poster is a member of the game),
 * charge the poster's daily quota and bump the montage queue, all in one
 * transaction so a burst of posts cannot overshoot the quota.
 *
 * @returns {Promise<{queued: boolean, reason: string, decision?: object}>}
 */
async function queuePost(db, post, now) {
  const nowIso = now.toISOString();
  const ref = montageRef(db, post.gameId, post.taskId);
  const qRef = quotaRef(db, post.userId, now);
  return db.runTransaction(async (tx) => {
    // Every read before any write (a Firestore transaction requirement).
    const quotaSnap = await tx.get(qRef);
    const existing = await tx.get(ref);

    const quota = takeQuota(quotaSnap.exists ? quotaSnap.data().count : 0);
    if (!quota.ok) return {queued: false, reason: 'quota'};
    tx.set(qRef, {count: quota.count, updatedAt: nowIso}, {merge: true});

    const data = existing.exists ? existing.data() : null;
    const update = applyNewPost(data, post, nowIso);
    tx.set(ref, update, {merge: true});
    return {
      queued: true,
      reason: 'queued',
      decision: decideRender({...(data || {}), ...update}, now.getTime()),
    };
  });
}

/**
 * `onFeedPostCreated`, minus the Cloud Functions wrapper.
 *
 * @param {object} post the new feed post, with `id`
 * @param {{db: object, render: Function, now?: () => Date}} deps
 * @returns {Promise<{queued: boolean, reason: string, decision?: object, rendered?: boolean}>}
 */
async function handleNewPost(post, {db, render, now = () => new Date()}) {
  if (!isMontageablePost(post)) return {queued: false, reason: 'not-montageable'};

  // Starter tasks need no game read: admitPost checks the id against the list.
  let game = null;
  if (post.gameId && post.taskId && !isStarterTask(post.taskId)) {
    const snap = await db.collection(GAMES).doc(String(post.gameId)).get();
    game = snap.exists ? snap.data() : null;
  }
  const admit = admitPost({post, game});
  if (!admit.ok) return {queued: false, reason: admit.reason};

  // WP-11: a friend game's montages are a Pro feature of its HOST. A free
  // host's game still plays fine (Watch together is client-side); it just
  // never costs a render. Starter Pack montages stay free for everyone.
  if (admit.reason === 'member' && !(await hostMayMontage(db, game, now().getTime()))) {
    return {queued: false, reason: 'host-not-pro'};
  }

  const result = await queuePost(db, post, now());
  if (result.queued && result.decision.render) {
    await render(post.gameId, post.taskId);
    result.rendered = true;
  }
  return result;
}

/**
 * Claim the montage doc so two instances never encode the same task at once.
 * Records how many pending posts this render is taking responsibility for, so
 * finalize can leave any that arrive mid-render pending.
 *
 * @returns {Promise<{claimed: boolean, version: number, pendingCount?: number,
 *   claimedAt?: string, reason?: string}>}
 */
async function claim(db, ref, {force = false, now = () => new Date()} = {}) {
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return {claimed: false, version: 0, reason: 'no-doc'};
    const data = snap.data();
    const at = now();
    const decision = decideRender(data, at.getTime());
    if (!force && decision.reason === 'locked') {
      return {claimed: false, version: Number(data.version) || 0, reason: 'locked'};
    }
    const claimedAt = at.toISOString();
    tx.set(ref, {lockedAt: claimedAt}, {merge: true});
    return {
      claimed: true,
      version: Number(data.version) || 0,
      pendingCount: Number(data.pendingCount) || 0,
      claimedAt,
    };
  });
}

/**
 * Publish a finished render. `doc` is the result fields (URLs, clip count,
 * version, ...); the queue bookkeeping is computed from the doc as it is NOW,
 * inside the transaction, so a post that landed during the render keeps the
 * montage pending instead of being zeroed away.
 *
 * @returns {Promise<object>} what was written
 */
async function finalize(db, ref, doc, claimResult) {
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const current = snap.exists ? snap.data() : null;
    const written = {
      ...doc,
      ...finalizeBookkeeping(current, claimResult.pendingCount, claimResult.claimedAt),
      lockedAt: null,
    };
    tx.set(ref, written, {merge: true});
    return written;
  });
}

module.exports = {
  MONTAGES,
  GAMES,
  montageRef,
  quotaRef,
  queuePost,
  handleNewPost,
  claim,
  finalize,
};
