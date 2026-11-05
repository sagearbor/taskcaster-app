'use strict';

/**
 * RevenueCat -> users/{uid} plan sync (audit WP-11, docs/MONETIZATION.md).
 * Ported from oralhistory_timeline functions/src/revenuecat.ts, cut down to
 * TaskCaster's one paid level ('pro').
 *
 * Two inputs, one output (the server-owned plan* fields on users/{uid}):
 *   1. `revenuecatWebhook` (HTTPS): RevenueCat POSTs every subscription
 *      lifecycle event. The request's Authorization header must equal the
 *      Secret Manager secret REVENUECAT_WEBHOOK_AUTH (the same value is typed
 *      into RevenueCat's webhook settings). No secret -> 503, wrong -> 401.
 *   2. `refreshEntitlement` (callable): the app calls it right after a
 *      purchase or Restore Purchases; the server re-reads the subscriber from
 *      RevenueCat's REST API (secret REVENUECAT_SECRET_API_KEY). Covers webhook
 *      delays and TRANSFER events.
 *
 * Identity: RevenueCat's app_user_id IS the Firebase uid. The app calls
 * Purchases.logIn(uid) before any purchase and only for a non-anonymous
 * account, so $RCAnonymousID events never own a plan here and are ignored.
 *
 * Fields written (all server-owned, see firestore.rules serverOwnedPlanFields):
 *   plan             'pro' | 'free'
 *   planExpiresAt    Timestamp | null   end of the paid period (grace included)
 *   planLapsedAt     Timestamp | null   when Pro last ended (retention clock)
 *   planStatus       'active' | 'cancelled' | 'billing_issue' | 'paused' |
 *                    'expired' | 'transferred'
 *   planWillRenew, planBillingIssue, planCancelReason,
 *   planProductId, planPendingProductId, planStore, planEnvironment,
 *   planSource ('revenuecat'), planUpdatedAt,
 *   planLastEventMs, planLastEventType  (out-of-order guard)
 *
 * Everything is injected (db, Timestamp, FieldValue, fetch, userExists), so
 * the whole mapping and the webhook are unit-tested with no emulator.
 */

const crypto = require('crypto');

const {ENTITLEMENT, PRODUCT_IDS, toMillis} = require('./plans');

const USERS = 'users';

/** Event types that (re)grant Pro until expiration_at_ms. */
const GRANT_TYPES = new Set([
  'INITIAL_PURCHASE',
  'RENEWAL',
  'UNCANCELLATION',
  'NON_RENEWING_PURCHASE',
  'SUBSCRIPTION_EXTENDED',
  'TEMPORARY_ENTITLEMENT_GRANT',
  'REFUND_REVERSED',
]);

const UID_RE = /^[A-Za-z0-9_-]{6,128}$/;
const isAnonymousRcId = (id) => typeof id === 'string' && id.startsWith('$RCAnonymousID');

// ---------------------------------------------------------------- auth ----

/**
 * Constant-time compare of the Authorization header against the secret.
 * Accepts the value verbatim or as "Bearer <value>".
 */
function verifyWebhookAuth(header, secret) {
  if (!secret || !header || typeof header !== 'string') return false;
  const h = header.trim();
  const want = Buffer.from(String(secret).trim());
  return [h, h.replace(/^Bearer\s+/i, '')].some((candidate) => {
    const got = Buffer.from(candidate);
    return got.length === want.length && crypto.timingSafeEqual(got, want);
  });
}

// ------------------------------------------------------------- mapping ----

/** Store product id without Play's ":basePlan" suffix. */
const baseProductId = (pid) => String(pid || '').split(':')[0];

const isOurProduct = (pid) => PRODUCT_IDS.includes(baseProductId(pid));

/** First non-anonymous RevenueCat id on the event (== our Firebase uid). */
function resolveUid(e) {
  const ids = [e.app_user_id, e.original_app_user_id, ...(e.aliases || [])];
  for (const id of ids) {
    if (typeof id === 'string' && !isAnonymousRcId(id) && UID_RE.test(id)) return id;
  }
  return null;
}

