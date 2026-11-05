'use strict';

// Account deletion: the auth onDelete trigger must remove every trace of the
// deleted user (posts, grades given, clips, push subs, profile, game seats)
// in one run.
//
// The planGameDeparture tests are pure and always run. The end-to-end test
// seeds the Firestore + Storage emulators, fires the real trigger handler with
// a deleted-user record, and asserts the data is gone; it runs only when the
// emulators are up (`npm run test:emulator`), and is skipped by plain
// `npm test`.

const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const assert = require('node:assert/strict');

// v1 trigger metadata needs a project id; the emulators set one themselves.
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-taskcaster';

const {
  planGameDeparture, submissionsPrefix, transcodedPrefix, onAuthUserDeleted,
} = require('../src/account_deletion');

const player = (userId) => ({userId, displayName: userId, totalScore: 0});

test('index.js exports the auth onDelete trigger', () => {
  const src = fs.readFileSync(path.join(__dirname, '..', 'src', 'index.js'), 'utf8');
  assert.match(src, /exports\.deleteUserData\s*=\s*require\('\.\/account_deletion'\)\.onAuthUserDeleted/);
  const endpoint = onAuthUserDeleted.__endpoint;
  assert.equal(endpoint.eventTrigger.eventType, 'providers/firebase.auth/eventTypes/user.delete');
  assert.deepEqual(endpoint.region, ['us-central1']);
});

test('clips are deleted from the uploader\'s own Storage folder only', () => {
  assert.equal(submissionsPrefix('u1'), 'submissions/u1/');
});

test('WP-08 posters are deleted from the user\'s transcoded/ folder, matching transcode.js', () => {
  const {posterObjectPath} = require('../src/transcode');
  assert.equal(transcodedPrefix('u1'), 'transcoded/u1/');
  assert.ok(posterObjectPath({uid: 'u1', day: '20261105', slot: '0'}).startsWith(transcodedPrefix('u1')));
});

test('a game the user is not in is left alone', () => {
  const game = {creatorId: 'a', judgeId: 'a', playerIds: ['a', 'b'], players: [player('a'), player('b')]};
  assert.deepEqual(planGameDeparture(game, 'z'), {action: 'none'});
});

test('a game the user created alone is deleted', () => {
  const game = {creatorId: 'u', judgeId: 'u', playerIds: ['u'], players: [player('u')]};
  assert.deepEqual(planGameDeparture(game, 'u'), {action: 'delete'});
});

test('a game the user created with others is handed to the next player', () => {
  const game = {
    creatorId: 'u', judgeId: 'u',
    playerIds: ['u', 'b', 'c'], players: [player('u'), player('b'), player('c')],
    tasks: [{title: 't', submissions: [{userId: 'u', videoUrl: 'x'}, {userId: 'b', videoUrl: 'y'}]}],
  };
  const plan = planGameDeparture(game, 'u');
  assert.equal(plan.action, 'update');
  assert.equal(plan.data.creatorId, 'b');
  assert.equal(plan.data.judgeId, 'b');
  assert.deepEqual(plan.data.playerIds, ['b', 'c']);
  assert.deepEqual(plan.data.players.map((p) => p.userId), ['b', 'c']);
  assert.deepEqual(plan.data.tasks[0].submissions, [{userId: 'b', videoUrl: 'y'}]);
});

test('a plain member just leaves; ownership is untouched', () => {
  const game = {creatorId: 'a', judgeId: 'a', playerIds: ['a', 'u'], players: [player('a'), player('u')]};
  const plan = planGameDeparture(game, 'u');
  assert.equal(plan.action, 'update');
  assert.equal(plan.data.creatorId, undefined);
  assert.equal(plan.data.judgeId, undefined);
  assert.deepEqual(plan.data.playerIds, ['a']);
});

test('a member who was judge hands the judge seat back to the creator', () => {
  const game = {creatorId: 'a', judgeId: 'u', playerIds: ['a', 'u'], players: [player('a'), player('u')]};
  assert.equal(planGameDeparture(game, 'u').data.judgeId, 'a');
});

