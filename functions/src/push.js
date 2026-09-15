'use strict';

/**
 * Web push for "you got graded".
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
  const title = post.taskTitle ? `Someone graded "${post.taskTitle}"` : 'Someone graded your clip';
  const {mean, points} = crowdScore(post.gradeSum || 0, post.gradeCount || 0);
  const count = post.gradeCount || 0;
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

module.exports = {
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