/** Does this event concern TaskCaster Pro (entitlement or product)? */
function isProEvent(e) {
  const ents = [...(e.entitlement_ids || []), ...(e.entitlement_id ? [e.entitlement_id] : [])];
  return ents.includes(ENTITLEMENT) || isOurProduct(e.product_id) || isOurProduct(e.new_product_id);
}

/**
 * Pure: one RevenueCat event -> the users/{uid} field changes it implies.
 * Returns [] for events deliberately ignored (TEST, other products,
 * anonymous-only ids, informational types).
 *
 * @returns {Array<{uid: string, fields: object}>} fields use *Ms numbers for
 *   timestamps; toFirestoreFields converts them.
 */
function mapEventToChanges(e) {
  if (!e || typeof e.type !== 'string') return [];
  const eventMs = Number(e.event_timestamp_ms) || 0;
  const base = {planSource: 'revenuecat', planLastEventMs: eventMs, planLastEventType: e.type};

  if (e.type === 'TRANSFER') {
    // The subscription moved to another RevenueCat user. The losing side is
    // downgraded now (and its retention clock starts); the receiving side is
    // filled in by refreshFromRevenueCat (the event carries no expiry for it).
    return (e.transferred_from || [])
      .filter((id) => UID_RE.test(id) && !isAnonymousRcId(id))
      .map((uid) => ({
        uid,
        fields: {
          ...base,
          plan: 'free',
          planStatus: 'transferred',
          planWillRenew: false,
          planLapsedAtMs: eventMs || null,
        },
      }));
  }

  if (!isProEvent(e)) return [];
  const uid = resolveUid(e);
  if (!uid) return [];

  const product = {
    ...(e.product_id ? {planProductId: e.product_id} : {}),
    ...(e.store ? {planStore: String(e.store).toLowerCase()} : {}),
    ...(e.environment ? {planEnvironment: String(e.environment).toLowerCase()} : {}),
  };
  const exp = e.expiration_at_ms === undefined || e.expiration_at_ms === null
    ? null
    : Number(e.expiration_at_ms);

  if (GRANT_TYPES.has(e.type)) {
    return [{
      uid,
      fields: {
        ...base,
        ...product,
        plan: 'pro',
        planExpiresAtMs: exp,
        planLapsedAtMs: null,
        planStatus: 'active',
        planWillRenew: e.type !== 'NON_RENEWING_PURCHASE',
        planBillingIssue: false,
        planPendingProductId: null,
      },
    }];
  }

  switch (e.type) {
    case 'CANCELLATION':
      // Auto-renew turned off: Pro stays in force until planExpiresAt. (A
      // refund also arrives as CANCELLATION with expiration_at_ms = the refund
      // time, so effectivePlan() drops to free at once.)
      return [{
        uid,
        fields: {
          ...base,
          ...product,
          plan: 'pro',
          planExpiresAtMs: exp,
          planStatus: 'cancelled',
          planWillRenew: false,
          ...(e.cancel_reason ? {planCancelReason: String(e.cancel_reason)} : {}),
        },
      }];
    case 'BILLING_ISSUE':
      // Store retry / grace period: keep Pro until the grace period ends.
      return [{
        uid,
        fields: {
          ...base,
          ...product,
          plan: 'pro',
          planExpiresAtMs: e.grace_period_expiration_at_ms ?? exp,
          planStatus: 'billing_issue',
          planBillingIssue: true,
        },
      }];
    case 'PRODUCT_CHANGE':
      // Monthly <-> yearly. The current period keeps its product and expiry;
      // the switch takes effect at renewal, whose RENEWAL event carries the
      // new product. Record what is coming so the plan card can say so.
      return [{
        uid,
        fields: {
          ...base,
          planPendingProductId: e.new_product_id ? String(e.new_product_id) : null,
        },
      }];
    case 'SUBSCRIPTION_PAUSED':
      // Play pause: takes effect at the period end, then EXPIRATION follows.
      return [{uid, fields: {...base, planWillRenew: false, planStatus: 'paused'}}];
    case 'EXPIRATION':
      return [{
        uid,
        fields: {
          ...base,
          ...product,
          plan: 'free',
          planExpiresAtMs: exp,
          // Starts the post-lapse retention clock (plans.js clipRetention).
          planLapsedAtMs: exp ?? (eventMs || null),
          planStatus: 'expired',
          planWillRenew: false,
          planBillingIssue: false,
          planPendingProductId: null,
          ...(e.expiration_reason ? {planCancelReason: String(e.expiration_reason)} : {}),
        },
      }];
    default:
      return [];
  }
}

