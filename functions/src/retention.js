'use strict';

/**
 * Clip retention sweep (audit WP-11). Owner rule 2026-11-05: never keep data
 * forever. The verdict for one clip is plans.js clipRetention():
 *
 *   free / guest   deleted 90 days after createdAt; a "keeper" (spliced into
 *                  a montage, or graded 4+ on average) after 1 year
 *   pro (active)   kept while subscribed
 *   pro, lapsed    free rules, but at least 90 days and at most 1 year after
 *                  the lapse date (users/{uid}.planLapsedAt)
 *
 * Account deletion is not this file's job: account_deletion.js removes
 * everything immediately.
 *
 * HOW IT STAYS CHEAP (no full scans)
 *
 *   Every clips/{id} doc carries `retainUntil`: the next moment its verdict
 *   could change. transcode.js stamps it at createdAt + 90 days, and every
 *   time the sweep keeps a clip it moves `retainUntil` to that clip's
 *   deadline (or, for an active Pro user, to the end of the paid period). So
 *   the daily run is one paged query, `retainUntil <= now` ordered by
 *   retainUntil, and touches only clips that are actually due. A kept clip
 *   leaves the result set, so the next page is simply the same query again.
 *
 *   Clips created before WP-11 have no `retainUntil`. A second, cursor-driven
 *   query walks `createdAt <= now - 90 days` in createdAt order exactly once
 *   (the cursor lives in retention_state/clips), evaluating each legacy clip
 *   it meets and skipping the ones that already have `retainUntil`.
 *
 *   Each run is bounded (MAX_PAGES x PAGE_SIZE); a backlog drains over days.
 *
 * IDEMPOTENT
 *
 *   Delete order is Storage objects (404 is fine), then the feed posts that
 *   pointed at the clip are marked `videoExpired`, then the clip doc. A crash
 *   anywhere leaves the doc due, so the next run finishes the job.
 *
 * `store` and `storage` are injected (firestoreRetentionStore below, and
 * index.js); tests use in-memory fakes.
 */

const {
  FREE_RETENTION_DAYS,
  KEEPER_MIN_AVG_GRADE,
  DAY_MS,
  toMillis,
  averageGrade,
  clipRetention,
} = require('./plans');
const {posterObjectPath} = require('./transcode');

const CLIPS = 'clips';
const RETENTION_STATE = 'retention_state';
const STATE_DOC = 'clips';

const PAGE_SIZE = 200;
const MAX_PAGES = 10;
const LEGACY_PAGES = 2;

/** Is this clip a keeper? Only asked when the free verdict would delete it. */
async function isKeeper(store, clip) {
  const objectPath = clip.playbackPath || clip.sourcePath;
  if (!objectPath) return false;
  const posts = await store.postsForPath(objectPath);
  if (posts.some((p) => averageGrade(p) >= KEEPER_MIN_AVG_GRADE)) return true;
  for (const post of posts) {
    // eslint-disable-next-line no-await-in-loop
    if (await store.inMontage(post.id)) return true;
  }
  return false;
}

/**
 * Evaluate one clip and act on it.
 * @returns {Promise<'deleted'|'kept'>}
 */
async function processClip({id, clip}, {store, storage, now, users, logger}) {
  const uid = clip.uid;
  if (!users.has(uid)) users.set(uid, await store.getUser(uid));
  const user = users.get(uid);
  const createdAtMs = toMillis(clip.createdAt);

  // The cheap verdict first (no keeper lookups): if even a non-keeper is
  // kept, a keeper certainly is, and its recheck time is the earlier one.
  let verdict = clipRetention({createdAtMs, user, keeper: false, now});
  if (verdict.action === 'delete' && await isKeeper(store, clip)) {
    verdict = clipRetention({createdAtMs, user, keeper: true, now});
  }

  if (verdict.action === 'keep') {
    await store.setRetainUntil(id, verdict.recheckAtMs);
    return 'kept';
  }

  const objectPath = clip.playbackPath || clip.sourcePath;
  const parts = {uid: clip.uid, day: clip.day, slot: clip.slot};
  const poster = clip.posterPath || (parts.uid && parts.day && parts.slot !== undefined
    ? posterObjectPath(parts)
    : null);
  for (const p of [objectPath, poster]) {
    // eslint-disable-next-line no-await-in-loop
    if (p) await storage.deleteObject(p);
  }
  if (objectPath) {
    const posts = await store.postsForPath(objectPath);
    if (posts.length) await store.markPostsExpired(posts.map((p) => p.id), now);
  }
  await store.deleteClip(id);
  logger.info('retention: clip deleted', {clipId: id, uid, reason: verdict.reason});
  return 'deleted';
}

/**
 * One sweep. Safe to run as often as you like.
 *
 * @param {object} deps
 * @param {object} deps.store   see firestoreRetentionStore
 * @param {object} deps.storage {deleteObject(path)} (404 must not throw)
 * @param {number} [deps.now]
 * @param {number} [deps.pageSize]
 * @param {number} [deps.maxPages]
 * @param {number} [deps.legacyPages]
 * @param {object} [deps.logger]
 * @returns {Promise<{examined: number, deleted: number, kept: number, failed: number, legacyExamined: number}>}
 */
