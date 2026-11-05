'use strict';

/**
 * TaskCaster plans (audit WP-11): the server's copy of the tier table.
 * Mirrored for UI only in lib/core/services/plans/plans.dart; THIS file and
 * storage.rules are what is enforced. See docs/MONETIZATION.md.
 *
 *              clips                       length  upload cap  retention
 *   guest      5 lifetime (guest/0..4)     20 s    32 MiB      free rules
 *   free       3 per UTC day (slots 0-2)   20 s    32 MiB      90 days; keepers 1 year
 *   pro        15 per UTC day (0-9, a-e)   60 s    96 MiB      while subscribed; after a
 *                                                              lapse at most 1 year
 *
 * Pro also unlocks server-rendered montages for friend games the Pro user
 * HOSTS (every player in that game sees them).
 *
 * The plan lives in server-owned fields on users/{uid}, written only by the
 * RevenueCat webhook / refreshEntitlement (revenuecat.js); firestore.rules
 * refuses any client write to them (serverOwnedPlanFields()).
 *
 * Everything here is pure (no Firebase), so it is unit-tested directly.
 */

const ENTITLEMENT = 'pro';
const PRODUCT_IDS = Object.freeze(['taskcaster_pro_monthly', 'taskcaster_pro_yearly']);

const MiB = 1024 * 1024;
const DAY_MS = 24 * 60 * 60 * 1000;

const LIMITS = Object.freeze({
  guest: Object.freeze({clipsLifetime: 5, clipsPerDay: null, clipSeconds: 20, maxUploadBytes: 32 * MiB}),
  free: Object.freeze({clipsLifetime: null, clipsPerDay: 3, clipSeconds: 20, maxUploadBytes: 32 * MiB}),
  pro: Object.freeze({clipsLifetime: null, clipsPerDay: 15, clipSeconds: 60, maxUploadBytes: 96 * MiB}),
});

/**
 * Retention (owner rule 2026-11-05: never keep data forever).
 *   - A clip of a user without an active Pro plan is deleted FREE_RETENTION_DAYS
 *     after it was created, or KEEPER_RETENTION_DAYS when it is a "keeper"
 *     (spliced into a montage, or graded KEEPER_MIN_AVG_GRADE+ on average).
 *   - While Pro is active nothing is deleted.
 *   - After a Pro plan lapses, clips fall back to the free rules, but each one
 *     gets at least LAPSE_GRACE_DAYS from the lapse (time to resubscribe) and
 *     never more than LAPSE_MAX_DAYS from it.
 *   Nothing is therefore ever kept more than one year without an active Pro
 *   subscription. Account deletion is separate and immediate
 *   (account_deletion.js).
 */
const FREE_RETENTION_DAYS = 90;
const KEEPER_RETENTION_DAYS = 365;
const KEEPER_MIN_AVG_GRADE = 4;
const LAPSE_GRACE_DAYS = 90;
const LAPSE_MAX_DAYS = 365;

/**
 * How often an active Pro user's clips are looked at again when the plan has
 * no expiry (an admin grant): cheap, and catches a revoked grant.
 */
const PRO_RECHECK_DAYS = 30;

/** Firestore Timestamp | Date | ms | ISO string -> ms, or null. */
function toMillis(value) {
  if (value === null || value === undefined) return null;
  if (typeof value === 'number') return Number.isFinite(value) ? value : null;
  if (typeof value === 'string') {
    const ms = Date.parse(value);
    return Number.isNaN(ms) ? null : ms;
  }
  if (value instanceof Date) return value.getTime();
  if (typeof value.toMillis === 'function') return value.toMillis();
  if (typeof value.seconds === 'number') return value.seconds * 1000;
  if (typeof value._seconds === 'number') return value._seconds * 1000;
  return null;
}

/**
 * The plan a users/{uid} document is entitled to RIGHT NOW: 'pro' or 'free'.
 * `plan == 'pro'` with a past `planExpiresAt` is free (the EXPIRATION webhook
 * may be late); `plan == 'pro'` with no expiry is an open-ended grant.
 * Same test as storage.rules isPro().
 */
function effectivePlan(userData, now = Date.now()) {
  if (!userData || userData.plan !== 'pro') return 'free';
  const exp = toMillis(userData.planExpiresAt);
  if (exp !== null && exp <= now) return 'free';
  return 'pro';
}

const isPro = (userData, now = Date.now()) => effectivePlan(userData, now) === 'pro';

