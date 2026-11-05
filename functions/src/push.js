'use strict';

/**
 * "You got graded" push: web (VAPID, directly below) and iOS/Android (FCM,
 * further down). Both go out from the same trigger with the same words, under
 * one per-post throttle.
 *
 * The rest of this header explains the WEB half.
 *
 * WHY NOT FCM
 * -----------
 * FCM web push would be the obvious route -- `firebase_messaging` is already a
 * dependency -- but it needs a VAPID key pair registered with the project as a
 * "Web Push certificate", and Firebase only exposes that through the console.
 * There is no CLI command and no REST endpoint for it (both
 * firebasemessaging.googleapis.com and fcm.googleapis.com return 404 for
 * `webPushCertificates`), so wiring FCM here would have left a manual
 * owner-only step in the middle of the feature.
 *
 * So this speaks the Web Push protocol (RFC 8030 / VAPID RFC 8292) directly:
 * the browser subscribes with our own public key, and this module signs and
 * encrypts with the matching private key. That is the same transport FCM uses
 * underneath -- Chrome subscriptions still resolve to fcm.googleapis.com
 * endpoints -- with no console step and no account to create. The public key
 * ships in the client; the private key lives in Secret Manager as
 * VAPID_PRIVATE_KEY and is never committed.
 *
 * Everything that decides WHAT to say is a pure function so it can be tested
 * without a network or an emulator; only `sendToSubscriptions` does I/O.
 */

const webpush = require('web-push');

/**
 * VAPID "subject": a contact the push service can use if a subscription
 * misbehaves. Must be a mailto: or https: URL. The app has no support mailbox
 * yet (a known store blocker), so this points at the app itself.
 */
const VAPID_SUBJECT = 'https://taskmaster-app-3d480.web.app';

/**
 * The VAPID public key. Public by design -- the browser passes it as
 * `applicationServerKey` when it subscribes, so it ships in the page. Its
 * private half lives only in Secret Manager.
 *
 * This literal is duplicated in `web/push.js`, which is the copy the browser
 * actually subscribes with. If the two ever drift, every push is rejected with
 * a 403 VapidPkHashMismatch and nothing else goes wrong -- a silent failure --
 * so `test/push.test.js` reads that file and asserts the two agree.
 */
const VAPID_PUBLIC_KEY = 'BGOwK1VgkCnM159BYg50FxO_RdNoXvoEMTUml5nQ7LQiYvtN2T7uoO1vOrPt0smZ-dt4g9MqmsZOsv9j4NBzdxU';

/** Push services drop anything much larger; we are well under it. */
const MAX_PAYLOAD_BYTES = 3000;

/**
 * Subscriptions whose endpoint returns one of these are permanently dead --
 * the browser cleared site data, the user revoked permission, or the
 * subscription expired. They must be deleted, not retried.
 */
const GONE_STATUS = new Set([404, 410]);

/**
 * The scoreboard line for a post: mean grade out of 5 and crowd points out of
 * 10. Mirrors FeedPost.meanGrade / crowdPoints in the Dart model, so the
 * notification can never disagree with the screen the player lands on.
 *
 * @param {number} gradeSum
 * @param {number} gradeCount
 * @returns {{mean: number, points: number}}
 */
function crowdScore(gradeSum, gradeCount) {
  if (!gradeCount || gradeCount <= 0) return {mean: 0, points: 0};
  const mean = gradeSum / gradeCount;
  const points = Math.min(10, Math.max(0, Math.round(mean * 2)));
  return {mean, points};
}

/**
 * What the player sees on the lock screen.
 *
 * Deliberately says the score and the task, never who graded them: grading is
 * anonymous in the Arena and leaking the grader's name in a notification would
 * quietly change the game's social contract.
 *
 * @param {object} args
 * @param {object} args.post   the feed_posts document (needs taskTitle, gameId, taskId, gradeSum, gradeCount)
 * @param {number} args.score  the grade just given, 1..5
 * @returns {{title: string, body: string, data: object, tag: string}}
 */
function gradeNotification({post, score}) {
  const {mean, points} = crowdScore(post.gradeSum || 0, post.gradeCount || 0);
  const count = post.gradeCount || 0;
  // With the per-post throttle, one push can stand for several grades, so
  // say how many ("3 people graded "Egg on a spoon"").
  const who = count > 1 ? `${count} people` : 'Someone';
  const title = post.taskTitle ? `${who} graded "${post.taskTitle}"` : `${who} graded your clip`;
  const graderWord = count === 1 ? '1 grade' : `${count} grades`;
  const body =
    count > 0
      ? `They gave it ${score}/5. You're on ${points} points from ${graderWord} (avg ${mean.toFixed(1)}).`
      : `They gave it ${score}/5.`;

  return {
    title,
    body,
    // One notification per post: a second grade REPLACES the first on screen
    // rather than stacking, so a popular clip cannot spam the lock screen.
    tag: `grade-${post.id}`,
    data: {
      postId: post.id,
      gameId: post.gameId || null,
      taskId: post.taskId || null,
      url: '/',
    },
  };
}

