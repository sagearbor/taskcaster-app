'use strict';

/**
 * The free-tier watermark on rendered montages (audit WP-09): a small
 * "taskcaster.app" burned into the corner of every finale/moments frame, so a
 * finale downloaded and reposted anywhere still carries the brand.
 *
 * Pro hosts get clean renders. Plans are owned by WP-11 (RevenueCat
 * entitlements in functions/src/plans.js + entitlements.js); until that
 * lands, [isPro] is a stub that says "free" for everyone, so every render is
 * watermarked.
 */

const WATERMARK_TEXT = 'taskcaster.app';

/**
 * Whether [uid] has an active Pro plan.
 *
 * TODO(WP-11): wire this to the server-owned plan fields on users/{uid}
 * (plan == 'pro' && planExpiresAt > now), via WP-11's entitlements helper.
 * Keep the signature: async, never throws, false on any doubt.
 *
 * @param {string|null|undefined} _uid
 * @param {{db?: object}} [_deps]
 * @returns {Promise<boolean>}
 */
async function isPro(_uid, _deps = {}) {
  return false;
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
