'use strict';

/**
 * WP-11 RevenueCat webhook + REST refresh (functions/src/revenuecat.js),
 * against the in-memory Firestore. One fixture per event type.
 */

const test = require('node:test');
const assert = require('node:assert/strict');

const rc = require('../src/revenuecat');
const {effectivePlan} = require('../src/plans');
const {makeFakeFirestore} = require('./fake_firestore');

const UID = 'firebaseUid123';
const SECRET = 'whsec-test-value';
const T0 = Date.parse('2026-11-05T12:00:00Z');
const MONTH = 30 * 24 * 3600 * 1000;

const Timestamp = {fromMillis: (ms) => new Date(ms)};
const FieldValue = {serverTimestamp: () => 'SERVER_TS'};
const silent = {info() {}, warn() {}, error() {}};

/** A RevenueCat event fixture. */
function event(type, over = {}) {
  return {
    type,
    id: `evt-${type}-${over.event_timestamp_ms || T0}`,
    app_user_id: UID,
    original_app_user_id: UID,
    aliases: [UID],
    entitlement_ids: ['pro'],
    product_id: 'taskcaster_pro_monthly',
    period_type: 'NORMAL',
    purchased_at_ms: T0,
    expiration_at_ms: T0 + MONTH,
    event_timestamp_ms: T0,
    store: 'APP_STORE',
    environment: 'SANDBOX',
    ...over,
  };
}

function setup(seed = {[`users/${UID}`]: {displayName: 'Sam'}}, extra = {}) {
  const db = makeFakeFirestore(seed);
  const deps = {db, Timestamp, FieldValue, secret: SECRET, logger: silent, now: T0, ...extra};
  const post = (body, headers = {authorization: SECRET}) =>
    rc.handleWebhook({method: 'POST', headers, body}, deps);
  const user = () => db.peek(`users/${UID}`);
  return {db, deps, post, user};
}

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------

test('webhook auth: no secret 503, wrong/missing header 401, GET 405, Bearer ok', async () => {
  const {post, deps} = setup();
  const body = {event: event('INITIAL_PURCHASE')};
  assert.equal((await rc.handleWebhook({method: 'POST', headers: {authorization: SECRET}, body},
    {...deps, secret: ''})).status, 503);
  assert.equal((await post(body, {})).status, 401);
  assert.equal((await post(body, {authorization: 'nope'})).status, 401);
  assert.equal((await post(body, {authorization: `${SECRET}x`})).status, 401);
  assert.equal((await rc.handleWebhook({method: 'GET', headers: {}, body}, deps)).status, 405);
  assert.equal((await post({}, {authorization: SECRET})).status, 400);
  assert.equal((await post(body, {authorization: `Bearer ${SECRET}`})).status, 200);
});

// ---------------------------------------------------------------------------
// Event mapping, one fixture each
// ---------------------------------------------------------------------------

test('INITIAL_PURCHASE grants pro until expiration_at_ms', async () => {
  const {post, user} = setup();
  const res = await post({event: event('INITIAL_PURCHASE')});
  assert.deepEqual(res, {status: 200, body: 'OK'});
  const u = user();
  assert.equal(u.plan, 'pro');
  assert.equal(u.planExpiresAt.getTime(), T0 + MONTH);
  assert.equal(u.planLapsedAt, null);
  assert.equal(u.planStatus, 'active');
  assert.equal(u.planWillRenew, true);
  assert.equal(u.planProductId, 'taskcaster_pro_monthly');
  assert.equal(u.planStore, 'app_store');
  assert.equal(u.planEnvironment, 'sandbox');
  assert.equal(u.planSource, 'revenuecat');
  assert.equal(u.planLastEventMs, T0);
  assert.equal(u.planUpdatedAt, 'SERVER_TS');
  assert.equal(u.displayName, 'Sam', 'merge: other profile fields untouched');
  assert.equal(effectivePlan(u, T0 + 1), 'pro');
});

test('RENEWAL extends the expiry', async () => {
  const {post, user} = setup();
  await post({event: event('INITIAL_PURCHASE')});
  await post({event: event('RENEWAL', {event_timestamp_ms: T0 + MONTH, expiration_at_ms: T0 + 2 * MONTH})});
  assert.equal(user().plan, 'pro');
  assert.equal(user().planExpiresAt.getTime(), T0 + 2 * MONTH);
});

