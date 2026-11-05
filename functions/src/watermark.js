'use strict';

/**
 * The free-tier watermark on rendered montages (audit WP-09): a small
 * "taskcaster.app" burned into the corner of every finale/moments frame, so a
 * finale downloaded and reposted anywhere still carries the brand.
 *
 * Pro hosts get clean renders. Plans are owned by WP-11: [isPro] reads the
 * server-owned plan fields on users/{uid} (written only by the RevenueCat
 * webhook / refreshEntitlement) through entitlements.planOf.
 */

const {planOf} = require('./entitlements');

const WATERMARK_TEXT = 'taskcaster.app';

/**
 * Whether [uid] has an active Pro plan right now: users/{uid}.plan == 'pro'
 * and planExpiresAt in the future (or none), the same test as storage.rules
 * and functions/src/plans.js effectivePlan(). Async, never throws, false on
 * any doubt (no uid, no doc, a read error).
 *
 * @param {string|null|undefined} uid
 * @param {{db?: object, now?: number}} [deps] db defaults to the Admin SDK's
 * @returns {Promise<boolean>}
 */
async function isPro(uid, deps = {}) {
  if (!uid || typeof uid !== 'string') return false;
  try {
    const db = deps.db || require('firebase-admin/firestore').getFirestore();
    return (await planOf(db, uid, deps.now || Date.now())) === 'pro';
  } catch {
    return false;
  }
}

/**
 * The watermark text for a render, or null for a clean one.
 *
 * Starter Pack montages are shared by everyone, so they are always branded.
 * A friend-game montage is clean only when the game's HOST is Pro (one payer
 * unlocks the room, per the WP-11 plan table).
 *
 * @param {{gameId: string, taskId: string, isStarter: boolean,
 *          getGame: (gameId: string) => Promise<object|null>,
 *          isProFn?: (uid: string) => Promise<boolean>}} args
 * @returns {Promise<string|null>}
 */
async function watermarkFor({gameId, isStarter, getGame, isProFn = isPro}) {
  if (isStarter) return WATERMARK_TEXT;
  try {
    const game = await getGame(gameId);
    const host = game && typeof game.creatorId === 'string' ? game.creatorId : null;
    if (host && (await isProFn(host))) return null;
  } catch {
    /* any doubt: watermark */
  }
  return WATERMARK_TEXT;
}

module.exports = {WATERMARK_TEXT, isPro, watermarkFor};
