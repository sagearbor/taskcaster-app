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
 * encodes. Only posts for a real task (Starter Pack id, or a game the poster
 * belongs to) can queue a render, each uid may queue at most
 * MONTAGE_QUEUE_PER_UID_PER_DAY posts a day, and the force-render callable is
 * admin-only (guards.js, audit WP-04).
 */

const fs = require('fs');
const os = require('os');
const path = require('path');

const {initializeApp} = require('firebase-admin/app');
const {getFirestore, FieldValue, FieldPath} = require('firebase-admin/firestore');
const {getMessaging} = require('firebase-admin/messaging');
const {getStorage} = require('firebase-admin/storage');
const {setGlobalOptions} = require('firebase-functions/v2');
const {onDocumentCreated} = require('firebase-functions/v2/firestore');
const {onObjectFinalized} = require('firebase-functions/v2/storage');
const {onSchedule} = require('firebase-functions/v2/scheduler');
const {onCall, onRequest, HttpsError} = require('firebase-functions/v2/https');
const logger = require('firebase-functions/logger');

const montage = require('./montage');
const {hasDrawtext} = require('./ffmpeg');
const {deliverGradePush, firestoreStore} = require('./push');
const {
  MAX_CLIPS,
  montageDocId,
  isStarterTask,
  finaleObjectPath,
  momentsObjectPath,
  publicUrl,
  objectPathForPost,
  selectClips,
  decideRender,
  clipFromPost,
} = require('./contract');
const {requireAdmin} = require('./guards');
const pipeline = require('./pipeline');
const transcode = require('./transcode');
const sharePage = require('./share_page');
const {watermarkFor} = require('./watermark');

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

/**
 * Light function shape, for the push trigger. RENDER_OPTS is sized for ffmpeg
 * (2 GiB, 9 minutes) and would be absurd for sending a few HTTP requests.
 * `secrets` mounts the VAPID private key from Secret Manager as an env var.
 */
const PUSH_OPTS = {
  region: REGION,
  memory: '256MiB',
  timeoutSeconds: 60,
  maxInstances: 5,
  secrets: ['VAPID_PRIVATE_KEY'],
};

/**
 * Clip transcode shape (WP-08): one 720p H.264 encode of a <= 30 s clip.
 * 1 GiB + 1 vCPU is the cheapest shape that decodes a 4K HEVC source in time;
 * ffmpeg threads are capped at 2 in transcode.js to keep memory inside it.
 * concurrency 1: two encodes on one vCPU would just run twice as slow.
 */
const TRANSCODE_OPTS = {
  region: REGION,
  bucket: defaultBucketName(),
  memory: '1GiB',
  cpu: 1,
  timeoutSeconds: 300,
  maxInstances: 3,
  concurrency: 1,
};

/**
 * The project's default bucket. Deployed functions get it from FIREBASE_CONFIG;
 * the fallback is the production bucket (named in storage.rules), so loading
 * this module in a unit test does not throw.
 */
function defaultBucketName() {
  try {
    const bucketName = JSON.parse(process.env.FIREBASE_CONFIG || '{}').storageBucket;
    if (bucketName) return bucketName;
  } catch {
    /* fall through */
  }
  return 'taskmaster-app-3d480.firebasestorage.app';
}

const MONTAGES = 'montages';
const FEED_POSTS = 'feed_posts';
const GRADES = 'grades';

const db = () => getFirestore();
const bucket = () => getStorage().bucket();

const nowIso = () => new Date().toISOString();

// ---------------------------------------------------------------------------
// Triggers
// ---------------------------------------------------------------------------

/** Auth user deleted: remove their posts, grades, clips, subs and games. */
exports.deleteUserData = require('./account_deletion').onAuthUserDeleted;

/**
 * A new post landed. If it is a player video for a real task (a Starter Pack
 * task, or a task in a game the poster belongs to) and the poster is under
 * their daily montage quota, mark its task's montage pending and — once three
 * videos have piled up — render straight away. Anything else is ignored: the
 * post still shows in the feed, it just never costs a render. See guards.js.
 */
