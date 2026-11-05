'use strict';

/**
 * Account deletion: when a Firebase Auth user is deleted (the in-app
 * "Delete account" button, or an admin delete in the console), remove
 * everything that account left behind. App Store 5.1.1(v) and Play's data
 * deletion policy both require that deleting the account deletes its data,
 * not just the profile doc the client can reach.
 *
 * The client deletes users/{uid} and friends itself before deleting the auth
 * user (it can only touch its own docs). Everything below needs the Admin SDK:
 *
 *   feed_posts where userId == uid     the post and its grades subcollection
 *   grades the user gave               feed_posts/{p}/grades/{uid}, found via
 *                                      graderIds array-contains uid; the uid
 *                                      is pulled from graderIds, but the
 *                                      anonymous gradeCount/gradeSum stay so
 *                                      other players' scores do not move
 *   push_subscriptions/{uid}           web push targets AND the iOS/Android
 *                                      FCM device tokens (fcmTokens, moved
 *                                      here from users/{uid} by WP-12)
 *   montage_quota/{uid}                the per-day render counters (and
 *                                      their days/ subcollection)
 *   Storage submissions/{uid}/         every clip the user uploaded; only the
 *                                      Admin SDK can do this, storage.rules
 *                                      deny client delete/list under
 *                                      submissions/
 *   Storage transcoded/{uid}/          poster frames of the user's clips (WP-08;
 *                                      the clips themselves are transcoded in
 *                                      place under submissions/{uid}/)
 *   clips where uid == uid             per-clip transcode metadata (WP-08)
 *   users/{uid}                        the whole subtree (private/, friends/)
 *   invites the user sent or received
 *   games                              the uid leaves players/playerIds and
 *                                      its task submissions; a game it created
 *                                      is deleted if it was the only player,
 *                                      otherwise handed to the next player
 *
 * Every step is idempotent, so a retried run is harmless.
 */

const functionsV1 = require('firebase-functions/v1');
const logger = require('firebase-functions/logger');

const REGION = 'us-central1';

const FEED_POSTS = 'feed_posts';
const GRADES = 'grades';
const PUSH_SUBSCRIPTIONS = 'push_subscriptions';
const USERS = 'users';
const GAMES = 'games';
const INVITES = 'invites';
const {MONTAGE_QUOTA} = require('./guards');

/** Storage prefix every player upload lives under (see storage.rules). */
const submissionsPrefix = (uid) => `submissions/${uid}/`;

/** Storage prefix of the poster frames WP-08's transcode writes per clip. */
const transcodedPrefix = (uid) => `transcoded/${uid}/`;

/** Per-clip transcode metadata (functions/src/transcode.js). */
const CLIPS = 'clips';

/** Firestore caps a batch at 500 writes. */
const BATCH_LIMIT = 450;

async function deleteInBatches(db, refs) {
  for (let i = 0; i < refs.length; i += BATCH_LIMIT) {
    const batch = db.batch();
    for (const ref of refs.slice(i, i + BATCH_LIMIT)) batch.delete(ref);
    // eslint-disable-next-line no-await-in-loop
    await batch.commit();
  }
}

/** The user's own posts, with their grades subcollections. */
async function deleteOwnPosts(db, uid) {
  const snap = await db.collection(FEED_POSTS).where('userId', '==', uid).get();
  await Promise.all(snap.docs.map((d) => db.recursiveDelete(d.ref)));
  return snap.size;
}

/** Grades this user gave on other people's posts. */
async function deleteGivenGrades(db, uid, FieldValue) {
  const snap = await db.collection(FEED_POSTS).where('graderIds', 'array-contains', uid).get();
  for (let i = 0; i < snap.docs.length; i += BATCH_LIMIT / 2) {
    const batch = db.batch();
    for (const post of snap.docs.slice(i, i + BATCH_LIMIT / 2)) {
      batch.delete(post.ref.collection(GRADES).doc(uid));
      batch.update(post.ref, {graderIds: FieldValue.arrayRemove(uid)});
    }
    // eslint-disable-next-line no-await-in-loop
    await batch.commit();
  }
  return snap.size;
}

async function deleteInvites(db, uid) {
  const [sent, received] = await Promise.all([
    db.collection(INVITES).where('inviterUid', '==', uid).get(),
    db.collection(INVITES).where('recipientUid', '==', uid).get(),
  ]);
  const refs = new Map();
  for (const d of [...sent.docs, ...received.docs]) refs.set(d.ref.path, d.ref);
  await deleteInBatches(db, [...refs.values()]);
  return refs.size;
}

/**
 * Pure: what should happen to one game document when [uid] leaves it.
 * Returns {action: 'none'} | {action: 'delete'} | {action: 'update', data}.
 */