/**
 * Whether a graded post should notify anybody at all.
 * @returns {{ok: boolean, reason?: string}}
 */
function shouldNotify({post, graderUid}) {
  if (!post) return {ok: false, reason: 'post missing'};
  if (post.isHouse === true || post.userId === 'house') {
    return {ok: false, reason: 'house post has no owner'};
  }
  if (!post.userId) return {ok: false, reason: 'post has no userId'};
  // Rules already forbid grading your own post; belt and braces, because a
  // self-notification is the most obviously broken thing a user could see.
  if (post.userId === graderUid) return {ok: false, reason: 'self-grade'};
  return {ok: true};
}

/**
 * Normalise a stored subscription record into what web-push expects.
 * Returns null when the record is malformed (an old or partial write).
 */
function toWebPushSubscription(record) {
  if (!record || typeof record !== 'object') return null;
  const {endpoint, p256dh, auth} = record;
  if (typeof endpoint !== 'string' || !endpoint.startsWith('https://')) return null;
  if (typeof p256dh !== 'string' || typeof auth !== 'string') return null;
  if (!p256dh || !auth) return null;
  return {endpoint, keys: {p256dh, auth}};
}

/**
 * Deliver one payload to every subscription a user has.
 *
 * Never throws: a push that fails must not fail the Firestore trigger and
 * cause a retry storm against the push service.
 *
 * @param {object} args
 * @param {Record<string, object>} args.subscriptions  map of id -> stored record
 * @param {object} args.notification  from gradeNotification()
 * @param {{publicKey: string, privateKey: string}} args.keys
 * @param {Function} [args.send]  injectable for tests; defaults to web-push
 * @returns {Promise<{sent: string[], gone: string[], failed: string[], skipped: string[]}>}
 */
async function sendToSubscriptions({subscriptions, notification, keys, send}) {
  const result = {sent: [], gone: [], failed: [], skipped: []};
  const entries = Object.entries(subscriptions || {});
  if (!entries.length) return result;

  const payload = JSON.stringify(notification);
  if (Buffer.byteLength(payload) > MAX_PAYLOAD_BYTES) {
    // Should be impossible with a task title, but truncating silently would be
    // worse than saying so.
    result.failed.push('payload-too-large');
    return result;
  }

  const deliver =
    send ||
    ((subscription, body) =>
      webpush.sendNotification(subscription, body, {
        vapidDetails: {
          subject: VAPID_SUBJECT,
          publicKey: keys.publicKey,
          privateKey: keys.privateKey,
        },
        TTL: 60 * 60 * 12,
      }));

  await Promise.all(
    entries.map(async ([id, record]) => {
      const subscription = toWebPushSubscription(record);
      if (!subscription) {
        result.skipped.push(id);
        return;
      }
      try {
        await deliver(subscription, payload);
        result.sent.push(id);
      } catch (err) {
        const status = err && (err.statusCode || err.status);
        if (GONE_STATUS.has(status)) result.gone.push(id);
        else result.failed.push(id);
      }
    }),
  );
  return result;
}

// ---------------------------------------------------------------------------
// Mobile (FCM) delivery
// ---------------------------------------------------------------------------

/**
 * At most one push per post per this window. Grades on a popular clip arrive
 * in bursts; ten pings in a minute is how a player turns notifications off.
 * The push that does go out carries the running count and average, so a
 * suppressed grade still shows up in the next one.
 */
const THROTTLE_MS = 10 * 60 * 1000;

/** sendEachForMulticast takes at most this many tokens per call. */
const FCM_MULTICAST_LIMIT = 500;

/**
 * FCM error codes that mean the token will never work again: the app was
 * uninstalled, its data cleared, or the token rotated. Delete, do not retry.
 * Anything else (quota, unavailable, internal) is transient.
 */
const FCM_GONE_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
]);

/**
 * Whether a push may go out now, given when the last one for this post did.
 * @param {number|null|undefined} lastSentAtMs
 * @param {number} nowMs
 * @param {number} [windowMs]
 */
function throttleAllows(lastSentAtMs, nowMs, windowMs = THROTTLE_MS) {
  if (typeof lastSentAtMs !== 'number' || !Number.isFinite(lastSentAtMs)) return true;
  return nowMs - lastSentAtMs >= windowMs;
}