test('CANCELLATION keeps pro until expiry, then effectivePlan is free', async () => {
  const {post, user} = setup();
  await post({event: event('INITIAL_PURCHASE')});
  await post({event: event('CANCELLATION', {event_timestamp_ms: T0 + 1000, cancel_reason: 'UNSUBSCRIBE'})});
  const u = user();
  assert.equal(u.plan, 'pro');
  assert.equal(u.planStatus, 'cancelled');
  assert.equal(u.planWillRenew, false);
  assert.equal(u.planCancelReason, 'UNSUBSCRIBE');
  assert.equal(effectivePlan(u, T0 + MONTH - 1), 'pro');
  assert.equal(effectivePlan(u, T0 + MONTH + 1), 'free');
});

test('EXPIRATION goes back to free and sets planLapsedAt (the retention clock)', async () => {
  const {post, user} = setup();
  await post({event: event('INITIAL_PURCHASE')});
  await post({event: event('EXPIRATION', {event_timestamp_ms: T0 + MONTH + 5, expiration_reason: 'UNSUBSCRIBE'})});
  const u = user();
  assert.equal(u.plan, 'free');
  assert.equal(u.planStatus, 'expired');
  assert.equal(u.planLapsedAt.getTime(), T0 + MONTH);
  assert.equal(u.planWillRenew, false);
  assert.equal(effectivePlan(u, T0 + MONTH + 10), 'free');
});

test('BILLING_ISSUE keeps pro through the grace period', async () => {
  const {post, user} = setup();
  await post({event: event('INITIAL_PURCHASE')});
  await post({event: event('BILLING_ISSUE', {
    event_timestamp_ms: T0 + MONTH, grace_period_expiration_at_ms: T0 + MONTH + 16 * 86400000,
  })});
  const u = user();
  assert.equal(u.plan, 'pro');
  assert.equal(u.planStatus, 'billing_issue');
  assert.equal(u.planBillingIssue, true);
  assert.equal(u.planExpiresAt.getTime(), T0 + MONTH + 16 * 86400000);
});

test('PRODUCT_CHANGE records the pending product, keeps plan and expiry', async () => {
  const {post, user} = setup();
  await post({event: event('INITIAL_PURCHASE')});
  await post({event: event('PRODUCT_CHANGE', {
    event_timestamp_ms: T0 + 1000, new_product_id: 'taskcaster_pro_yearly',
  })});
  const u = user();
  assert.equal(u.plan, 'pro');
  assert.equal(u.planProductId, 'taskcaster_pro_monthly');
  assert.equal(u.planPendingProductId, 'taskcaster_pro_yearly');
  assert.equal(u.planExpiresAt.getTime(), T0 + MONTH);
  // ...and the RENEWAL on the new product clears it.
  await post({event: event('RENEWAL', {
    event_timestamp_ms: T0 + MONTH, product_id: 'taskcaster_pro_yearly', expiration_at_ms: T0 + 13 * MONTH,
  })});
  assert.equal(user().planProductId, 'taskcaster_pro_yearly');
  assert.equal(user().planPendingProductId, null);
});

test('an EXPIRATION of the old product after a switch does not drop the user to free', async () => {
  const {post, user} = setup();
  await post({event: event('RENEWAL', {product_id: 'taskcaster_pro_yearly', expiration_at_ms: T0 + 12 * MONTH})});
  await post({event: event('EXPIRATION', {event_timestamp_ms: T0 + 5, product_id: 'taskcaster_pro_monthly'})});
  assert.equal(user().plan, 'pro');
  assert.equal(user().planProductId, 'taskcaster_pro_yearly');
});

test('TRANSFER downgrades the losing uid and refreshes the receiving one', async () => {
  const refreshed = [];
  const {post, user} = setup(undefined, {refresh: async (uid) => refreshed.push(uid)});
  await post({event: event('INITIAL_PURCHASE')});
  await post({event: {
    type: 'TRANSFER', event_timestamp_ms: T0 + 100,
    transferred_from: [UID, '$RCAnonymousID:abc'], transferred_to: ['otherUid999', '$RCAnonymousID:x'],
  }});
  assert.equal(user().plan, 'free');
  assert.equal(user().planStatus, 'transferred');
  assert.equal(user().planLapsedAt.getTime(), T0 + 100);
  assert.deepEqual(refreshed, ['otherUid999']);
});

// ---------------------------------------------------------------------------
// What is ignored
// ---------------------------------------------------------------------------

test('stale events (older than planLastEventMs) are ignored', async () => {
  const {post, user} = setup();
  await post({event: event('RENEWAL', {event_timestamp_ms: T0 + MONTH, expiration_at_ms: T0 + 2 * MONTH})});
  // A retried EXPIRATION from before the renewal arrives late.
  const res = await post({event: event('EXPIRATION', {event_timestamp_ms: T0 + 10})});
  assert.equal(res.body, 'Ignored');
  assert.equal(user().plan, 'pro');
  assert.equal(user().planExpiresAt.getTime(), T0 + 2 * MONTH);
});

