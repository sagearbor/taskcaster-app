'use strict';

/**
 * WP-11 tier table + retention verdicts (functions/src/plans.js). Pure.
 */

const test = require('node:test');
const assert = require('node:assert/strict');

const p = require('../src/plans');
const {assertPro, hostMayMontage, clipSecondsForUpload} = require('../src/entitlements');
const {makeFakeFirestore} = require('./fake_firestore');

const NOW = Date.parse('2026-11-05T12:00:00Z');
const DAY = p.DAY_MS;

test('the tier table matches docs/MONETIZATION.md', () => {
  assert.equal(p.ENTITLEMENT, 'pro');
  assert.deepEqual([...p.PRODUCT_IDS], ['taskcaster_pro_monthly', 'taskcaster_pro_yearly']);
  assert.equal(p.LIMITS.guest.clipsLifetime, 5);
  assert.equal(p.LIMITS.guest.clipSeconds, 20);
  assert.equal(p.LIMITS.free.clipsPerDay, 3);
  assert.equal(p.LIMITS.free.clipSeconds, 20);
  assert.equal(p.LIMITS.pro.clipsPerDay, 15);
  assert.equal(p.LIMITS.pro.clipSeconds, 60);
});

test('effectivePlan: pro only with plan == pro and an expiry in the future (or none)', () => {
  assert.equal(p.effectivePlan(null, NOW), 'free');
  assert.equal(p.effectivePlan({}, NOW), 'free');
  assert.equal(p.effectivePlan({plan: 'free'}, NOW), 'free');
  assert.equal(p.effectivePlan({plan: 'pro', planExpiresAt: new Date(NOW + DAY)}, NOW), 'pro');
  assert.equal(p.effectivePlan({plan: 'pro', planExpiresAt: new Date(NOW - 1)}, NOW), 'free',
    'a late EXPIRATION webhook cannot keep Pro alive');
  assert.equal(p.effectivePlan({plan: 'pro', planExpiresAt: null}, NOW), 'pro', 'open-ended grant');
  assert.equal(p.effectivePlan({plan: 'pro', planExpiresAt: {toMillis: () => NOW + 5}}, NOW), 'pro');
  assert.equal(p.effectivePlan({plan: 'PRO'}, NOW), 'free');
});

test('clipSecondsFor: guest path is always 20 s; otherwise the plan cap', () => {
  const pro = {plan: 'pro', planExpiresAt: new Date(NOW + DAY)};
  assert.equal(p.clipSecondsFor({day: 'guest', userData: pro, now: NOW}), 20);
  assert.equal(p.clipSecondsFor({day: '20261105', userData: pro, now: NOW}), 60);
  assert.equal(p.clipSecondsFor({day: '20261105', userData: {plan: 'free'}, now: NOW}), 20);
  assert.equal(p.clipSecondsFor({day: '20261105', userData: null, now: NOW}), 20);
});

test('lapsedAtMs: planLapsedAt, else the past expiry of a pro plan, else null', () => {
  assert.equal(p.lapsedAtMs({plan: 'free', planLapsedAt: new Date(NOW - DAY)}, NOW), NOW - DAY);
  assert.equal(p.lapsedAtMs({plan: 'pro', planExpiresAt: new Date(NOW - 2 * DAY)}, NOW), NOW - 2 * DAY);
  assert.equal(p.lapsedAtMs({plan: 'pro', planExpiresAt: new Date(NOW + DAY)}, NOW), null);
  assert.equal(p.lapsedAtMs({plan: 'free'}, NOW), null);
});

// ---------------------------------------------------------------------------
// Retention verdicts (owner rule 2026-11-05)
// ---------------------------------------------------------------------------

const verdict = (createdDaysAgo, user, keeper = false) =>
  p.clipRetention({createdAtMs: NOW - createdDaysAgo * DAY, user, keeper, now: NOW});