/** Convert a change's plain fields to Firestore write values. */
function toFirestoreFields(fields, {Timestamp, FieldValue}) {
  const out = {...fields};
  for (const [msKey, key] of [['planExpiresAtMs', 'planExpiresAt'], ['planLapsedAtMs', 'planLapsedAt']]) {
    if (msKey in out) {
      const ms = out[msKey];
      delete out[msKey];
      out[key] = ms === null || ms === undefined ? null : Timestamp.fromMillis(Number(ms));
    }
  }
  out.planUpdatedAt = FieldValue.serverTimestamp();
  return out;
}

/**
 * True when a negative event (expiration / cancellation / billing issue) is
 * about a product the user has since MOVED OFF (the old monthly expiring
 * after a switch to yearly): applying it would wrongly drop them to free.
 * REST refreshes are authoritative and never skipped.
 */
function isSupersededProductEvent(stored, fields, now = Date.now()) {
  if (fields.planLastEventType === 'REST_REFRESH') return false;
  if (!['expired', 'cancelled', 'billing_issue'].includes(fields.planStatus)) return false;
  const incoming = baseProductId(fields.planProductId);
  const current = baseProductId(stored && stored.planProductId);
  if (!incoming || !current || incoming === current) return false;
  if (!stored || stored.plan !== 'pro') return false;
  const exp = toMillis(stored.planExpiresAt);
  return exp === null || exp > now;
}

/**
 * Apply changes, one transaction per user. Skipped:
 *   - an event older than the last one applied for that user (RevenueCat
 *     retries and may deliver out of order);
 *   - a negative event for a product the user has already moved off;
 *   - a uid with no Firebase Auth account (deleted accounts stay deleted: a
 *     late RENEWAL must not resurrect users/{uid}).
 *
 * @param {object} db Admin Firestore (or the test fake)
 * @param {Array} changes from mapEventToChanges / mapSubscriberToFields
 * @param {object} deps {Timestamp, FieldValue, userExists?: (uid) => Promise<boolean>, now?}
 * @returns {Promise<{applied: number, skipped: Array<{uid: string, reason: string}>}>}
 */
async function applyChanges(db, changes, deps) {
  const {userExists = async () => true, now = Date.now()} = deps;
  let applied = 0;
  const skipped = [];
  for (const ch of changes) {
    // eslint-disable-next-line no-await-in-loop
    if (!(await userExists(ch.uid))) {
      skipped.push({uid: ch.uid, reason: 'no-such-user'});
      continue;
    }
    const ref = db.collection(USERS).doc(ch.uid);
    // eslint-disable-next-line no-await-in-loop
    const verdict = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const stored = snap.exists ? snap.data() : null;
      const last = Number(stored && stored.planLastEventMs) || 0;
      const incoming = Number(ch.fields.planLastEventMs) || 0;
      if (incoming && last && incoming < last) return 'stale';
      if (stored && isSupersededProductEvent(stored, ch.fields, now)) return 'superseded';
      tx.set(ref, toFirestoreFields(ch.fields, deps), {merge: true});
      return 'applied';
    });
    if (verdict === 'applied') applied += 1;
    else skipped.push({uid: ch.uid, reason: verdict});
  }
  return {applied, skipped};
}

// ------------------------------------------------------------- webhook ----

/**
 * The webhook, minus the Cloud Functions wrapper.
 *
 * @param {{method: string, headers: object, body: any}} req
 * @param {object} deps {secret, db, Timestamp, FieldValue, userExists?,
 *   refresh?: (uid) => Promise, logger?}
 * @returns {Promise<{status: number, body: string}>}
 */
