'use strict';

// "You got graded" web push: what we say, who we say it to, and what happens
// when a push service rejects a subscription.

const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const assert = require('node:assert/strict');

const {
  VAPID_PUBLIC_KEY,
  VAPID_SUBJECT,
  crowdScore,
  gradeNotification,
  shouldNotify,
  toWebPushSubscription,
  sendToSubscriptions,
  THROTTLE_MS,
  PUSH_THROTTLE,
  throttleAllows,
  fcmMessage,
  sendToFcmTokens,
  firestoreStore,
  deliverGradePush,
} = require('../src/push');

const KEYS = {publicKey: VAPID_PUBLIC_KEY, privateKey: 'not-used-by-the-fake-sender'};

const sub = (n) => ({
  endpoint: `https://fcm.googleapis.com/fcm/send/endpoint-${n}`,
  p256dh: 'BFakeClientPublicKey',
  auth: 'FakeAuthSecret',
});

test('the client and server VAPID public keys are the same key', () => {
  // A mismatch fails SILENTLY: every send comes back 403 VapidPkHashMismatch
  // and nothing else in the app misbehaves. Pin them together.
  const clientJs = fs.readFileSync(path.join(__dirname, '..', '..', 'web', 'push.js'), 'utf8');
  const found = /'(B[A-Za-z0-9_-]{80,})'/.exec(clientJs);
  assert.ok(found, 'no VAPID public key literal found in web/push.js');
  assert.equal(found[1], VAPID_PUBLIC_KEY);
});

test('the VAPID subject is a contact the push service will accept', () => {
  assert.match(VAPID_SUBJECT, /^(https:\/\/|mailto:)/);
});

test('crowdScore matches the Dart model (mean out of 5, points out of 10)', () => {
  assert.deepEqual(crowdScore(0, 0), {mean: 0, points: 0});
  assert.deepEqual(crowdScore(5, 1), {mean: 5, points: 10});
  assert.deepEqual(crowdScore(9, 3), {mean: 3, points: 6});
  // Rounds the same way FeedPost.crowdPoints does, and clamps at 10.
  assert.equal(crowdScore(7, 2).points, 7);
  assert.equal(crowdScore(50, 10).points, 10);
});

test('the notification names the task and the score, never the grader', () => {
  const post = {id: 'p1', taskTitle: 'Egg on a spoon', gradeSum: 4, gradeCount: 1};
  const n = gradeNotification({post, score: 4});
  assert.match(n.title, /Egg on a spoon/);
  assert.match(n.body, /4\/5/);
  // Grading is anonymous in the Arena; a name here would leak it.
  assert.doesNotMatch(JSON.stringify(n), /grader/i);
  assert.equal(n.tag, 'grade-p1');
  assert.equal(n.data.postId, 'p1');
});

test('a second grade replaces the first notification rather than stacking', () => {
  const post = {id: 'p1', taskTitle: 'T', gradeSum: 8, gradeCount: 2};
  assert.equal(
    gradeNotification({post, score: 4}).tag,
    gradeNotification({post, score: 5}).tag,
  );
});

test('a post with no title still produces a sane notification', () => {
  const n = gradeNotification({post: {id: 'p2', gradeSum: 3, gradeCount: 1}, score: 3});
  assert.ok(n.title.length > 0);
  assert.doesNotMatch(n.title, /undefined|null/);
  assert.doesNotMatch(n.body, /undefined|null|NaN/);
});

test('house posts and self-grades notify nobody', () => {
  assert.equal(shouldNotify({post: {userId: 'house'}, graderUid: 'u1'}).ok, false);
  assert.equal(shouldNotify({post: {userId: 'u2', isHouse: true}, graderUid: 'u1'}).ok, false);
  assert.equal(shouldNotify({post: {userId: 'u1'}, graderUid: 'u1'}).ok, false);
  assert.equal(shouldNotify({post: {}, graderUid: 'u1'}).ok, false);
  assert.equal(shouldNotify({post: null, graderUid: 'u1'}).ok, false);
  assert.equal(shouldNotify({post: {userId: 'u2'}, graderUid: 'u1'}).ok, true);
});

test('malformed subscription records are rejected, not sent to', () => {
  assert.equal(toWebPushSubscription(null), null);
  assert.equal(toWebPushSubscription({endpoint: 'http://insecure', p256dh: 'a', auth: 'b'}), null);
  assert.equal(toWebPushSubscription({endpoint: 'https://x', p256dh: '', auth: 'b'}), null);
  assert.equal(toWebPushSubscription({endpoint: 'https://x', auth: 'b'}), null);
  assert.deepEqual(toWebPushSubscription(sub(1)), {
    endpoint: sub(1).endpoint,
    keys: {p256dh: 'BFakeClientPublicKey', auth: 'FakeAuthSecret'},
  });
});