function planGameDeparture(game, uid) {
  const players = Array.isArray(game.players) ? game.players : [];
  const playerIds = Array.isArray(game.playerIds) ? game.playerIds : [];
  const isMember = playerIds.includes(uid) || players.some((p) => p && p.userId === uid);
  const isCreator = game.creatorId === uid;
  const isJudge = game.judgeId === uid;
  if (!isMember && !isCreator && !isJudge) return {action: 'none'};

  const remainingPlayers = players.filter((p) => !p || p.userId !== uid);
  // playerIds is what the games rule and the home query read (WP-02). A
  // legacy game without it gets one derived from the remaining roster, so
  // the update never leaves players[] and playerIds disagreeing.
  const remainingIds = Array.isArray(game.playerIds) ?
    playerIds.filter((id) => id !== uid) :
    remainingPlayers.map((p) => p && p.userId).filter(Boolean);
  const others = remainingIds.length > 0 ?
    remainingIds :
    remainingPlayers.map((p) => p && p.userId).filter(Boolean);

  if (isCreator && others.length === 0) return {action: 'delete'};

  const data = {players: remainingPlayers, playerIds: remainingIds};
  if (Array.isArray(game.tasks)) {
    // Drop the user's submissions AND their per-task status, the same as the
    // app's leaveGame, so nobody's judging screen waits on a deleted player.
    data.tasks = game.tasks.map((t) => {
      if (!t || typeof t !== 'object') return t;
      const next = {...t};
      if (Array.isArray(t.submissions)) {
        next.submissions = t.submissions.filter((s) => !s || s.userId !== uid);
      }
      if (t.playerStatuses && typeof t.playerStatuses === 'object' &&
          Object.prototype.hasOwnProperty.call(t.playerStatuses, uid)) {
        const statuses = {...t.playerStatuses};
        delete statuses[uid];
        next.playerStatuses = statuses;
      }
      return next;
    });
  }
  if (isCreator) data.creatorId = others[0];
  if (isJudge) {
    // The judge seat goes to whoever now owns the game.
    const nextJudge = isCreator ? others[0] : (game.creatorId || others[0]);
    if (nextJudge) data.judgeId = nextJudge;
  }
  return {action: 'update', data};
}

async function leaveGames(db, uid) {
  const [asPlayer, asCreator] = await Promise.all([
    db.collection(GAMES).where('playerIds', 'array-contains', uid).get(),
    db.collection(GAMES).where('creatorId', '==', uid).get(),
  ]);
  const refs = new Map();
  for (const d of [...asPlayer.docs, ...asCreator.docs]) refs.set(d.ref.path, d.ref);

  let deleted = 0;
  let updated = 0;
  await Promise.all([...refs.values()].map((ref) => db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return;
    const plan = planGameDeparture(snap.data(), uid);
    if (plan.action === 'delete') {
      tx.delete(ref);
      deleted++;
    } else if (plan.action === 'update') {
      tx.update(ref, plan.data);
      updated++;
    }
  })));
  return {deleted, updated};
}

async function deleteStorageClips(bucket, uid) {
  if (!bucket) return;
  await bucket.deleteFiles({prefix: submissionsPrefix(uid), force: true});
  await bucket.deleteFiles({prefix: transcodedPrefix(uid), force: true});
}

async function deleteClipDocs(db, uid) {
  const snap = await db.collection(CLIPS).where('uid', '==', uid).get();
  await deleteInBatches(db, snap.docs.map((d) => d.ref));
  return snap.size;
}

/**
 * Remove everything [uid] owns. [db] is an Admin Firestore, [bucket] an Admin
 * Storage bucket (null skips Storage), [FieldValue] the Admin FieldValue.
 * Returns counts for the log line.
 */
async function deleteUserData(uid, {db, bucket, FieldValue}) {
  if (!uid || typeof uid !== 'string') throw new Error('deleteUserData: uid required');

  const posts = await deleteOwnPosts(db, uid);
  const gradesGiven = await deleteGivenGrades(db, uid, FieldValue);
  const games = await leaveGames(db, uid);
  const invites = await deleteInvites(db, uid);
  await db.recursiveDelete(db.collection(PUSH_SUBSCRIPTIONS).doc(uid));
  await db.recursiveDelete(db.collection(MONTAGE_QUOTA).doc(uid));
  await db.recursiveDelete(db.collection(USERS).doc(uid));
  await deleteStorageClips(bucket, uid);
  // After Storage: a transcode that finishes mid-deletion fails its
  // generation precondition, but its claim doc may still be written.
  const clips = await deleteClipDocs(db, uid);

  return {posts, gradesGiven, games, invites, clips};
}

/**
 * Auth onDelete trigger. v2 has no auth delete event (only blocking
 * beforeCreate/beforeSignIn), so this is the v1 trigger, pinned to the same
 * region as everything else. Admin handles are resolved lazily so this module
 * can be required without an initialised app (tests).
 */
const onAuthUserDeleted = functionsV1
  .region(REGION)
  .runWith({memory: '256MB', timeoutSeconds: 300, maxInstances: 5})
  .auth.user()
  .onDelete(async (user) => {
    const {getFirestore, FieldValue} = require('firebase-admin/firestore');
    const {getStorage} = require('firebase-admin/storage');
    const counts = await deleteUserData(user.uid, {
      db: getFirestore(),
      bucket: getStorage().bucket(),
      FieldValue,
    });
    logger.info('account deletion: user data removed', {uid: user.uid, ...counts});
  });

module.exports = {
  deleteUserData,
  planGameDeparture,
  submissionsPrefix,
  transcodedPrefix,
  onAuthUserDeleted,
};