test('the leaver\'s per-task status goes too (WP-02 leaveGame parity)', () => {
  const game = {
    creatorId: 'a', judgeId: 'a', playerIds: ['a', 'u'], players: [player('a'), player('u')],
    tasks: [{
      title: 't',
      submissions: [],
      playerStatuses: {a: {playerId: 'a', state: 'submitted'}, u: {playerId: 'u', state: 'not_started'}},
    }],
  };
  const plan = planGameDeparture(game, 'u');
  assert.deepEqual(Object.keys(plan.data.tasks[0].playerStatuses), ['a']);
});

test('a group-graded game (WP-13) has no judge, and the departure does not mint one', () => {
  const game = {
    creatorId: 'u', judgeId: '', settings: {judgingMode: 'group'},
    playerIds: ['u', 'b', 'c'], players: [player('u'), player('b'), player('c')],
  };
  const plan = planGameDeparture(game, 'u');
  assert.equal(plan.data.creatorId, 'b');
  assert.equal(plan.data.judgeId, undefined);
});

test('a legacy game without playerIds gets them from the remaining roster', () => {
  const game = {creatorId: 'a', judgeId: 'a', players: [player('a'), player('u'), player('b')]};
  const plan = planGameDeparture(game, 'u');
  assert.deepEqual(plan.data.playerIds, ['a', 'b']);
});

// ---------------------------------------------------------------------------
// Emulator: seed, fire the trigger, assert.
// ---------------------------------------------------------------------------

const EMULATED = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
const PROJECT = process.env.GCLOUD_PROJECT;
const BUCKET = `${PROJECT}.appspot.com`;

