'use strict';

/**
 * TaskCaster automatic montage pipeline — Cloud Functions v2 glue.
 *
 * There is no human step anywhere in here. A player posts a video; once three
 * videos have landed for a task (or 30 minutes pass with fewer), the server
 * renders two montages and writes their URLs back to Firestore:
 *
 *   montages/{gameId}/{taskId}/finale.mp4   the last 2 s of every clip
 *   montages/{gameId}/{taskId}/moments.mp4  one auto-picked highlight per clip
 *
 * Cost posture: no minInstances, maxInstances 3, us-central1, and every render
 * is claimed with a lock so a burst of posts cannot fan out into parallel
 * encodes.
 */

const fs = require('fs');
const os = require('os');
const path = require('path');

const {initializeApp} = require('firebase-admin/app');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');
const {getStorage} = require('firebase-admin/storage');
const {setGlobalOptions} = require('firebase-functions/v2');
const {onDocumentCreated} = require('firebase-functions/v2/firestore');
const {onSchedule} = require('firebase-functions/v2/scheduler');
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const logger = require('firebase-functions/logger');

const montage = require('./montage');
const {hasDrawtext} = require('./ffmpeg');
const {
  MAX_CLIPS,
  montageDocId,
  isStarterTask,
  finaleObjectPath,
  momentsObjectPath,
  publicUrl,
  objectPathForPost,
  isMontageablePost,
  selectClips,
  decideRender,
  applyNewPost,
  clipFromPost,
} = require('./contract');

initializeApp();

const REGION = 'us-central1';

setGlobalOptions({region: REGION, maxInstances: 3});

/** Heavy (ffmpeg) function shape. 2 GiB also buys a full vCPU. */
const RENDER_OPTS = {
  region: REGION,
  memory: '2GiB',
  timeoutSeconds: 540,
  maxInstances: 3,
  concurrency: 1,
};

const MONTAGES = 'montages';
const FEED_POSTS = 'feed_posts';

const db = () => getFirestore();
const bucket = () => getStorage().bucket();

const nowIso = () => new Date().toISOString();

// ---------------------------------------------------------------------------
// Triggers
// ---------------------------------------------------------------------------

/**
 * A new post landed. If it is a player video, mark its task's montage pending
 * and — once three videos have piled up — render straight away.
 */
exports.onFeedPostCreated = onDocumentCreated(
  {document: `${FEED_POSTS}/{postId}`, ...RENDER_OPTS},
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const post = {id: event.params.postId, ...snap.data()};

    if (!isMontageablePost(post)) {
      logger.debug('montage: ignoring post', {postId: post.id, mediaType: post.mediaType});
      return;
    }
    const {gameId, taskId} = post;
    if (!gameId || !taskId) {
      logger.warn('montage: post is missing gameId/taskId', {postId: post.id});
      return;
    }

    const ref = db().collection(MONTAGES).doc(montageDocId(gameId, taskId));
    const decision = await db().runTransaction(async (tx) => {
      const existing = await tx.get(ref);
      const data = existing.exists ? existing.data() : null;
      const update = applyNewPost(data, post, nowIso());
      tx.set(ref, update, {merge: true});
      return decideRender({...(data || {}), ...update}, Date.now());
    });

    logger.info('montage: post queued', {
      postId: post.id, gameId, taskId, decision: decision.reason,
    });
    if (decision.render) await render(gameId, taskId);
  },
);

/**
 * The settle pass: anything still pending 30 minutes after its first video
 * gets rendered even if it never reached three clips.
 */
exports.renderPendingMontages = onSchedule(
  {schedule: 'every 10 minutes', ...RENDER_OPTS},
  async () => {
    const snap = await db().collection(MONTAGES).where('status', '==', 'pending').get();
    const now = Date.now();
    let rendered = 0;
    for (const doc of snap.docs) {
      const data = doc.data();
      const decision = decideRender(data, now);
      if (!decision.render) continue;
      try {
        // Serial on purpose: one encode at a time per instance.
        // eslint-disable-next-line no-await-in-loop
        await render(data.gameId, data.taskId);
        rendered += 1;
      } catch (err) {
        logger.error('montage: scheduled render failed', {
          docId: doc.id, error: err.message,
        });
      }
    }
    logger.info('montage: settle pass done', {pending: snap.size, rendered});
  },
);

/**
 * Manual kick, for verifying the pipeline in the cloud without waiting for the
 * settle window. Requires a signed-in caller and an existing montage doc that
 * is not already `ready`, so it cannot be used to burn CPU on demand.
 */
exports.renderMontageNow = onCall({...RENDER_OPTS, maxInstances: 1}, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  const {gameId, taskId} = request.data || {};
  if (!gameId || !taskId) throw new HttpsError('invalid-argument', 'gameId and taskId required.');

  const ref = db().collection(MONTAGES).doc(montageDocId(gameId, taskId));
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError('not-found', 'No montage queued for that task.');
  if (snap.data().status === 'ready') {
    throw new HttpsError('failed-precondition', 'That montage is already rendered.');
  }
  return render(gameId, taskId, {force: true});
});

// ---------------------------------------------------------------------------
// Render
// ---------------------------------------------------------------------------

/**
 * Claim the montage doc so two instances never encode the same task at once.
 * @returns {Promise<{claimed:boolean, version:number, reason?:string}>}
 */