test('every subscription a user has gets the push', async () => {
  const seen = [];
  const result = await sendToSubscriptions({
    subscriptions: {a: sub(1), b: sub(2)},
    notification: gradeNotification({post: {id: 'p', taskTitle: 'T'}, score: 5}),
    keys: KEYS,
    send: async (subscription, payload) => {
      seen.push([subscription.endpoint, JSON.parse(payload).tag]);
    },
  });
  assert.deepEqual(result.sent.sort(), ['a', 'b']);
  assert.equal(result.gone.length, 0);
  assert.equal(seen.length, 2);
  assert.equal(seen[0][1], 'grade-p');
});

test('404 and 410 mark a subscription gone; other errors are retryable failures', async () => {
  const fail = (status) => {
    const err = new Error(`push failed ${status}`);
    err.statusCode = status;
    return err;
  };
  const result = await sendToSubscriptions({
    subscriptions: {dead: sub(1), expired: sub(2), flaky: sub(3), fine: sub(4)},
    notification: gradeNotification({post: {id: 'p', taskTitle: 'T'}, score: 5}),
    keys: KEYS,
    send: async (subscription) => {
      if (subscription.endpoint.endsWith('-1')) throw fail(404);
      if (subscription.endpoint.endsWith('-2')) throw fail(410);
      if (subscription.endpoint.endsWith('-3')) throw fail(500);
      return undefined;
    },
  });
  assert.deepEqual(result.gone.sort(), ['dead', 'expired']);
  assert.deepEqual(result.failed, ['flaky']);
  assert.deepEqual(result.sent, ['fine']);
});

test('a user with no subscriptions is a no-op, not an error', async () => {
  const result = await sendToSubscriptions({
    subscriptions: {},
    notification: gradeNotification({post: {id: 'p', taskTitle: 'T'}, score: 5}),
    keys: KEYS,
    send: async () => assert.fail('must not send'),
  });
  assert.deepEqual(result, {sent: [], gone: [], failed: [], skipped: []});
});

test('a broken record is skipped without stopping the others', async () => {
  const result = await sendToSubscriptions({
    subscriptions: {broken: {endpoint: 'nope'}, good: sub(1)},
    notification: gradeNotification({post: {id: 'p', taskTitle: 'T'}, score: 5}),
    keys: KEYS,
    send: async () => undefined,
  });
  assert.deepEqual(result.skipped, ['broken']);
  assert.deepEqual(result.sent, ['good']);
});