/**
 * Translate a gradeNotification() into the FCM message shape (minus tokens).
 *
 * FCM `data` values must all be strings, so nulls are dropped rather than
 * sent as "null". The tag doubles as the Android collapse key / notification
 * tag and the APNs collapse id, so -- exactly like the web notification -- a
 * newer grade replaces the older one on the lock screen instead of stacking.
 */
function fcmMessage(notification) {
  const data = {};
  for (const [k, v] of Object.entries(notification.data || {})) {
    if (v !== null && v !== undefined) data[k] = String(v);
  }
  return {
    notification: {title: notification.title, body: notification.body},
    data,
    android: {
      collapseKey: notification.tag,
      notification: {tag: notification.tag},
    },
    apns: {
      headers: {'apns-collapse-id': notification.tag},
      payload: {aps: {'thread-id': notification.tag, sound: 'default'}},
    },
  };
}

/**
 * Deliver one notification to every FCM registration token a user has.
 *
 * Never throws, for the same reason as sendToSubscriptions: a failed push
 * must not fail (and so retry) the Firestore trigger.
 *
 * @param {object} args
 * @param {string[]} args.tokens
 * @param {object} args.notification  from gradeNotification()
 * @param {{sendEachForMulticast: Function}} args.messaging  getMessaging()
 * @returns {Promise<{sent: string[], gone: string[], failed: string[]}>}
 */
async function sendToFcmTokens({tokens, notification, messaging}) {
  const result = {sent: [], gone: [], failed: []};
  const unique = [...new Set((tokens || []).filter((t) => typeof t === 'string' && t))];
  if (!unique.length) return result;

  const base = fcmMessage(notification);
  for (let i = 0; i < unique.length; i += FCM_MULTICAST_LIMIT) {
    const batch = unique.slice(i, i + FCM_MULTICAST_LIMIT);
    let response;
    try {
      // Sequential on purpose: >500 tokens for one user means something is
      // wrong, and fanning out would only multiply it.
      // eslint-disable-next-line no-await-in-loop
      response = await messaging.sendEachForMulticast({...base, tokens: batch});
    } catch {
      // The whole call failed (auth, network). Every token in it is a
      // transient failure, not a dead one.
      result.failed.push(...batch);
      continue;
    }
    const responses = (response && response.responses) || [];
    batch.forEach((token, idx) => {
      const r = responses[idx];
      if (r && r.success) {
        result.sent.push(token);
        return;
      }
      const err = r && r.error;
      const code = err && (err.code || (err.errorInfo && err.errorInfo.code));
      if (FCM_GONE_CODES.has(code)) result.gone.push(token);
      else result.failed.push(token);
    });
  }
  return result;
}

// ---------------------------------------------------------------------------
// Orchestration: the body of the onGradeCreated trigger
// ---------------------------------------------------------------------------

const FEED_POSTS = 'feed_posts';
const PUSH_SUBSCRIPTIONS = 'push_subscriptions';

/**
 * Server-only: one doc per post recording when it last pushed. No client rule
 * matches it, so Firestore's default deny keeps it out of the app's reach.
 */
const PUSH_THROTTLE = 'push_throttle';

/**
 * The Firestore side of a grade push, behind four calls, so the orchestration
 * can be tested against an in-memory fake. `FieldValue` and `FieldPath` are
 * injected for the same reason.
 *
 * A user's push targets live together on push_subscriptions/{uid}:
 *   subs.{id}          browser (VAPID) subscriptions
 *   fcmTokens.{token}  iOS / Android FCM registration tokens
 * That document is readable only by its owner, which is the point of keeping
 * tokens there rather than on the readable-by-any-signed-in-user users/{uid}.
 */
function firestoreStore({db, FieldValue, FieldPath}) {
  return {
    async getPost(postId) {
      const snap = await db.collection(FEED_POSTS).doc(postId).get();
      return snap.exists ? {id: postId, ...snap.data()} : null;
    },

    async getTargets(uid) {
      const snap = await db.collection(PUSH_SUBSCRIPTIONS).doc(uid).get();
      const data = (snap.exists && snap.data()) || {};
      const subs = data.subs && typeof data.subs === 'object' ? data.subs : {};
      const fcmTokens =
        data.fcmTokens && typeof data.fcmTokens === 'object' ? Object.keys(data.fcmTokens) : [];
      return {subs, fcmTokens};
    },

    /** Atomically take the post's push slot. False while inside the window. */
    async claimThrottle(postId, nowMs, windowMs = THROTTLE_MS) {
      const ref = db.collection(PUSH_THROTTLE).doc(postId);
      return db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        const last = snap.exists ? (snap.data() || {}).lastSentAtMs : null;
        if (!throttleAllows(last, nowMs, windowMs)) return false;
        tx.set(ref, {lastSentAtMs: nowMs});
        return true;
      });
    },

    async removeTargets(uid, {subs = [], fcmTokens = []}) {
      if (!subs.length && !fcmTokens.length) return;
      // FieldPath, not a dotted string: FCM tokens contain ':' and are opaque,
      // so never splice one into a field-path string.
      const args = [];
      for (const id of subs) args.push(new FieldPath('subs', id), FieldValue.delete());
      for (const t of fcmTokens) args.push(new FieldPath('fcmTokens', t), FieldValue.delete());
      await db.collection(PUSH_SUBSCRIPTIONS).doc(uid).update(...args);
    },
  };
}