test('$RCAnonymousID-only events, other products and TEST events are ignored', async () => {
  const {post, user, db} = setup();
  const anon = '$RCAnonymousID:123';
  assert.equal((await post({event: event('INITIAL_PURCHASE', {
    app_user_id: anon, original_app_user_id: anon, aliases: [anon],
  })})).body, 'Ignored');
  assert.equal((await post({event: event('INITIAL_PURCHASE', {
    entitlement_ids: ['other'], product_id: 'someone_elses_product',
  })})).body, 'Ignored');
  assert.equal((await post({event: event('TEST')})).body, 'Ignored');
  assert.equal(user().plan, undefined);
  assert.equal(db.docs.size, 1);
});

test('an event for a deleted account never resurrects users/{uid}', async () => {
  const {post, db} = setup({}, {userExists: async () => false});
  const res = await post({event: event('RENEWAL')});
  assert.equal(res.body, 'Ignored');
  assert.equal(db.peek(`users/${UID}`), null);
});

test('resolveUid skips anonymous ids and picks the first real alias', () => {
  assert.equal(rc.resolveUid({app_user_id: '$RCAnonymousID:1', aliases: ['$RCAnonymousID:1', UID]}), UID);
  assert.equal(rc.resolveUid({app_user_id: '$RCAnonymousID:1'}), null);
  assert.equal(rc.resolveUid({app_user_id: 'bad id!'}), null);
});

test('a Play product id with a base-plan suffix is still ours', () => {
  assert.equal(rc.isProEvent({entitlement_ids: [], product_id: 'taskcaster_pro_yearly:yearly'}), true);
});

// ---------------------------------------------------------------------------
// REST refresh
// ---------------------------------------------------------------------------

function fakeFetch(body, status = 200) {
  const calls = [];
  const fn = async (url, opts) => {
    calls.push({url, opts});
    return {ok: status < 400, status, json: async () => body};
  };
  fn.calls = calls;
  return fn;
}

test('refreshFromRevenueCat: an active entitlement becomes pro, stamped as REST_REFRESH', async () => {
  const {db, deps, user} = setup();
  const fetch = fakeFetch({subscriber: {
    entitlements: {pro: {expires_date: new Date(T0 + MONTH).toISOString(), product_identifier: 'taskcaster_pro_yearly'}},
    subscriptions: {taskcaster_pro_yearly: {expires_date: new Date(T0 + MONTH).toISOString(), store: 'PLAY_STORE'}},
  }});
  const out = await rc.refreshFromRevenueCat(UID, {...deps, db, apiKey: 'sk_test', fetch});
  assert.deepEqual(out, {synced: true, plan: 'pro'});
  assert.match(fetch.calls[0].url, /subscribers\/firebaseUid123$/);
  assert.equal(fetch.calls[0].opts.headers.Authorization, 'Bearer sk_test');
  assert.equal(user().plan, 'pro');
  assert.equal(user().planStatus, 'active');
  assert.equal(user().planStore, 'play_store');
  assert.equal(user().planLastEventType, 'REST_REFRESH');
});

test('refreshFromRevenueCat: no key is a harmless no-op; a lapsed entitlement is free', async () => {
  const {deps, user} = setup();
  assert.deepEqual(await rc.refreshFromRevenueCat(UID, {...deps, apiKey: ''}), {synced: false, reason: 'not-configured'});
  const fetch = fakeFetch({subscriber: {
    entitlements: {pro: {expires_date: new Date(T0 - 1000).toISOString(), product_identifier: 'taskcaster_pro_monthly'}},
    subscriptions: {},
  }});
  await rc.refreshFromRevenueCat(UID, {...deps, apiKey: 'sk', fetch});
  assert.equal(user().plan, 'free');
  assert.equal(user().planLapsedAt.getTime(), T0 - 1000);
  assert.deepEqual(await rc.refreshFromRevenueCat(UID, {...deps, apiKey: 'sk', fetch: fakeFetch({}, 404)}),
    {synced: false, reason: 'revenuecat-404'});
});

test('mapSubscriberToFields: cancelled (unsubscribe detected) and never-subscribed', () => {
  const body = {subscriber: {
    entitlements: {pro: {expires_date: new Date(T0 + 1000).toISOString(), product_identifier: 'taskcaster_pro_monthly'}},
    subscriptions: {taskcaster_pro_monthly: {
      expires_date: new Date(T0 + 1000).toISOString(), unsubscribe_detected_at: new Date(T0).toISOString(),
    }},
  }};
  assert.equal(rc.mapSubscriberToFields(body, T0).planStatus, 'cancelled');
  assert.equal(rc.mapSubscriberToFields({subscriber: {entitlements: {}}}, T0), null);
});