test('the push worker is registered in its own scope, not Flutter\'s', () => {
  // A scope holds exactly one service worker, and Flutter owns '/' with
  // flutter_service_worker.js. Registering ours there loses silently: the
  // subscription attaches to Flutter's worker, which has no 'push' handler, so
  // notifications arrive as Chrome's generic "updated in the background"
  // instead of ours. Caught on production; pinned here.
  const clientJs = fs.readFileSync(path.join(__dirname, '..', '..', 'web', 'push.js'), 'utf8');
  const url = /SW_URL\s*=\s*'([^']+)'/.exec(clientJs);
  const scope = /SW_SCOPE\s*=\s*'([^']+)'/.exec(clientJs);
  assert.ok(url && scope, 'push.js must declare SW_URL and SW_SCOPE');
  assert.notEqual(scope[1], '/', 'the push worker must not claim the root scope');
  // A worker's scope can never be broader than its own path.
  assert.ok(url[1].startsWith(scope[1]), `${url[1]} cannot control ${scope[1]}`);
  assert.match(clientJs, /register\(SW_URL,\s*\{scope: SW_SCOPE\}\)/);
  // navigator.serviceWorker.ready resolves with the worker controlling the
  // PAGE (Flutter's), not ours -- subscribing on it is the same bug again.
  // (Comments stripped first: the code says exactly this in prose too.)
  const clientCode = clientJs.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
  assert.doesNotMatch(clientCode, /serviceWorker\.ready/);
  assert.ok(
    fs.existsSync(path.join(__dirname, '..', '..', 'web', url[1].replace(/^\//, ''))),
    `web${url[1]} must exist so hosting serves it at that path`,
  );
});

test('the push service worker draws a notification and focuses an open tab', () => {
  const sw = fs.readFileSync(path.join(__dirname, '..', '..', 'web', 'push', 'sw.js'), 'utf8');
  assert.match(sw, /addEventListener\('push'/);
  assert.match(sw, /showNotification/);
  assert.match(sw, /addEventListener\('notificationclick'/);
  // Flutter regenerates flutter_service_worker.js on every build, so this
  // worker must stand alone rather than hook into it (the file name appears in
  // this worker's header comment explaining exactly that, hence stripping
  // comments before asserting on the code).
  const code = sw.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
  assert.doesNotMatch(code, /flutter_service_worker/);
  assert.doesNotMatch(code, /importScripts/);
});

// ---------------------------------------------------------------------------
// Mobile (FCM) push and the onGradeCreated orchestration
// ---------------------------------------------------------------------------

/**
 * In-memory Firestore with just what firestoreStore touches: doc get/set,
 * update(FieldPath, FieldValue.delete(), ...) and runTransaction. Running the
 * REAL store over a fake db (rather than a fake store) means token pruning and
 * the throttle doc are exercised exactly as deployed.
 */
class FakeFieldPath {
  constructor(...segments) {
    this.segments = segments;
  }
}
const DELETE = Symbol('delete');
const FakeFieldValue = {delete: () => DELETE};
const clone = (v) => JSON.parse(JSON.stringify(v));

function fakeDb(initial = {}) {
  const docs = new Map(Object.entries(initial).map(([k, v]) => [k, clone(v)]));
  const ref = (key) => ({
    key,
    async get() {
      const d = docs.get(key);
      return {exists: d !== undefined, data: () => (d === undefined ? undefined : clone(d))};
    },
    async update(...args) {
      const d = docs.get(key);
      if (d === undefined) throw new Error(`NOT_FOUND ${key}`);
      for (let i = 0; i < args.length; i += 2) {
        const segs = args[i].segments;
        let node = d;
        for (const s of segs.slice(0, -1)) node = node[s] || (node[s] = {});
        const leaf = segs[segs.length - 1];
        if (args[i + 1] === DELETE) delete node[leaf];
        else node[leaf] = args[i + 1];
      }
    },
  });
  return {
    docs,
    collection: (c) => ({doc: (id) => ref(`${c}/${id}`)}),
    async runTransaction(fn) {
      return fn({get: (r) => r.get(), set: (r, data) => docs.set(r.key, clone(data))});
    },
  };
}

/** getMessaging() stand-in. `fail` maps token -> FCM error code. */
function fakeMessaging(fail = {}) {
  const calls = [];
  return {
    calls,
    async sendEachForMulticast(message) {
      calls.push(message);
      return {
        responses: message.tokens.map((t) =>
          fail[t] ? {success: false, error: {code: fail[t]}} : {success: true, messageId: `m-${t}`},
        ),
      };
    },
  };
}

const POST = {
  userId: 'owner',
  taskTitle: 'Egg on a spoon',
  gradeSum: 13,
  gradeCount: 3,
  gameId: 'g1',
  taskId: 't1',
};

function run(db, messaging, extra = {}) {
  return deliverGradePush({
    store: firestoreStore({db, FieldValue: FakeFieldValue, FieldPath: FakeFieldPath}),
    messaging,
    postId: 'p1',
    graderUid: 'grader',
    score: 5,
    vapidPrivateKey: undefined,
    nowMs: 1_000_000_000,
    ...extra,
  });
}

test('a grade on a post whose owner has 2 FCM tokens sends 2 messages', async () => {
  const db = fakeDb({
    'feed_posts/p1': POST,
    'push_subscriptions/owner': {fcmTokens: {'tok:A': 1, 'tok:B': 2}},
  });
  const messaging = fakeMessaging();
  const out = await run(db, messaging);
  assert.equal(out.status, 'sent');
  assert.equal(messaging.calls.length, 1);
  assert.deepEqual([...messaging.calls[0].tokens].sort(), ['tok:A', 'tok:B']);
  assert.deepEqual(out.fcm.sent.sort(), ['tok:A', 'tok:B']);
  // The aggregated copy the throttle makes necessary.
  assert.equal(messaging.calls[0].notification.title, '3 people graded "Egg on a spoon"');
  assert.match(messaging.calls[0].notification.body, /avg 4\.3/);
});

test('dead FCM tokens are removed; transient failures are kept', async () => {
  const db = fakeDb({
    'feed_posts/p1': POST,
    'push_subscriptions/owner': {
      fcmTokens: {'tok:live': 1, 'tok:gone': 2, 'tok:bad': 3, 'tok:flaky': 4},
      subs: {web1: sub(1)},
    },
  });
  const messaging = fakeMessaging({
    'tok:gone': 'messaging/registration-token-not-registered',
    'tok:bad': 'messaging/invalid-registration-token',
    'tok:flaky': 'messaging/internal-error',
  });
  const out = await run(db, messaging);
  assert.deepEqual(out.fcm.gone.sort(), ['tok:bad', 'tok:gone']);
  assert.deepEqual(out.fcm.failed, ['tok:flaky']);
  const left = db.docs.get('push_subscriptions/owner');
  assert.deepEqual(Object.keys(left.fcmTokens).sort(), ['tok:flaky', 'tok:live']);
  // Pruning FCM tokens must not touch the browser subscriptions beside them.
  assert.deepEqual(Object.keys(left.subs), ['web1']);
});

test('web and mobile targets both get the grade, from one trigger', async () => {
  const db = fakeDb({
    'feed_posts/p1': POST,
    'push_subscriptions/owner': {fcmTokens: {'tok:A': 1}, subs: {web1: sub(1), web2: sub(2)}},
  });
  const webSeen = [];
  const out = await run(db, fakeMessaging(), {
    vapidPrivateKey: 'fake',
    sendWebPush: async (s) => {
      if (s.endpoint.endsWith('-2')) {
        const err = new Error('gone');
        err.statusCode = 410;
        throw err;
      }
      webSeen.push(s.endpoint);
    },
  });
  assert.equal(webSeen.length, 1);
  assert.deepEqual(out.fcm.sent, ['tok:A']);
  const left = db.docs.get('push_subscriptions/owner');
  assert.deepEqual(Object.keys(left.subs), ['web1']);
  assert.deepEqual(Object.keys(left.fcmTokens), ['tok:A']);
});

test('a missing VAPID key skips web push but still reaches the app', async () => {
  const db = fakeDb({
    'feed_posts/p1': POST,
    'push_subscriptions/owner': {fcmTokens: {'tok:A': 1}, subs: {web1: sub(1)}},
  });
  const out = await run(db, fakeMessaging(), {
    sendWebPush: async () => assert.fail('no key, no web send'),
  });
  assert.deepEqual(out.fcm.sent, ['tok:A']);
});

test('at most one push per post per 10 minutes', async () => {
  const db = fakeDb({
    'feed_posts/p1': POST,
    'push_subscriptions/owner': {fcmTokens: {'tok:A': 1}},
  });
  const messaging = fakeMessaging();
  const t0 = 5_000_000;
  assert.equal((await run(db, messaging, {nowMs: t0})).status, 'sent');
  assert.equal((await run(db, messaging, {nowMs: t0 + 60_000})).status, 'throttled');
  assert.equal((await run(db, messaging, {nowMs: t0 + THROTTLE_MS - 1})).status, 'throttled');
  assert.equal((await run(db, messaging, {nowMs: t0 + THROTTLE_MS})).status, 'sent');
  assert.equal(messaging.calls.length, 2);
  assert.equal(THROTTLE_MS, 10 * 60 * 1000);
});

test('no targets, self-grades and missing posts send nothing and burn no throttle', async () => {
  const messaging = fakeMessaging();
  const empty = fakeDb({'feed_posts/p1': POST});
  assert.equal((await run(empty, messaging)).status, 'no-targets');
  assert.equal(empty.docs.has(`${PUSH_THROTTLE}/p1`), false);

  const self = fakeDb({
    'feed_posts/p1': POST,
    'push_subscriptions/owner': {fcmTokens: {'tok:A': 1}},
  });
  assert.equal((await run(self, messaging, {graderUid: 'owner'})).status, 'skipped');
  assert.equal(self.docs.has(`${PUSH_THROTTLE}/p1`), false);
  assert.equal((await run(fakeDb({}), messaging)).status, 'post-missing');
  assert.equal(messaging.calls.length, 0);
});

test('throttleAllows treats a missing or junk timestamp as never sent', () => {
  assert.equal(throttleAllows(undefined, 10), true);
  assert.equal(throttleAllows(null, 10), true);
  assert.equal(throttleAllows('x', 10), true);
  assert.equal(throttleAllows(0, THROTTLE_MS - 1), false);
  assert.equal(throttleAllows(0, THROTTLE_MS), true);
});

test('the FCM message carries string-only data and collapses per post', () => {
  const m = fcmMessage(
    gradeNotification({post: {id: 'p9', taskTitle: 'T', gradeSum: 4, gradeCount: 1}, score: 4}),
  );
  for (const v of Object.values(m.data)) assert.equal(typeof v, 'string');
  // gameId/taskId were null: dropped, not sent as the string "null".
  assert.deepEqual(Object.keys(m.data).sort(), ['postId', 'url']);
  assert.equal(m.notification.title, 'Someone graded "T"');
  assert.equal(m.android.collapseKey, 'grade-p9');
  assert.equal(m.android.notification.tag, 'grade-p9');
  assert.equal(m.apns.headers['apns-collapse-id'], 'grade-p9');
});

test('a whole-call FCM failure marks tokens failed, never gone', async () => {
  const out = await sendToFcmTokens({
    tokens: ['a', 'b', 'a'],
    notification: gradeNotification({post: {id: 'p', taskTitle: 'T'}, score: 5}),
    messaging: {
      async sendEachForMulticast() {
        throw new Error('app/invalid-credential');
      },
    },
  });
  assert.deepEqual(out, {sent: [], gone: [], failed: ['a', 'b']});
});