const SILENT_LOGGER = {info() {}, warn() {}, error() {}};

/**
 * Everything onGradeCreated does, minus the trigger plumbing.
 *
 * @param {object} args
 * @param {ReturnType<typeof firestoreStore>} args.store
 * @param {{sendEachForMulticast: Function}} args.messaging
 * @param {string} args.postId
 * @param {string} args.graderUid
 * @param {number|null} args.score
 * @param {string|undefined} args.vapidPrivateKey  web push is skipped without it
 * @param {number} args.nowMs
 * @param {Function} [args.sendWebPush]  injectable web-push sender for tests
 * @param {{info: Function, warn: Function, error: Function}} [args.logger]
 * @returns {Promise<{status: string, reason?: string, web?: object, fcm?: object}>}
 */
async function deliverGradePush({
  store,
  messaging,
  postId,
  graderUid,
  score,
  vapidPrivateKey,
  nowMs,
  sendWebPush,
  logger = SILENT_LOGGER,
}) {
  const post = await store.getPost(postId);
  if (!post) {
    logger.warn('push: graded post is gone', {postId});
    return {status: 'post-missing'};
  }

  const verdict = shouldNotify({post, graderUid});
  if (!verdict.ok) {
    logger.info('push: skipped', {postId, reason: verdict.reason});
    return {status: 'skipped', reason: verdict.reason};
  }

  const {subs, fcmTokens} = await store.getTargets(post.userId);
  const hasWeb = Object.keys(subs).length > 0;
  if (!hasWeb && !fcmTokens.length) {
    // The overwhelmingly common case: the player never opted in.
    logger.info('push: no targets', {postId, uid: post.userId});
    return {status: 'no-targets'};
  }

  // Claimed only once there is someone to tell, so grades on a post whose
  // owner has not opted in yet do not burn the window.
  if (!(await store.claimThrottle(postId, nowMs))) {
    logger.info('push: throttled', {postId});
    return {status: 'throttled'};
  }

  const notification = gradeNotification({post, score});

  let web = {sent: [], gone: [], failed: [], skipped: []};
  if (hasWeb) {
    if (vapidPrivateKey) {
      web = await sendToSubscriptions({
        subscriptions: subs,
        notification,
        keys: {publicKey: VAPID_PUBLIC_KEY, privateKey: vapidPrivateKey},
        send: sendWebPush,
      });
    } else {
      logger.error('push: VAPID_PRIVATE_KEY is not set; skipping web push');
    }
  }

  const fcm = await sendToFcmTokens({tokens: fcmTokens, notification, messaging});

  // Drop targets the push services say are permanently gone, so an
  // uninstalled app or a cleared browser does not cost a failed request on
  // every future grade.
  if (web.gone.length || fcm.gone.length) {
    try {
      await store.removeTargets(post.userId, {subs: web.gone, fcmTokens: fcm.gone});
    } catch (err) {
      logger.warn('push: could not prune dead targets', {postId, error: err.message});
    }
  }

  logger.info('push: sent', {
    postId,
    uid: post.userId,
    webSent: web.sent.length,
    webGone: web.gone.length,
    webFailed: web.failed.length,
    fcmSent: fcm.sent.length,
    fcmGone: fcm.gone.length,
    fcmFailed: fcm.failed.length,
  });
  return {status: 'sent', web, fcm};
}

module.exports = {
  THROTTLE_MS,
  FCM_GONE_CODES,
  FCM_MULTICAST_LIMIT,
  PUSH_THROTTLE,
  throttleAllows,
  fcmMessage,
  sendToFcmTokens,
  firestoreStore,
  deliverGradePush,
  VAPID_SUBJECT,
  VAPID_PUBLIC_KEY,
  GONE_STATUS,
  MAX_PAYLOAD_BYTES,
  crowdScore,
  gradeNotification,
  shouldNotify,
  toWebPushSubscription,
  sendToSubscriptions,
};