async function handleWebhook(req, deps) {
  const {secret, db, refresh, logger = console} = deps;
  if (req.method !== 'POST') return {status: 405, body: 'Method not allowed'};
  if (!secret || !String(secret).trim()) return {status: 503, body: 'Webhook auth not configured'};
  const headers = req.headers || {};
  if (!verifyWebhookAuth(headers.authorization || headers.Authorization, secret)) {
    return {status: 401, body: 'Unauthorized'};
  }
  const event = req.body && req.body.event;
  if (!event || typeof event.type !== 'string') return {status: 400, body: 'No event'};

  try {
    const changes = mapEventToChanges(event);
    const result = await applyChanges(db, changes, deps);
    if (event.type === 'TRANSFER' && refresh) {
      for (const uid of event.transferred_to || []) {
        if (UID_RE.test(uid) && !isAnonymousRcId(uid)) {
          // eslint-disable-next-line no-await-in-loop
          await refresh(uid).catch((err) => logger.warn('revenuecat: transfer refresh failed', {uid, error: err.message}));
        }
      }
    }
    logger.info('revenuecat: event', {
      type: event.type, id: event.id, applied: result.applied, skipped: result.skipped,
    });
    return {status: 200, body: result.applied ? 'OK' : 'Ignored'};
  } catch (err) {
    // 5xx -> RevenueCat retries with backoff.
    logger.error('revenuecat: webhook failed', {error: err.message});
    return {status: 500, body: 'Error'};
  }
}

// ---------------------------------------------------- REST refresh path ----

/**
 * Pure: RevenueCat REST `GET /v1/subscribers/{id}` body -> plan fields, or
 * null when the subscriber has never had the `pro` entitlement.
 */
function mapSubscriberToFields(body, now = Date.now()) {
  const sub = body && body.subscriber;
  const ent = sub && sub.entitlements && sub.entitlements[ENTITLEMENT];
  if (!ent) return null;
  const expRaw = ent.grace_period_expires_date || ent.expires_date;
  const expMs = expRaw ? Date.parse(expRaw) : null;
  const active = expMs === null || expMs > now;
  const pid = ent.product_identifier;
  const s = pid && sub.subscriptions ? sub.subscriptions[pid] : undefined;
  const willRenew = !!s && !s.unsubscribe_detected_at && !!s.expires_date;
  const billingIssue = !!(s && s.billing_issues_detected_at);
  let status = 'expired';
  if (active) status = billingIssue ? 'billing_issue' : (willRenew || !s ? 'active' : 'cancelled');
  return {
    planSource: 'revenuecat',
    plan: active ? 'pro' : 'free',
    planExpiresAtMs: expMs,
    planLapsedAtMs: active ? null : expMs,
    planStatus: status,
    planWillRenew: active && willRenew,
    planBillingIssue: billingIssue,
    ...(pid ? {planProductId: pid} : {}),
    ...(s && s.store ? {planStore: String(s.store).toLowerCase()} : {}),
  };
}

/**
 * Re-read one subscriber from RevenueCat and store the result.
 * @param {string} uid
 * @param {object} deps {apiKey, fetch, db, Timestamp, FieldValue, userExists?, now?}
 */
async function refreshFromRevenueCat(uid, deps) {
  const {apiKey, fetch: fetchImpl = globalThis.fetch, db} = deps;
  const now = deps.now || Date.now();
  const key = String(apiKey || '').trim();
  if (!key) return {synced: false, reason: 'not-configured'};
  const resp = await fetchImpl(
    `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(uid)}`,
    {headers: {Authorization: `Bearer ${key}`, Accept: 'application/json'}},
  );
  if (!resp.ok) return {synced: false, reason: `revenuecat-${resp.status}`};
  const fields = mapSubscriberToFields(await resp.json(), now);
  if (!fields) return {synced: true, plan: 'free'};
  // REST state is "now": stamp it so an older webhook retry cannot undo it.
  fields.planLastEventMs = now;
  fields.planLastEventType = 'REST_REFRESH';
  await applyChanges(db, [{uid, fields}], {...deps, now});
  return {synced: true, plan: fields.plan};
}

module.exports = {
  GRANT_TYPES,
  verifyWebhookAuth,
  resolveUid,
  isProEvent,
  mapEventToChanges,
  toFirestoreFields,
  isSupersededProductEvent,
  applyChanges,
  handleWebhook,
  mapSubscriberToFields,
  refreshFromRevenueCat,
};
