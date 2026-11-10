'use strict';

/**
 * Find (and reversibly hide) Arena posts made by automated test walks.
 *
 * Why: agents walk the production web app with headless Chromium. Before the
 * e2e guard (lib/core/config/e2e_mode.dart, `?e2e=1`) every walk posted
 * Chrome fake-camera color bars and generated JPEGs to the public Arena as
 * "Guest", and the finale montage spliced them in (fun audit 2026-11-09,
 * WP-1). This script cleans that up WITHOUT deleting anything.
 *
 * NOTHING HERE DELETES. "Hide" sets `shareable: false` (+ `hiddenReason:
 * 'test-walk'`), which is exactly what a private post looks like:
 *   - the app's Arena queue skips it (FeedRepositoryImpl.watchQueue);
 *   - firestore.rules refuse it to strangers reading by id;
 *   - the public /p/ and /t/ share pages 404 (share_page.js isShareablePost;
 *     a finale with one private clip is private as a whole);
 *   - the montage renderer leaves it out of the next render
 *     (contract.js isMontageablePost) — from the functions deploy that
 *     carries that check onwards.
 * `--unhide` puts every field back as it was.
 *
 * MODES (Application Default Credentials: `gcloud auth application-default login`)
 *
 *   node scripts/purge_test_posts.js [--uids a,b] [--out ids.txt] [--dump-photos dir]
 *       DRY RUN (default, read-only). Lists candidates: non-house posts whose
 *       userId is in --uids (default: the 2026-11-09 audit walk), or whose
 *       displayName is 'Guest'. Prints posterUrl / video URL so a human can
 *       open them and confirm a test pattern. --out writes the ids, one per
 *       line with the reason as a comment: delete the lines of real players
 *       before hiding. --dump-photos writes inline photo posts as .jpg files.
 *
 *   node scripts/purge_test_posts.js --hide --ids ids.txt [--write]
 *   node scripts/purge_test_posts.js --unhide --ids ids.txt [--write]
 *       Print the plan; with --write, apply it. House posts are refused.
 *       --unhide only touches posts this script hid.
 *
 *   node scripts/purge_test_posts.js --mark-stale --ids ids.txt [--write]
 *       Re-queue the finale montages that contain (or, after an unhide, could
 *       contain) those posts, so the every-10-minutes settle pass re-renders
 *       them from the posts that are still eligible. A montage left with no
 *       eligible clip has its URLs parked in staleFinaleUrl/staleMomentsUrl
 *       (the Storage objects stay) so the app stops showing it; --unhide
 *       --mark-stale puts them back. RUN THIS ONLY AFTER the functions deploy
 *       that excludes `shareable == false` from montages, or the re-render
 *       splices the hidden clips straight back in.
 *
 * Everything that decides anything is a pure function, unit-tested in
 * test/purge_test_posts.test.js; main() is just Firestore plumbing.
 */

const fs = require('fs');
const path = require('path');

const {montageDocId, isMontageablePost, RENDER_AT_CLIP_COUNT} = require('../src/contract');

const PROJECT_ID = 'taskmaster-app-3d480';
const FEED_POSTS = 'feed_posts';
const MONTAGES = 'montages';

/** The guest uid of the 2026-11-09 fun-audit walk (10 junk posts). */
const DEFAULT_UIDS = ['xUsHQrBtTwdCETXLdmaZgsgaLcp2'];

const HIDDEN_REASON = 'test-walk';

/** Firestore `in` takes at most 30 values. */
const MAX_IN = 30;

/** Marks "delete this field" in a pure plan; main() maps it to FieldValue.delete(). */
const DELETE = Symbol('delete-field');

const isHousePost = (post) => !post || post.isHouse === true || post.userId === 'house';

/**
 * Which posts look like test-walk junk, and why.
 *
 * @param {Array<object>} posts feed_posts documents (with `id`)
 * @param {{uids?: Iterable<string>}} opts
 * @returns {Array<object>} one row per candidate, oldest first
 */