test('free: kept for 90 days, deleted after; recheck lands on the deadline', () => {
  const kept = verdict(89, {plan: 'free'});
  assert.equal(kept.action, 'keep');
  assert.equal(kept.recheckAtMs, NOW + DAY);
  assert.equal(verdict(90, {plan: 'free'}).action, 'delete');
  assert.equal(verdict(91, null).action, 'delete', 'no user doc (a guest) = free rules');
});

test('free keeper (montage or graded 4+): kept for one year, never longer', () => {
  assert.equal(verdict(200, {plan: 'free'}, true).action, 'keep');
  assert.equal(verdict(364, {plan: 'free'}, true).action, 'keep');
  assert.equal(verdict(365, {plan: 'free'}, true).action, 'delete');
});

test('pro: kept while subscribed; rechecked at the end of the paid period', () => {
  const user = {plan: 'pro', planExpiresAt: new Date(NOW + 20 * DAY)};
  const v = verdict(1000, user);
  assert.equal(v.action, 'keep');
  assert.equal(v.reason, 'pro-active');
  assert.ok(v.recheckAtMs > NOW + 20 * DAY && v.recheckAtMs < NOW + 21 * DAY);
  const grant = verdict(1000, {plan: 'pro', planExpiresAt: null});
  assert.equal(grant.recheckAtMs, NOW + p.PRO_RECHECK_DAYS * DAY);
});

test('lapsed pro: at least 90 days of grace, never more than 1 year after the lapse', () => {
  // Lapsed 10 days ago: an old clip still has 80 days of grace.
  const recent = {plan: 'free', planLapsedAt: new Date(NOW - 10 * DAY)};
  const v = verdict(800, recent);
  assert.equal(v.action, 'keep');
  assert.equal(v.recheckAtMs, NOW + 80 * DAY);
  // Lapsed 91 days ago: an old, non-keeper clip goes.
  assert.equal(verdict(800, {plan: 'free', planLapsedAt: new Date(NOW - 91 * DAY)}).action, 'delete');
  // A keeper created just before the lapse keeps its own year...
  assert.equal(verdict(200, {plan: 'free', planLapsedAt: new Date(NOW - 150 * DAY)}, true).action, 'keep');
  // ...but nothing survives a year past the lapse.
  assert.equal(verdict(30, {plan: 'free', planLapsedAt: new Date(NOW - 365 * DAY)}, true).action, 'delete');
});

test('HARD CAP: no combination keeps a clip more than a year without active Pro', () => {
  for (const created of [0, 30, 89, 90, 200, 364, 365, 400, 2000]) {
    for (const lapsedAgo of [null, 0, 10, 90, 200, 364, 365, 500]) {
      for (const keeper of [false, true]) {
        const user = lapsedAgo === null ? {plan: 'free'} : {plan: 'free', planLapsedAt: new Date(NOW - lapsedAgo * DAY)};
        const v = verdict(created, user, keeper);
        if (v.action !== 'keep') continue;
        const createdAt = NOW - created * DAY;
        const lapse = lapsedAgo === null ? -Infinity : NOW - lapsedAgo * DAY;
        assert.ok(v.recheckAtMs <= Math.max(createdAt, lapse) + 365 * DAY,
          `created ${created}d ago, lapsed ${lapsedAgo}d ago, keeper ${keeper}`);
      }
    }
  }
});

test('averageGrade', () => {
  assert.equal(p.averageGrade({gradeCount: 0, gradeSum: 0}), 0);
  assert.equal(p.averageGrade({gradeCount: 2, gradeSum: 9}), 4.5);
  assert.equal(p.averageGrade(null), 0);
});

test('planLimitError is resource-exhausted with {reason:plan-limit, limitKey, upgradePlan:pro}', () => {
  const err = p.planLimitError('customPacks');
  assert.equal(err.code, 'resource-exhausted');
  assert.deepEqual(err.details, {reason: 'plan-limit', limitKey: 'customPacks', plan: 'free', upgradePlan: 'pro'});
});