/** When the user's last Pro plan ended, in ms, or null if never / still active. */
function lapsedAtMs(userData, now = Date.now()) {
  if (!userData || isPro(userData, now)) return null;
  const lapsed = toMillis(userData.planLapsedAt);
  if (lapsed !== null) return lapsed;
  // EXPIRATION webhook not in yet, but the paid period is over.
  if (userData.plan === 'pro') return toMillis(userData.planExpiresAt);
  return null;
}

/** Limits for a plan id ('guest' | 'free' | 'pro'); unknown -> free. */
function limitsFor(plan) {
  return LIMITS[plan] || LIMITS.free;
}

/**
 * The server-side clip-length cap for an upload at `submissions/{uid}/{day}/{slot}`.
 * Guest-path uploads always get the guest cap, whatever the user doc says.
 */
function clipSecondsFor({day, userData, now = Date.now()}) {
  if (day === 'guest') return LIMITS.guest.clipSeconds;
  return limitsFor(effectivePlan(userData, now)).clipSeconds;
}

/** Average crowd grade of a feed post, or 0 when ungraded. */
function averageGrade(post) {
  const count = Number(post && post.gradeCount) || 0;
  if (count <= 0) return 0;
  return (Number(post.gradeSum) || 0) / count;
}

/**
 * The retention verdict for one clip.
 *
 * @param {object} args
 * @param {number} args.createdAtMs   when the clip doc was created
 * @param {object|null} args.user     users/{uid} data (null: no such user)
 * @param {boolean} args.keeper       in a montage, or graded 4+ on average
 * @param {number} [args.now]
 * @returns {{action: 'delete'|'keep', reason: string, recheckAtMs?: number}}
 *   `recheckAtMs` is when the sweep should look at the clip again; it is the
 *   clip's deadline when one is known, so a kept clip is not re-read daily.
 */
function clipRetention({createdAtMs, user, keeper, now = Date.now()}) {
  const created = Number(createdAtMs);
  if (!Number.isFinite(created) || created <= 0) {
    // No creation time is a broken doc: give it the free window from now.
    return {action: 'keep', reason: 'no-created-at', recheckAtMs: now + FREE_RETENTION_DAYS * DAY_MS};
  }

  if (user && isPro(user, now)) {
    const exp = toMillis(user.planExpiresAt);
    const recheck = exp !== null ? exp + 1000 : now + PRO_RECHECK_DAYS * DAY_MS;
    return {action: 'keep', reason: 'pro-active', recheckAtMs: Math.max(recheck, now + 60 * 60 * 1000)};
  }

  let deadline = created + (keeper ? KEEPER_RETENTION_DAYS : FREE_RETENTION_DAYS) * DAY_MS;
  const lapsed = lapsedAtMs(user, now);
  if (lapsed !== null) {
    deadline = Math.max(deadline, lapsed + LAPSE_GRACE_DAYS * DAY_MS);
    deadline = Math.min(deadline, lapsed + LAPSE_MAX_DAYS * DAY_MS);
  }
  // Hard cap, whatever happened above: one year after creation or after the
  // lapse, whichever is later. (Both branches above already respect it.)
  if (now >= deadline) return {action: 'delete', reason: keeper ? 'keeper-expired' : 'expired'};
  return {action: 'keep', reason: keeper ? 'keeper' : 'within-window', recheckAtMs: deadline};
}

/** The details object every plan-limited server call refuses with. */
function limitErrorDetails(limitKey, plan = 'free') {
  return {reason: 'plan-limit', limitKey, plan, upgradePlan: 'pro'};
}

/**
 * Build the typed refusal for a plan-limited callable:
 * resource-exhausted + {reason:'plan-limit', limitKey, upgradePlan:'pro'}.
 * The app turns it into the upgrade prompt.
 */
function planLimitError(limitKey, plan = 'free', message) {
  // Lazy require keeps this module loadable without firebase-functions.
  const {HttpsError} = require('firebase-functions/v2/https');
  return new HttpsError(
    'resource-exhausted',
    message || `That needs TaskCaster Pro (${limitKey}).`,
    limitErrorDetails(limitKey, plan),
  );
}

module.exports = {
  ENTITLEMENT,
  PRODUCT_IDS,
  LIMITS,
  DAY_MS,
  FREE_RETENTION_DAYS,
  KEEPER_RETENTION_DAYS,
  KEEPER_MIN_AVG_GRADE,
  LAPSE_GRACE_DAYS,
  LAPSE_MAX_DAYS,
  PRO_RECHECK_DAYS,
  toMillis,
  effectivePlan,
  isPro,
  lapsedAtMs,
  limitsFor,
  clipSecondsFor,
  averageGrade,
  clipRetention,
  limitErrorDetails,
  planLimitError,
};
