'use strict';

/**
 * One-off: give every game document a `playerIds` array (the flat list of
 * player uids) derived from `players[].userId`.
 *
 * Why: since WP-02 the home screen lists a user's games with a single query
 * (`playerIds` array-contains uid), and firestore.rules decide who is a
 * member from `playerIds`. Games created before the field existed have only
 * `players[]`, so they are missing from their players' home screens and
 * those players cannot submit. Every create/join path writes `playerIds`
 * today; this script fixes the old documents.
 *
 * Usage (Application Default Credentials, e.g. `gcloud auth application-default login`):
 *   node scripts/backfill_player_ids.js           # dry run: print the plan
 *   node scripts/backfill_player_ids.js --write   # apply it
 *
 * Idempotent: a game whose `playerIds` is already an array is left alone,
 * so re-running writes nothing.
 */

const PROJECT_ID = 'taskmaster-app-3d480';
const GAMES = 'games';

/**
 * Pure: the `playerIds` to write for one game document, or null when it
 * already has them (or has nothing to derive them from). Order follows
 * `players[]`; duplicates and malformed entries are dropped.
 */
function playerIdsFor(game) {
  if (!game || Array.isArray(game.playerIds)) return null;
  const players = Array.isArray(game.players) ? game.players : [];
  const ids = [];
  for (const p of players) {
    const id = p && typeof p.userId === 'string' ? p.userId : null;
    if (id && !ids.includes(id)) ids.push(id);
  }
  return ids;
}

/** Pure: [{id, playerIds}] for every document in [docs] ({id, data}) that needs one. */
function backfillPlan(docs) {
  const plan = [];
  for (const {id, data} of docs) {
    const playerIds = playerIdsFor(data);
    if (playerIds !== null) plan.push({id, playerIds});
  }
  return plan;
}

async function main(argv) {
  const write = argv.includes('--write');

  const admin = require('firebase-admin');
  if (!admin.apps.length) admin.initializeApp({projectId: PROJECT_ID});
  const db = admin.firestore();

  const snap = await db.collection(GAMES).get();
  const plan = backfillPlan(snap.docs.map((d) => ({id: d.id, data: d.data()})));

  for (const {id, playerIds} of plan) {
    console.log(`${id}: playerIds = [${playerIds.join(', ')}]`);
  }
  console.log(`${plan.length} of ${snap.size} games lack playerIds`);
  if (!write) {
    console.log('dry run; pass --write to apply');
    return;
  }
  for (let i = 0; i < plan.length; i += 400) {
    const batch = db.batch();
    for (const {id, playerIds} of plan.slice(i, i + 400)) {
      batch.update(db.collection(GAMES).doc(id), {playerIds});
    }
    await batch.commit();
  }
  console.log(`backfilled ${plan.length} games`);
}

if (require.main === module) {
  main(process.argv.slice(2)).catch((e) => {
    console.error(e);
    process.exit(1);
  });
}

module.exports = {playerIdsFor, backfillPlan};