test('deleting an account removes its data in one trigger run (emulator)', {skip: !EMULATED && 'emulators not running; use npm run test:emulator'}, async () => {
  const {initializeApp, getApps} = require('firebase-admin/app');
  const {getFirestore} = require('firebase-admin/firestore');
  const {getStorage} = require('firebase-admin/storage');
  if (!getApps().length) initializeApp({projectId: PROJECT, storageBucket: BUCKET});
  const db = getFirestore();
  const storageEmulated = Boolean(process.env.FIREBASE_STORAGE_EMULATOR_HOST);
  const bucket = storageEmulated ? getStorage().bucket(BUCKET) : null;

  const uid = 'doomed';
  // Their post (with a grade from someone else), and a post they graded.
  await db.doc('feed_posts/mine').set({userId: uid, mediaType: 'video', videoStoragePath: `submissions/${uid}/20261105/0`, graderIds: ['other']});
  await db.doc('feed_posts/mine/grades/other').set({score: 4});
  await db.doc('feed_posts/theirs').set({userId: 'other', gradeCount: 1, gradeSum: 5, graderIds: [uid]});
  await db.doc(`feed_posts/theirs/grades/${uid}`).set({score: 5});
  await db.doc(`push_subscriptions/${uid}`).set({
    subs: {k: {endpoint: 'https://x'}},
    fcmTokens: {'device-token-1': new Date().toISOString()},
  });
  await db.doc(`montage_quota/${uid}/days/20261105`).set({count: 3});
  await db.doc(`users/${uid}`).set({displayName: 'Doomed'});
  await db.doc(`users/${uid}/private/profile`).set({email: 'd@example.com'});
  await db.doc(`users/${uid}/friends/other`).set({uid: 'other'});
  await db.doc('invites/i1').set({inviterUid: uid, recipientUid: 'other'});
  await db.doc('games/solo').set({creatorId: uid, judgeId: uid, playerIds: [uid], players: [player(uid)]});
  await db.doc('games/shared').set({creatorId: uid, judgeId: uid, playerIds: [uid, 'other'], players: [player(uid), player('other')]});
  await db.doc('games/joined').set({creatorId: 'other', judgeId: 'other', playerIds: ['other', uid], players: [player('other'), player(uid)]});
  // WP-13 friend-game grades: given, received, the user's locked score, and a
  // bystander's grade and score that must survive.
  await db.doc(`games/joined/peer_grades/t1__other__${uid}`).set({taskId: 't1', targetUid: 'other', graderUid: uid, score: 4});
  await db.doc(`games/joined/peer_grades/t1__${uid}__other`).set({taskId: 't1', targetUid: uid, graderUid: 'other', score: 3});
  await db.doc(`games/joined/peer_results/t1__${uid}`).set({taskId: 't1', uid, points: 6});
  await db.doc('games/joined/peer_results/t1__other').set({taskId: 't1', uid: 'other', points: 8});
  await db.doc('games/elsewhere/peer_grades/t1__x__other').set({taskId: 't1', targetUid: 'x', graderUid: 'other', score: 5});
  // Someone else's data must survive.
  await db.doc('feed_posts/bystander').set({userId: 'other', graderIds: []});
  await db.doc(`clips/${uid}_20261105_0`).set({uid, status: 'ready'});
  await db.doc('clips/other_20261105_0').set({uid: 'other', status: 'ready'});
  if (bucket) {
    await bucket.file(`submissions/${uid}/20261105/0`).save(Buffer.from('clip'), {contentType: 'video/mp4'});
    await bucket.file('submissions/other/20261105/0').save(Buffer.from('clip'), {contentType: 'video/mp4'});
    await bucket.file(`transcoded/${uid}/20261105/0.jpg`).save(Buffer.from('jpg'), {contentType: 'image/jpeg'});
    await bucket.file('transcoded/other/20261105/0.jpg').save(Buffer.from('jpg'), {contentType: 'image/jpeg'});
  }

  // Fire the deployed trigger's handler exactly as Auth would.
  await onAuthUserDeleted.run({uid}, {eventId: 'e1', timestamp: new Date().toISOString(), params: {}});

  const exists = async (p) => (await db.doc(p).get()).exists;
  assert.equal(await exists('feed_posts/mine'), false, 'own post deleted');
  assert.equal(await exists('feed_posts/mine/grades/other'), false, 'grades on own post deleted');
  assert.equal(await exists(`feed_posts/theirs/grades/${uid}`), false, 'grade given deleted');
  const theirs = (await db.doc('feed_posts/theirs').get()).data();
  assert.deepEqual(theirs.graderIds, [], 'uid pulled from graderIds');
  assert.equal(theirs.gradeSum, 5, 'other player\'s score unchanged');
  assert.equal(await exists(`push_subscriptions/${uid}`), false);
  assert.equal(await exists(`montage_quota/${uid}/days/20261105`), false, 'quota counters deleted');
  assert.equal(await exists(`users/${uid}`), false);
  assert.equal(await exists(`users/${uid}/private/profile`), false);
  assert.equal(await exists(`users/${uid}/friends/other`), false);
  assert.equal(await exists('invites/i1'), false);
  assert.equal(await exists('games/solo'), false, 'solo game deleted');
  const shared = (await db.doc('games/shared').get()).data();
  assert.equal(shared.creatorId, 'other');
  assert.deepEqual(shared.playerIds, ['other']);
  const joined = (await db.doc('games/joined').get()).data();
  assert.equal(joined.creatorId, 'other');
  assert.deepEqual(joined.playerIds, ['other']);
  assert.equal(await exists('feed_posts/bystander'), true, 'bystander untouched');
  assert.equal(await exists(`games/joined/peer_grades/t1__other__${uid}`), false, 'peer grade given deleted');
  assert.equal(await exists(`games/joined/peer_grades/t1__${uid}__other`), false, 'peer grade received deleted');
  assert.equal(await exists(`games/joined/peer_results/t1__${uid}`), false, 'locked peer score deleted');
  assert.equal(await exists('games/joined/peer_results/t1__other'), true, 'other player\'s locked score untouched');
  assert.equal(await exists('games/elsewhere/peer_grades/t1__x__other'), true, 'unrelated peer grade untouched');
  assert.equal(await exists(`clips/${uid}_20261105_0`), false, 'clip metadata deleted');
  assert.equal(await exists('clips/other_20261105_0'), true, 'other player\'s clip metadata untouched');

  if (bucket) {
    const [mine] = await bucket.getFiles({prefix: submissionsPrefix(uid)});
    assert.equal(mine.length, 0, 'clips deleted');
    const [others] = await bucket.getFiles({prefix: submissionsPrefix('other')});
    assert.equal(others.length, 1, 'other player\'s clip untouched');
    const [posters] = await bucket.getFiles({prefix: transcodedPrefix(uid)});
    assert.equal(posters.length, 0, 'posters deleted');
    const [otherPosters] = await bucket.getFiles({prefix: transcodedPrefix('other')});
    assert.equal(otherPosters.length, 1, 'other player\'s poster untouched');
  }

  // A retry (Functions may redeliver) is a harmless no-op.
  await onAuthUserDeleted.run({uid}, {eventId: 'e1', timestamp: new Date().toISOString(), params: {}});
});
