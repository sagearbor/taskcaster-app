'use strict';

/**
 * Seeds the Arena's "house" posts (four per Starter Pack task and two per
 * Daily Task, posted as userId 'house': `house-<taskId>` plus
 * `house-<taskId>-1..3`) with the Admin SDK, and optionally converts legacy
 * ISO-string `createdAt` values on feed_posts to Firestore Timestamps.
 *
 * Why a script: firestore.rules deny every client write to a house post (they
 * carry crowd counters that turn into points, so a client that could write
 * them could reset or vandalise them). The app's own seeding is a no-op on
 * Firestore; this is the only writer.
 *
 * The post data lives in house_posts.json next to this file. It is generated
 * from FeedRepositoryImpl.houseEntryPosts() in the Flutter app, and
 * test/features/arena/data/house_posts_seed_test.dart fails when it is stale.
 *
 * Usage (Application Default Credentials, e.g. `gcloud auth application-default login`):
 *   node scripts/seed_house_posts.js                      # dry run: print the plan
 *   node scripts/seed_house_posts.js --write              # seed / refresh house posts
 *   node scripts/seed_house_posts.js --fix-created-at     # dry run of the createdAt migration
 *   node scripts/seed_house_posts.js --fix-created-at --write
 *
 * Idempotent: a missing house post is created with its starting grade from
 * the JSON (gradeCount/gradeSum, default 0) and every other counter zeroed; an
 * existing one has only its seed fields refreshed (set/merge), never its
 * counters, graderIds or createdAt, so the grades it has collected survive.
 */

const path = require('path');
const fs = require('fs');

const PROJECT_ID = 'taskmaster-app-3d480';
const FEED_POSTS = 'feed_posts';

/** Fixed so the seeds sort last by recency and reseeding is byte-identical. */
const HOUSE_CREATED_AT = new Date('2026-01-01T00:00:00.000Z');

/** Fields the crowd (or the first seed) owns; a re-seed never touches them. */
const CROWD_FIELDS = [
  'gradeCount',
  'gradeSum',
  'graderIds',
  'tapCount',
  'tapSeconds',
  'lastTapSecond',
  'boosted',
  'createdAt',
];

function loadHousePosts(file = path.join(__dirname, 'house_posts.json')) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

/**
 * A new house post's starting crowd grade, from the JSON. Grades are 1-5, so
 * a sane pair has gradeSum between gradeCount and 5 * gradeCount; anything
 * else (or nothing) starts at zero.
 */
function startingGrade(post) {
  const count = post.gradeCount;
  const sum = post.gradeSum;
  if (Number.isInteger(count) && Number.isInteger(sum) && count > 0 &&
      sum >= count && sum <= 5 * count) {
    return {gradeCount: count, gradeSum: sum};
  }
  return {gradeCount: 0, gradeSum: 0};
}

/**
 * The writes to make, as plain data (no Firebase), so they are unit-testable.
 *
 * @param {Array<object>} posts house posts, each with an `id`
 * @param {Set<string>} existingIds ids already in feed_posts
 * @param {(d: Date) => any} toTimestamp converts the fixed createdAt
 * @returns {Array<{id: string, data: object, merge: boolean}>}
 */
function houseWrites(posts, existingIds, toTimestamp = (d) => d) {
  const writes = [];
  for (const post of posts) {
    const {id, ...rest} = post;
    if (typeof id !== 'string' || !id) continue;
    if (rest.userId !== 'house' || rest.isHouse !== true) {
      throw new Error(`house_posts.json entry ${id} is not a house post`);
    }
    const seed = {...rest};
    for (const key of CROWD_FIELDS) delete seed[key];

    if (existingIds.has(id)) {
      writes.push({id, data: seed, merge: true});
    } else {
      const start = startingGrade(rest);
      writes.push({
        id,
        merge: false,
        data: {
          ...seed,
          gradeCount: start.gradeCount,
          gradeSum: start.gradeSum,
          graderIds: [],
          tapCount: 0,
          tapSeconds: {},
          boosted: false,
          createdAt: toTimestamp(HOUSE_CREATED_AT),
        },
      });
    }
  }
  return writes;
}

/**
 * A legacy createdAt (ISO string) as a Date, or null when the value needs no
 * migration (already a Timestamp) or cannot be parsed.
 */
function legacyCreatedAt(value) {
  if (typeof value !== 'string') return null;
  const ms = Date.parse(value);
  return Number.isFinite(ms) ? new Date(ms) : null;
}

async function main(argv) {
  const write = argv.includes('--write');
  const fixCreatedAt = argv.includes('--fix-created-at');

  const admin = require('firebase-admin');
  if (!admin.apps.length) admin.initializeApp({projectId: PROJECT_ID});
  const db = admin.firestore();
  const {Timestamp} = admin.firestore;

  if (fixCreatedAt) {
    const snap = await db.collection(FEED_POSTS).get();
    const fixes = [];
    for (const doc of snap.docs) {
      const date = legacyCreatedAt(doc.get('createdAt'));
      if (date) fixes.push({ref: doc.ref, date});
    }
    console.log(`${fixes.length} of ${snap.size} posts have a string createdAt`);
    if (write) {
      for (let i = 0; i < fixes.length; i += 400) {
        const batch = db.batch();
        for (const {ref, date} of fixes.slice(i, i + 400)) {
          batch.update(ref, {createdAt: Timestamp.fromDate(date)});
        }
        await batch.commit();
      }
      console.log('createdAt migrated');
    }
    return;
  }

  const posts = loadHousePosts();
  const refs = posts.map((p) => db.collection(FEED_POSTS).doc(p.id));
  const snaps = refs.length ? await db.getAll(...refs) : [];
  const existing = new Set(snaps.filter((s) => s.exists).map((s) => s.id));
  const writes = houseWrites(posts, existing, (d) => Timestamp.fromDate(d));

  for (const w of writes) {
    console.log(`${w.merge ? 'refresh' : 'create '} ${w.id}`);
  }
  if (!write) {
    console.log('dry run; pass --write to apply');
    return;
  }
  const batch = db.batch();
  for (const w of writes) {
    const ref = db.collection(FEED_POSTS).doc(w.id);
    if (w.merge) batch.set(ref, w.data, {merge: true});
    else batch.set(ref, w.data);
  }
  await batch.commit();
  console.log(`wrote ${writes.length} house posts`);
}

if (require.main === module) {
  main(process.argv.slice(2)).catch((e) => {
    console.error(e);
    process.exit(1);
  });
}

module.exports = {
  houseWrites, startingGrade, legacyCreatedAt, loadHousePosts, CROWD_FIELDS, HOUSE_CREATED_AT,
};