// ---------------------------------------------------------------------------
// entitlements.js over the fake Firestore
// ---------------------------------------------------------------------------

test('entitlements: assertPro, hostMayMontage, clipSecondsForUpload read the server fields', async () => {
  const db = makeFakeFirestore({
    'users/pro1': {plan: 'pro', planExpiresAt: new Date(NOW + DAY)},
    'users/free1': {plan: 'free'},
    // A client could never write this (rules), but even if a stale doc says
    // pro with a past expiry, the server reads free.
    'users/old1': {plan: 'pro', planExpiresAt: new Date(NOW - DAY)},
  });
  assert.equal(await assertPro(db, 'pro1', 'x', NOW), 'pro');
  await assert.rejects(assertPro(db, 'free1', 'customPacks', NOW), (e) => e.details.reason === 'plan-limit');
  await assert.rejects(assertPro(db, 'old1', 'customPacks', NOW), (e) => e.code === 'resource-exhausted');
  assert.equal(await hostMayMontage(db, {creatorId: 'pro1'}, NOW), true);
  assert.equal(await hostMayMontage(db, {creatorId: 'free1'}, NOW), false);
  assert.equal(await hostMayMontage(db, {creatorId: 'nobody'}, NOW), false);
  assert.equal(await hostMayMontage(db, null, NOW), false);
  assert.equal(await clipSecondsForUpload(db, {uid: 'pro1', day: '20261105'}, NOW), 60);
  assert.equal(await clipSecondsForUpload(db, {uid: 'pro1', day: 'guest'}, NOW), 20);
  assert.equal(await clipSecondsForUpload(db, {uid: 'free1', day: '20261105'}, NOW), 20);
});

// ---------------------------------------------------------------------------
// WP-09 watermark x WP-11 plans: a Pro host's friend-game montage is clean
// ---------------------------------------------------------------------------

test('watermark.isPro reads the server plan; a Pro host renders clean', async () => {
  const {isPro, watermarkFor, WATERMARK_TEXT} = require('../src/watermark');
  const db = makeFakeFirestore({
    'users/proHost': {plan: 'pro', planExpiresAt: new Date(NOW + DAY)},
    'users/freeHost': {plan: 'free'},
    'users/lapsedHost': {plan: 'pro', planExpiresAt: new Date(NOW - DAY)},
    'games/proGame': {creatorId: 'proHost'},
    'games/freeGame': {creatorId: 'freeHost'},
    'games/lapsedGame': {creatorId: 'lapsedHost'},
  });
  assert.equal(await isPro('proHost', {db, now: NOW}), true);
  assert.equal(await isPro('freeHost', {db, now: NOW}), false);
  assert.equal(await isPro('lapsedHost', {db, now: NOW}), false);
  assert.equal(await isPro('nobody', {db, now: NOW}), false);
  assert.equal(await isPro(null, {db}), false);
  const broken = {
    collection() {
      throw new Error('firestore down');
    },
  };
  assert.equal(await isPro('proHost', {db: broken}), false, 'any doubt: not Pro');

  const getGame = async (id) => (await db.collection('games').doc(id).get()).data() || null;
  const isProFn = (uid) => isPro(uid, {db, now: NOW});
  assert.equal(await watermarkFor({gameId: 'proGame', isStarter: false, getGame, isProFn}), null);
  assert.equal(await watermarkFor({gameId: 'freeGame', isStarter: false, getGame, isProFn}), WATERMARK_TEXT);
  assert.equal(await watermarkFor({gameId: 'lapsedGame', isStarter: false, getGame, isProFn}), WATERMARK_TEXT);
  assert.equal(await watermarkFor({gameId: 'proGame', isStarter: true, getGame, isProFn}), WATERMARK_TEXT,
    'Starter Pack montages are shared, so always branded');
});
