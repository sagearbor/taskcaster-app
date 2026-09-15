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