exports.onFeedPostCreated = onDocumentCreated(
  {document: `${FEED_POSTS}/{postId}`, ...RENDER_OPTS},
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const post = {id: event.params.postId, ...snap.data()};

    // WP-08: a post created AFTER its clip finished transcoding gets the
    // playback/poster URLs here (earlier posts are patched by the transcode).
    try {
      await transcode.applyClipToPost(post, {store: clipStore()});
    } catch (err) {
      logger.warn('transcode: could not apply clip to new post', {postId: post.id, error: err.message});
    }

    const result = await pipeline.handleNewPost(post, {db: db(), render});
    logger.info(result.queued ? 'montage: post queued' : 'montage: post not queued', {
      postId: post.id,
      gameId: post.gameId,
      taskId: post.taskId,
      reason: result.queued ? result.decision.reason : result.reason,
    });
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
 * settle window. Operator-only: the caller must hold the `admin` custom claim
 * (anonymous guests never can), because `force` skips the render lock and a
 * render is a 2 GiB ffmpeg run. Also requires an existing montage doc that is
 * not already `ready`.
 */
exports.renderMontageNow = onCall({...RENDER_OPTS, maxInstances: 1}, async (request) => {
  requireAdmin(request);
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

/**
 * "You got graded" push, to the browser (VAPID) and to the iOS/Android app
 * (FCM). All the logic lives in push.js#deliverGradePush; this is plumbing.
 *
 * Fires on the grade document, not on the post. A grade is written as
 * `feed_posts/{postId}/grades/{graderUid}` in the same transaction that bumps
 * gradeCount/gradeSum/graderIds on the post, and the rules make that document
 * create-only and immutable -- so this fires exactly once per (post, grader).
 * Watching the post document instead would mean re-firing on every tap, boost
 * and tapSeconds write.
 */
exports.onGradeCreated = onDocumentCreated(
  {document: `${FEED_POSTS}/{postId}/${GRADES}/{graderUid}`, ...PUSH_OPTS},
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const {postId, graderUid} = event.params;
    const score = snap.data() ? snap.data().score : null;

    await deliverGradePush({
      store: firestoreStore({db: db(), FieldValue, FieldPath}),
      messaging: getMessaging(),
      postId,
      graderUid,
      score,
      vapidPrivateKey: process.env.VAPID_PRIVATE_KEY,
      nowMs: Date.now(),
      logger,
    });
  },
);

/**
 * WP-08 universal playback: every player clip under
 * submissions/{uid}/{day}/{slot} is re-encoded to 720p H.264 SDR (HDR
 * tone-mapped) in place, plus a poster at transcoded/{uid}/{day}/{slot}.jpg.
 * Fires for every object in the bucket; transcode.shouldTranscode drops
 * everything else (including our own output) before any I/O. See
 * transcode.js for the layout, the clips/{id} metadata and the
 * never-twice guarantees.
 */
exports.onClipUploaded = onObjectFinalized(TRANSCODE_OPTS, async (event) => {
  const object = event.data;
  const result = await transcode.handleFinalized(object, {
    store: clipStore(),
    storage: gcsClipStorage(),
    logger,
  });
  if (result.status !== 'skipped' || result.reason !== 'not-a-submission') {
    logger.info('transcode: done', {path: object && object.name, ...result});
  }
});

/** WP-09 public share pages (/p/ /c/ /t/ /f/, rewritten by firebase.json). */
exports.sharePage = onRequest(sharePage.FUNCTION_OPTS, sharePage.httpHandler(db, logger));

const clipStore = () => transcode.firestoreClipStore({db: db(), FieldValue, feedPosts: FEED_POSTS});

/** The Storage side of a transcode, over the Admin SDK (bypasses rules). */
function gcsClipStorage() {
  return {
    async download(objectPath, destination, generation) {
      const opts = generation ? {generation: Number(generation)} : {};
      await bucket().file(objectPath, opts).download({destination});
    },
    async uploadPoster(localPath, objectPath) {
      await bucket().upload(localPath, {
        destination: objectPath,
        resumable: false,
        metadata: {
          contentType: 'image/jpeg',
          cacheControl: 'public,max-age=86400',
          metadata: {[transcode.MARKER]: '1'},
        },
      });
    },
    /**
     * Overwrite the original with the mp4, only if it is still the generation
     * we transcoded. Keeps the original's custom metadata, including
     * firebaseStorageDownloadTokens, so every existing download URL (feed
     * posts, game docs, shipped app builds) keeps working.
     */
    async replaceInPlace(objectPath, localPath, {ifGenerationMatch, metadata}) {
      const [current] = await bucket().file(objectPath).getMetadata();
      const [file] = await bucket().upload(localPath, {
        destination: objectPath,
        resumable: false,
        preconditionOpts: {ifGenerationMatch: Number(ifGenerationMatch)},
        metadata: {
          contentType: 'video/mp4',
          cacheControl: 'public,max-age=3600',
          metadata: {...(current.metadata || {}), ...metadata},
        },
      });
      return {generation: file.metadata && file.metadata.generation};
    },
    publicUrl: (objectPath) => publicUrl(bucket().name, objectPath),
  };
}

// ---------------------------------------------------------------------------
// Render
// ---------------------------------------------------------------------------

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
  const claimResult = await pipeline.claim(db(), ref, {force});
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

    // WP-09: free-tier renders carry a small 'taskcaster.app' mark.
    const watermark = await watermarkFor({
      gameId, isStarter: isStarterTask(taskId),
      getGame: async (id) => ((await db().collection('games').doc(id).get()).data() || null),
    });
    const finaleResult = await montage.finale(clips, finalePath, {seconds: 2, taskTitle, watermark});
    const momentsResult = await montage.moments(clips, momentsPath, {seconds: 3, taskTitle, watermark});

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
      // false when the runtime ffmpeg lacks drawtext: montage rendered, but
      // without burned-in countdown/title text (the app overlays the clock).
      countdownBurned: await hasDrawtext(),
      error: FieldValue.delete(),
      updatedAt: nowIso(),
      version: claimResult.version + 1,
      finaleSeconds: finaleResult.durationSeconds,
      momentsSeconds: momentsResult.durationSeconds,
      momentSignals: momentsResult.segments.map((s) => ({postId: s.postId, signal: s.signal})),
    };
    // status / pendingCount / pendingSince / lockedAt are settled inside a
    // transaction: posts that landed mid-render keep the montage pending.
    const written = await pipeline.finalize(db(), ref, doc, claimResult);

    logger.info('montage: ready', {
      gameId, taskId, clipCount: doc.clipCount, version: doc.version,
      status: written.status, stillPending: written.pendingCount,
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
