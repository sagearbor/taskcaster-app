'use strict';

/**
 * Server-side plan enforcement, Firestore side (audit WP-11). The tier table
 * is functions/src/plans.js; this is the glue that reads users/{uid} and
 * answers "may this happen?". Never trust the client: every check here reads
 * the server-owned plan fields the RevenueCat webhook writes.
 *
 * Enforced elsewhere, for the record:
 *   - clip count, slot and upload size  storage.rules (firestore.get of users/{uid})
 *   - clip length                       transcode.js trims to clipSecondsFor()
 *   - friend-game montages              pipeline.handleNewPost -> hostMayMontage()
 *   - retention                         retention.js
 */

const {effectivePlan, clipSecondsFor, planLimitError} = require('./plans');

const USERS = 'users';

/** users/{uid} data, or null. `db` is the Admin Firestore (or a fake). */
async function getUserData(db, uid) {
  if (!uid || typeof uid !== 'string') return null;
  const snap = await db.collection(USERS).doc(uid).get();
  return snap.exists ? snap.data() : null;
}

/** 'pro' | 'free' for a uid, from the server-owned fields. */
async function planOf(db, uid, now = Date.now()) {
  return effectivePlan(await getUserData(db, uid), now);
}

/**
 * Friend-game montages are a Pro feature of the HOST: a game renders its
 * finale + moments reel only when `game.creatorId` holds an active Pro plan,
 * and then every player in it gets them (one payer unlocks the room).
 * Starter Pack montages are shared and free; they never reach this check.
 */
async function hostMayMontage(db, game, now = Date.now()) {
  if (!game || !game.creatorId) return false;
  return (await planOf(db, String(game.creatorId), now)) === 'pro';
}

/** The transcode length cap for a clip at submissions/{uid}/{day}/{slot}. */
async function clipSecondsForUpload(db, {uid, day}, now = Date.now()) {
  if (day === 'guest') return clipSecondsFor({day});
  return clipSecondsFor({day, userData: await getUserData(db, uid), now});
}

/**
 * Throw the typed plan-limit refusal unless `uid` is Pro. For future
 * Pro-only callables (custom task packs, the AI task generator).
 */
async function assertPro(db, uid, limitKey, now = Date.now()) {
  const plan = await planOf(db, uid, now);
  if (plan !== 'pro') throw planLimitError(limitKey, plan);
  return plan;
}

module.exports = {
  USERS,
  getUserData,
  planOf,
  hostMayMontage,
  clipSecondsForUpload,
  assertPro,
};