async function sweep(deps) {
  const {
    store,
    storage,
    now = Date.now(),
    pageSize = PAGE_SIZE,
    maxPages = MAX_PAGES,
    legacyPages = LEGACY_PAGES,
    logger = console,
  } = deps;
  const users = new Map();
  const stats = {examined: 0, deleted: 0, kept: 0, failed: 0, legacyExamined: 0};
  const ctx = {store, storage, now, users, logger};

  const handle = async (item) => {
    stats.examined += 1;
    try {
      const outcome = await processClip(item, ctx);
      stats[outcome] += 1;
    } catch (err) {
      stats.failed += 1;
      logger.error('retention: clip failed', {clipId: item.id, error: err.message});
      // Push it out a day so one bad clip cannot pin the due query.
      await store.setRetainUntil(item.id, now + DAY_MS).catch(() => {});
    }
  };

  // 1. Clips that are due. Each processed clip leaves the result set.
  for (let page = 0; page < maxPages; page += 1) {
    // eslint-disable-next-line no-await-in-loop
    const due = await store.dueClips(now, pageSize);
    for (const item of due) {
      // eslint-disable-next-line no-await-in-loop
      await handle(item);
    }
    if (due.length < pageSize) break;
  }

  // 2. Legacy clips (no retainUntil), walked once in createdAt order.
  const cutoff = now - FREE_RETENTION_DAYS * DAY_MS;
  let cursor = (await store.getState()).legacyCursor || null;
  for (let page = 0; page < legacyPages; page += 1) {
    // eslint-disable-next-line no-await-in-loop
    const batch = await store.legacyClips(cutoff, cursor, pageSize);
    for (const item of batch) {
      stats.legacyExamined += 1;
      // eslint-disable-next-line no-await-in-loop
      if (item.clip.retainUntil === undefined || item.clip.retainUntil === null) await handle(item);
    }
    if (batch.length) {
      const last = batch[batch.length - 1];
      cursor = {createdAtMs: toMillis(last.clip.createdAt), id: last.id};
      // eslint-disable-next-line no-await-in-loop
      await store.setState({legacyCursor: cursor});
    }
    if (batch.length < pageSize) break;
  }

  logger.info('retention: sweep done', stats);
  return stats;
}

// ---------------------------------------------------------------------------
// Firestore adapter
// ---------------------------------------------------------------------------

/**
 * The sweep's Firestore access over the Admin SDK. Indexes: single-field
 * only (clips.retainUntil, clips.createdAt, feed_posts.videoStoragePath,
 * montages.sourcePostIds array-contains), all automatic.
 *
 * @param {{db: object, Timestamp: object, FieldPath: object, feedPosts?: string}} opts
 */
function firestoreRetentionStore({db, Timestamp, FieldPath, feedPosts = 'feed_posts'}) {
  const clips = () => db.collection(CLIPS);
  const asItems = (snap) => snap.docs.map((d) => ({id: d.id, clip: d.data()}));
  const stateRef = () => db.collection(RETENTION_STATE).doc(STATE_DOC);
  return {
    async dueClips(nowMs, limit) {
      const snap = await clips()
        .where('retainUntil', '<=', Timestamp.fromMillis(nowMs))
        .orderBy('retainUntil')
        .limit(limit)
        .get();
      return asItems(snap);
    },
    async legacyClips(cutoffMs, cursor, limit) {
      let q = clips()
        .where('createdAt', '<=', Timestamp.fromMillis(cutoffMs))
        .orderBy('createdAt')
        .orderBy(FieldPath.documentId());
      if (cursor && cursor.createdAtMs !== null && cursor.createdAtMs !== undefined) {
        q = q.startAfter(Timestamp.fromMillis(cursor.createdAtMs), cursor.id);
      }
      return asItems(await q.limit(limit).get());
    },
    async getState() {
      const snap = await stateRef().get();
      return snap.exists ? snap.data() : {};
    },
    async setState(state) {
      await stateRef().set({...state, updatedAt: new Date()}, {merge: true});
    },
    async getUser(uid) {
      if (!uid) return null;
      const snap = await db.collection('users').doc(String(uid)).get();
      return snap.exists ? snap.data() : null;
    },
    async postsForPath(objectPath) {
      const snap = await db.collection(feedPosts).where('videoStoragePath', '==', objectPath).get();
      return snap.docs.map((d) => ({id: d.id, ...d.data()}));
    },
    async inMontage(postId) {
      const snap = await db.collection('montages')
        .where('sourcePostIds', 'array-contains', postId)
        .limit(1)
        .get();
      return !snap.empty;
    },
    async setRetainUntil(id, ms) {
      await clips().doc(id).update({retainUntil: Timestamp.fromMillis(ms)});
    },
    async markPostsExpired(postIds, nowMs) {
      const batch = db.batch();
      for (const postId of postIds) {
        batch.update(db.collection(feedPosts).doc(postId), {videoExpired: true, videoExpiredAt: new Date(nowMs)});
      }
      await batch.commit();
    },
    async deleteClip(id) {
      await clips().doc(id).delete();
    },
  };
}

module.exports = {
  CLIPS,
  RETENTION_STATE,
  PAGE_SIZE,
  MAX_PAGES,
  isKeeper,
  processClip,
  sweep,
  firestoreRetentionStore,
};