async function claim(ref, {force}) {
  return db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return {claimed: false, version: 0, reason: 'no-doc'};
    const data = snap.data();
    const decision = decideRender(data, Date.now());
    if (!force && decision.reason === 'locked') {
      return {claimed: false, version: Number(data.version) || 0, reason: 'locked'};
    }
    tx.set(ref, {lockedAt: nowIso()}, {merge: true});
    return {claimed: true, version: Number(data.version) || 0};
  });
}

/**
 * Render both montages for one task and publish them.
 *
 * Idempotent and safe to re-run: it always rebuilds from whatever videos are in
 * `feed_posts` right now, overwrites the same two Storage objects, and bumps
 * `version`.
 *
 * @param {string} gameId
 * @param {string} taskId
 * @returns {Promise<object>} a summary (also the callable's response)
 */
async function render(gameId, taskId, {force = false} = {}) {
  const ref = db().collection(MONTAGES).doc(montageDocId(gameId, taskId));
  const claimResult = await claim(ref, {force});
  if (!claimResult.claimed) {
    logger.info('montage: render skipped', {gameId, taskId, reason: claimResult.reason});
    return {status: 'skipped', reason: claimResult.reason};
  }

  const workDir = fs.mkdtempSync(path.join(os.tmpdir(), 'montage-'));
  const started = Date.now();
  try {
    // Single-field query -> no composite index needed. Collections are small.
    // Starter Pack tasks are scoped across every player's solo game, so they
    // are fetched by taskId; game tasks by gameId (selectClips re-filters).
    const snap = isStarterTask(taskId)
      ? await db().collection(FEED_POSTS).where('taskId', '==', taskId).get()
      : await db().collection(FEED_POSTS).where('gameId', '==', gameId).get();
    const posts = selectClips(
      snap.docs.map((d) => ({id: d.id, ...d.data()})),
      {taskId, maxClips: MAX_CLIPS},
    );
    logger.info('montage: rendering', {gameId, taskId, candidates: snap.size, clips: posts.length});

    if (!posts.length) {
      await ref.set({
        status: 'failed',
        error: 'no video posts found for this task',
        lockedAt: null,
        updatedAt: nowIso(),
      }, {merge: true});
      return {status: 'failed', reason: 'no-clips'};
    }

    const clips = [];
    for (const post of posts) {
      const objectPath = objectPathForPost(post);
      const local = path.join(workDir, `${post.id}.mp4`);
      try {
        // eslint-disable-next-line no-await-in-loop
        await bucket().file(objectPath).download({destination: local});
        clips.push(clipFromPost(post, local));
      } catch (err) {
        logger.warn('montage: clip download failed, skipping', {
          postId: post.id, objectPath, error: err.message,
        });
      }
    }
    if (!clips.length) throw new Error('every clip failed to download');

    const taskTitle = posts[0].taskTitle || '';
    const finalePath = path.join(workDir, 'finale.mp4');
    const momentsPath = path.join(workDir, 'moments.mp4');

    const finaleResult = await montage.finale(clips, finalePath, {seconds: 2, taskTitle});
    const momentsResult = await montage.moments(clips, momentsPath, {seconds: 3, taskTitle});

    const finaleObject = finaleObjectPath(gameId, taskId);
    const momentsObject = momentsObjectPath(gameId, taskId);
    await Promise.all([
      upload(finalePath, finaleObject, {gameId, taskId, kind: 'finale'}),
      upload(momentsPath, momentsObject, {gameId, taskId, kind: 'moments'}),
    ]);

    const bucketName = bucket().name;
    const doc = {
      gameId,
      taskId,
      taskTitle,
      finaleUrl: publicUrl(bucketName, finaleObject),
      momentsUrl: publicUrl(bucketName, momentsObject),
      sourcePostIds: clips.map((c) => c.postId),
      clipCount: finaleResult.clipCount,
      status: 'ready',
      // false when the runtime ffmpeg lacks drawtext: montage rendered, but
      // without burned-in countdown/title text (the app overlays the clock).
      countdownBurned: await hasDrawtext(),
      error: FieldValue.delete(),
      updatedAt: nowIso(),
      version: claimResult.version + 1,
      // renderer bookkeeping — reset the window so new posts start a fresh one
      pendingCount: 0,
      pendingSince: null,
      lockedAt: null,
      finaleSeconds: finaleResult.durationSeconds,
      momentsSeconds: momentsResult.durationSeconds,
      momentSignals: momentsResult.segments.map((s) => ({postId: s.postId, signal: s.signal})),
    };
    await ref.set(doc, {merge: true});

    logger.info('montage: ready', {
      gameId, taskId, clipCount: doc.clipCount, version: doc.version,
      ms: Date.now() - started,
    });
    return {status: 'ready', clipCount: doc.clipCount, version: doc.version};
  } catch (err) {
    logger.error('montage: render failed', {gameId, taskId, error: err.message});
    await ref.set({
      status: 'failed',
      error: String(err.message).slice(0, 1500),
      lockedAt: null,
      updatedAt: nowIso(),
    }, {merge: true}).catch(() => {});
    return {status: 'failed', error: err.message};
  } finally {
    try {
      fs.rmSync(workDir, {recursive: true, force: true});
    } catch {
      /* best effort */
    }
  }
}

/** Upload one rendered mp4 to the public `montages/` prefix. */
async function upload(localPath, objectPath, metadata) {
  await bucket().upload(localPath, {
    destination: objectPath,
    resumable: false,
    metadata: {
      contentType: 'video/mp4',
      cacheControl: 'public,max-age=300',
      metadata: {...metadata, renderedAt: nowIso()},
    },
  });
}