function selectCandidates(posts, {uids = DEFAULT_UIDS} = {}) {
  const uidSet = new Set(uids);
  const seen = new Set();
  const rows = [];
  for (const post of posts || []) {
    if (!post || typeof post.id !== 'string' || seen.has(post.id)) continue;
    seen.add(post.id);
    if (isHousePost(post)) continue;
    const reasons = [];
    if (uidSet.has(post.userId)) reasons.push('uid');
    if (post.displayName === 'Guest') reasons.push('guest-name');
    if (!reasons.length) continue;
    rows.push({
      id: post.id,
      reasons,
      userId: post.userId || '',
      displayName: post.displayName || '',
      mediaType: post.mediaType || '',
      gameId: post.gameId || '',
      taskId: post.taskId || '',
      createdAt: isoOf(post.createdAt),
      posterUrl: post.posterUrl || null,
      videoUrl: post.playbackUrl || post.videoUrl || null,
      text: typeof post.text === 'string' ? post.text.slice(0, 80) : null,
      hasPhoto: typeof post.photoData === 'string' && post.photoData.length > 0,
      hidden: post.hiddenReason === HIDDEN_REASON,
      shareable: post.shareable === undefined ? null : post.shareable,
    });
  }
  return rows.sort((a, b) => a.createdAt.localeCompare(b.createdAt));
}

function isoOf(value) {
  if (!value) return '';
  if (typeof value === 'string') return value;
  if (value instanceof Date) return value.toISOString();
  if (typeof value.toDate === 'function') return value.toDate().toISOString();
  if (typeof value.seconds === 'number') return new Date(value.seconds * 1000).toISOString();
  return '';
}

/** A human-reviewable line for the dry run. */
function formatCandidate(row) {
  const what = row.mediaType === 'video'
    ? `video poster=${row.posterUrl || '-'} clip=${row.videoUrl || '-'}`
    : row.mediaType === 'photo'
      ? `photo ${row.hasPhoto ? '(inline; --dump-photos to view)' : row.videoUrl || '(no data)'}`
      : `${row.mediaType || '?'} ${row.text ? JSON.stringify(row.text) : row.videoUrl || ''}`;
  const state = row.hidden ? ' [already hidden]' : row.shareable === false ? ' [private]' : '';
  return `${row.id}  ${row.createdAt}  [${row.reasons.join('+')}]  uid=${row.userId} ` +
    `name=${row.displayName} task=${row.taskId}${state}\n    ${what}`;
}

/** The --out file: ids with their reason, so a reviewer can delete lines. */
function idsFileText(rows) {
  const header = [
    '# purge_test_posts.js candidates. One post id per line; text after # is ignored.',
    '# DELETE the lines of real players before running --hide.',
  ];
  return header.concat(rows.map((r) =>
    `${r.id}  # ${r.reasons.join('+')} ${r.mediaType} ${r.taskId} ${r.displayName}` +
    `${r.posterUrl ? ` ${r.posterUrl}` : ''}`)).join('\n') + '\n';
}

/** Ids from an ids file: one per line, `#` comments and blank lines ignored. */
function parseIdsFile(text) {
  const ids = [];
  for (const line of String(text).split(/\r?\n/)) {
    const id = line.replace(/#.*$/, '').trim().split(/\s+/)[0];
    if (id && !ids.includes(id)) ids.push(id);
  }
  return ids;
}

/**
 * The update that hides one post, or a reason it is skipped.
 * Records the previous `shareable` so --unhide restores it exactly.
 */
function hideUpdate(post, nowIso) {
  if (!post) return {skip: 'missing'};
  if (isHousePost(post)) return {skip: 'house'};
  if (post.hiddenReason === HIDDEN_REASON) return {skip: 'already-hidden'};
  return {
    update: {
      shareable: false,
      hiddenReason: HIDDEN_REASON,
      hiddenAt: nowIso,
      hiddenPrevShareable: typeof post.shareable === 'boolean' ? post.shareable : null,
    },
  };
}

/** The update that undoes [hideUpdate], or a reason it is skipped. */
function unhideUpdate(post) {
  if (!post) return {skip: 'missing'};
  if (post.hiddenReason !== HIDDEN_REASON) return {skip: 'not-hidden-by-this-script'};
  const prev = post.hiddenPrevShareable;
  return {
    update: {
      shareable: typeof prev === 'boolean' ? prev : DELETE,
      hiddenReason: DELETE,
      hiddenAt: DELETE,
      hiddenPrevShareable: DELETE,
    },
  };
}

/**
 * The montage docs a set of posts can appear in (video posts only — nothing
 * else is ever spliced).
 *
 * @returns {Map<string, {gameId: string, taskId: string}>} docId -> scope
 */
function affectedMontages(posts) {
  const out = new Map();
  for (const post of posts || []) {
    if (!post || post.mediaType !== 'video' || !post.taskId) continue;
    out.set(montageDocId(post.gameId, post.taskId), {gameId: post.gameId, taskId: post.taskId});
  }
  return out;
}

/**
 * How many clips a re-render of this montage would splice, given every post
 * in its scope as it is NOW (after hiding/unhiding).
 */
function eligibleClipCount(scopePosts, taskId) {
  return (scopePosts || []).filter((p) => isMontageablePost(p, taskId)).length;
}

/**
 * The montage update that makes the settle pass re-render it.
 *
 * Non-destructive: Storage objects are never touched. With clips left it is
 * queued (`pending` at the render threshold, unlocked) and the next settle
 * pass rebuilds it from the eligible posts. With none left, a render would
 * only mark it failed and leave the old finaleUrl showing, so its URLs are
 * parked in stale* fields instead and the app's finale card disappears
 * (Montage.isReady needs a finaleUrl). A later run with clips back restores
 * parked URLs first, then queues the re-render.
 *
 * @param {object|null} montage current doc data
 * @param {number} eligible clips a re-render would use
 * @param {string} nowIso
 * @returns {{skip?: string, update?: object}}
 */
function staleMontageUpdate(montage, eligible, nowIso) {
  if (!montage) return {skip: 'no-montage'};
  if (eligible <= 0) {
    if (!montage.finaleUrl && !montage.momentsUrl) return {skip: 'nothing-to-park'};
    return {
      update: {
        staleFinaleUrl: montage.finaleUrl || null,
        staleMomentsUrl: montage.momentsUrl || null,
        finaleUrl: DELETE,
        momentsUrl: DELETE,
        status: 'failed',
        error: `every clip hidden (${HIDDEN_REASON})`,
        staleReason: HIDDEN_REASON,
        lockedAt: null,
        updatedAt: nowIso,
      },
    };
  }
  const update = {
    status: 'pending',
    pendingCount: Math.max(RENDER_AT_CLIP_COUNT, Number(montage.pendingCount) || 0),
    pendingSince: nowIso,
    lockedAt: null,
    staleReason: HIDDEN_REASON,
    updatedAt: nowIso,
  };
  if (!montage.finaleUrl && montage.staleFinaleUrl) {
    update.finaleUrl = montage.staleFinaleUrl;
    update.momentsUrl = montage.staleMomentsUrl || null;
    update.staleFinaleUrl = DELETE;
    update.staleMomentsUrl = DELETE;
  }
  return {update};
}

/** Replace DELETE markers with the Admin SDK's FieldValue.delete(). */
function toFirestore(update, FieldValue) {
  const out = {};
  for (const [k, v] of Object.entries(update)) out[k] = v === DELETE ? FieldValue.delete() : v;
  return out;
}

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

function parseArgs(argv) {
  const args = {
    hide: false, unhide: false, markStale: false, write: false,
    uids: DEFAULT_UIDS, ids: null, out: null, dumpPhotos: null,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    const val = () => {
      const v = argv[i + 1];
      if (v === undefined || v.startsWith('--')) throw new Error(`${a} needs a value`);
      i += 1;
      return v;
    };
    if (a === '--hide') args.hide = true;
    else if (a === '--unhide') args.unhide = true;
    else if (a === '--mark-stale') args.markStale = true;
    else if (a === '--write') args.write = true;
    else if (a === '--uids') args.uids = val().split(',').map((s) => s.trim()).filter(Boolean);
    else if (a === '--ids') args.ids = val();
    else if (a === '--out') args.out = val();
    else if (a === '--dump-photos') args.dumpPhotos = val();
    else if (a === '--delete') throw new Error('There is no delete mode. Use --hide (reversible).');
    else throw new Error(`Unknown argument ${a}`);
  }
  if (args.hide && args.unhide) throw new Error('Pick one of --hide / --unhide.');
  if ((args.hide || args.unhide || args.markStale) && !args.ids) {
    throw new Error('--hide / --unhide / --mark-stale need --ids <file>.');
  }
  if (args.write && !(args.hide || args.unhide || args.markStale)) {
    throw new Error('--write only applies to --hide / --unhide / --mark-stale.');
  }
  return args;
}

async function dryRun(db, args) {
  const byId = new Map();
  const add = (snap) => snap.docs.forEach((d) => byId.set(d.id, {id: d.id, ...d.data()}));
  for (let i = 0; i < args.uids.length; i += MAX_IN) {
    add(await db.collection(FEED_POSTS).where('userId', 'in', args.uids.slice(i, i + MAX_IN)).get());
  }
  add(await db.collection(FEED_POSTS).where('displayName', '==', 'Guest').get());

  const rows = selectCandidates([...byId.values()], {uids: args.uids});
  for (const row of rows) console.log(formatCandidate(row));
  const byUid = rows.filter((r) => r.reasons.includes('uid')).length;
  console.log(`\n${rows.length} candidates (${byUid} by uid, ${rows.length - byUid} by name only). ` +
    'Read-only: nothing was changed.');

  if (args.dumpPhotos) {
    fs.mkdirSync(args.dumpPhotos, {recursive: true});
    let n = 0;
    for (const row of rows) {
      const data = byId.get(row.id).photoData;
      if (typeof data !== 'string' || !data) continue;
      fs.writeFileSync(path.join(args.dumpPhotos, `${row.id}.jpg`), Buffer.from(data, 'base64'));
      n += 1;
    }
    console.log(`wrote ${n} inline photos to ${args.dumpPhotos}`);
  }
  if (args.out) {
    fs.writeFileSync(args.out, idsFileText(rows));
    console.log(`wrote ${rows.length} ids to ${args.out} — prune real players, then --hide`);
  }
}

async function readPosts(db, ids) {
  const refs = ids.map((id) => db.collection(FEED_POSTS).doc(id));
  const snaps = refs.length ? await db.getAll(...refs) : [];
  return snaps.map((s) => (s.exists ? {id: s.id, ...s.data()} : {id: s.id, missing: true}));
}

async function hideOrUnhide(db, args, ids, FieldValue) {
  const posts = await readPosts(db, ids);
  const now = new Date().toISOString();
  const plan = [];
  for (const post of posts) {
    const result = post.missing ? {skip: 'missing'}
      : args.hide ? hideUpdate(post, now) : unhideUpdate(post);
    console.log(`${result.update ? (args.hide ? 'hide  ' : 'unhide') : 'skip  '} ${post.id}` +
      `${result.skip ? ` (${result.skip})` : ''}`);
    if (result.update) plan.push({id: post.id, update: result.update});
  }
  if (!args.write) {
    console.log(`dry run: ${plan.length} posts would change; add --write to apply`);
    return;
  }
  for (let i = 0; i < plan.length; i += 400) {
    const batch = db.batch();
    for (const {id, update} of plan.slice(i, i + 400)) {
      batch.update(db.collection(FEED_POSTS).doc(id), toFirestore(update, FieldValue));
    }
    await batch.commit();
  }
  console.log(`${args.hide ? 'hid' : 'unhid'} ${plan.length} posts`);
}

async function markStale(db, args, ids, FieldValue) {
  const posts = (await readPosts(db, ids)).filter((p) => !p.missing);
  const montages = affectedMontages(posts);
  const now = new Date().toISOString();
  console.log('Re-queuing montages. This only helps once the functions deploy that ' +
    'excludes shareable==false from montages is live.');
  let changed = 0;
  for (const [docId, {gameId, taskId}] of montages) {
    const snap = await db.collection(MONTAGES).doc(docId).get();
    const scope = docId.startsWith('starter_')
      ? await db.collection(FEED_POSTS).where('taskId', '==', taskId).get()
      : await db.collection(FEED_POSTS).where('gameId', '==', gameId).get();
    const eligible = eligibleClipCount(scope.docs.map((d) => ({id: d.id, ...d.data()})), taskId);
    const result = staleMontageUpdate(snap.exists ? snap.data() : null, eligible, now);
    console.log(`${docId}: ${eligible} eligible clips -> ` +
      `${result.skip ? `skip (${result.skip})` : result.update.status === 'pending' ? 're-render queued' : 'finale parked'}`);
    if (!result.update) continue;
    changed += 1;
    if (args.write) {
      await db.collection(MONTAGES).doc(docId).set(toFirestore(result.update, FieldValue), {merge: true});
    }
  }
  console.log(args.write ? `updated ${changed} montages; the settle pass renders within ~10 min`
    : `dry run: ${changed} montages would change; add --write to apply`);
}

async function main(argv) {
  const args = parseArgs(argv);
  const admin = require('firebase-admin');
  if (!admin.apps.length) admin.initializeApp({projectId: PROJECT_ID});
  const db = admin.firestore();
  const {FieldValue} = admin.firestore;

  if (!args.ids) return dryRun(db, args);

  const ids = parseIdsFile(fs.readFileSync(args.ids, 'utf8'));
  console.log(`${ids.length} ids from ${args.ids}`);
  if (args.hide || args.unhide) await hideOrUnhide(db, args, ids, FieldValue);
  if (args.markStale) await markStale(db, args, ids, FieldValue);
}

if (require.main === module) {
  main(process.argv.slice(2)).catch((e) => {
    console.error(e.message || e);
    process.exit(1);
  });
}

module.exports = {
  DEFAULT_UIDS,
  HIDDEN_REASON,
  DELETE,
  selectCandidates,
  formatCandidate,
  idsFileText,
  parseIdsFile,
  hideUpdate,
  unhideUpdate,
  affectedMontages,
  eligibleClipCount,
  staleMontageUpdate,
  toFirestore,
  parseArgs,
};
