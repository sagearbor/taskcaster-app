'use strict';

/**
 * WP-09 share pages: shareable vs private, 404s that leak nothing, the OG /
 * Twitter tags link previews need, and no PII anywhere in the HTML.
 */

const fs = require('fs');
const path = require('path');
const test = require('node:test');
const assert = require('node:assert/strict');

const {
  parseSharePath,
  isShareablePost,
  firstName,
  handleShareRequest,
  yourTurnUrl,
  httpHandler,
  CACHE_OK,
} = require('../src/share_page');
const {STARTER_TASKS, RETIRED_STARTER_TASKS, starterTask} = require('../src/starter_tasks');
const {STARTER_TASK_IDS} = require('../src/contract');
const {watermarkFor, WATERMARK_TEXT} = require('../src/watermark');
const {watermarkFilter} = require('../src/montage');

const SECRET_UID = 'uidSECRETabc123';
const SECRET_GAME = 'gameSECRETxyz789';
const SECRET_EMAIL = 'sage@example.com';

function starterPost(overrides = {}) {
  return {
    userId: SECRET_UID,
    gameId: SECRET_GAME,
    taskId: 'starter-09-v2',
    taskTitle: 'The face of someone who has just remembered the oven is on',
    displayName: 'Sage Arbor',
    email: SECRET_EMAIL,
    mediaType: 'video',
    videoUrl: 'https://firebasestorage.googleapis.com/v0/b/b/o/submissions%2Fx?alt=media&token=t',
    videoStoragePath: `submissions/${SECRET_UID}/20261105/0`,
    playbackUrl: 'https://firebasestorage.googleapis.com/v0/b/b/o/submissions%2Fx?alt=media&token=t2',
    posterUrl: 'https://firebasestorage.googleapis.com/v0/b/b/o/transcoded%2Fx.jpg?alt=media',
    stamp: 'NO REGRETS',
    elapsedSeconds: 8,
    caption: 'No hands. One word.',
    graderIds: ['graderSECRET1'],
    tapCount: 0,
    ...overrides,
  };
}

function friendPost(overrides = {}) {
  return starterPost({taskId: 'task-in-a-friend-game', taskTitle: 'Private inside joke', ...overrides});
}

function storeOf(posts = {}, montages = {}) {
  const reads = [];
  return {
    reads,
    async getPost(id) {
      reads.push(`feed_posts/${id}`);
      return posts[id] || null;
    },
    async getMontage(id) {
      reads.push(`montages/${id}`);
      return montages[id] || null;
    },
  };
}

const get = (p, store, query) => handleShareRequest({path: p, query, store});

function assertNoPii(body) {
  const text = String(body);
  for (const secret of [SECRET_UID, SECRET_GAME, SECRET_EMAIL, 'Arbor', 'graderSECRET1', 'submissions/']) {
    assert.ok(!text.includes(secret), `page leaks ${secret}`);
  }
}

const meta = (body, key) => {
  const m = String(body).match(new RegExp(`<meta (?:property|name)="${key}" content="([^"]*)"`));
  return m ? m[1] : null;
};

// ---- routing ----

test('parseSharePath: known routes, ids validated, junk rejected', () => {
  assert.deepEqual(parseSharePath('/p/abc'), {kind: 'post', id: 'abc'});
  assert.deepEqual(parseSharePath('/c/abc'), {kind: 'challenge', id: 'abc'});
  assert.deepEqual(parseSharePath('/t/starter-09'), {kind: 'task', id: 'starter-09'});
  assert.deepEqual(parseSharePath('/f/starter_starter-01-v2'), {kind: 'finale', id: 'starter_starter-01-v2'});
  assert.deepEqual(parseSharePath('/p/abc/image.jpg'), {kind: 'postImage', id: 'abc'});
  assert.equal(parseSharePath('/x/abc'), null);
  assert.equal(parseSharePath('/p/'), null);
  assert.equal(parseSharePath('/p/a.b'), null);
  assert.equal(parseSharePath('/p/abc/other'), null);
  assert.equal(parseSharePath('/p/<script>'), null);
});

// ---- privacy rule ----

test('isShareablePost: explicit flag wins; starter + house public by default; friend games private', () => {
  assert.equal(isShareablePost(starterPost()), true);
  assert.equal(isShareablePost(starterPost({shareable: false})), false);
  assert.equal(isShareablePost(friendPost()), false);
  assert.equal(isShareablePost(friendPost({shareable: true})), true);
  assert.equal(isShareablePost(friendPost({isHouse: true})), true);
  // A made-up starter-ish id is not a starter task.
  assert.equal(isShareablePost(friendPost({taskId: 'starter-99'})), false);
  // An alias is resolved for /t/ links but is not the real task id.
  assert.equal(isShareablePost(friendPost({taskId: 'starter-09'})), false);
  assert.equal(isShareablePost(null), false);
  assert.equal(isShareablePost(friendPost({shareable: 'yes'})), false);
});

test('firstName: first word only, never an email, never empty', () => {
  assert.equal(firstName('Sage Arbor'), 'Sage');
  assert.equal(firstName('  '), 'Someone');
  assert.equal(firstName(SECRET_EMAIL), 'Someone');
  assert.equal(firstName('x'.repeat(80)).length, 24);
});

// ---- /p/ ----

test('/p/ shareable post: 200, cacheable, OG + Twitter tags with poster and mp4', async () => {
  const res = await get('/p/post1', storeOf({post1: starterPost()}));
  assert.equal(res.status, 200);
  assert.equal(res.headers['Cache-Control'], CACHE_OK);
  assert.match(res.headers['Content-Type'], /text\/html/);
  assert.equal(meta(res.body, 'og:title'), 'Sage vs. The face of someone who has just remembered the oven is on');
  assert.equal(meta(res.body, 'og:image'), starterPost().posterUrl.replace(/&/g, '&amp;'));
  assert.equal(meta(res.body, 'og:video'), starterPost().playbackUrl.replace(/&/g, '&amp;'));
  assert.equal(meta(res.body, 'og:video:type'), 'video/mp4');
  assert.equal(meta(res.body, 'og:type'), 'video.other');
  assert.equal(meta(res.body, 'twitter:card'), 'summary_large_image');
  assert.equal(meta(res.body, 'og:url'), 'https://taskmaster-app-3d480.web.app/p/post1');
  assert.ok(meta(res.body, 'twitter:title'));
  assert.ok(meta(res.body, 'og:description').includes('Your turn — 30 s'));
  assert.ok(res.body.includes('NO REGRETS'));
  assert.ok(res.body.includes('8 s'));
  assert.ok(res.body.includes('playsinline'));
  // "Your turn" goes into the same task, carrying the post it answers.
  assert.ok(res.body.includes('href="https://taskmaster-app-3d480.web.app/?task=starter-09-v2&amp;from=post1"'));
  assert.ok(res.body.includes('Your turn — 30 s'));
  assert.ok(res.body.includes('Open in app'));
  assert.ok(res.body.includes('Play in browser'));
  assertNoPii(res.body);
});

test('/p/ falls back to the original clip while the transcode is pending', async () => {
  const res = await get('/p/p2', storeOf({p2: starterPost({playbackUrl: undefined, posterUrl: undefined})}));
  assert.equal(res.status, 200);
  assert.equal(meta(res.body, 'og:video'), starterPost().videoUrl.replace(/&/g, '&amp;'));
  // No poster yet: the brand icon stands in.
  assert.match(meta(res.body, 'og:image'), /Icon-512\.png$/);
});

test('/p/ private friend-game post: 404 identical to a missing post', async () => {
  const privateRes = await get('/p/priv', storeOf({priv: friendPost()}));
  const missingRes = await get('/p/nope', storeOf({}));
  assert.equal(privateRes.status, 404);
  assert.equal(missingRes.status, 404);
  assert.equal(privateRes.body, missingRes.body, 'a private post must be indistinguishable from none');
  assert.ok(!privateRes.body.includes('Private inside joke'));
  assertNoPii(privateRes.body);
});

test('/p/ friend-game post the owner shared: 200, but no game task id and a generic Play button', async () => {
  const res = await get('/p/shared', storeOf({shared: friendPost({shareable: true})}));
  assert.equal(res.status, 200);
  assert.ok(res.body.includes('Private inside joke'));
  assert.ok(!res.body.includes('task-in-a-friend-game'));
  assert.ok(res.body.includes('Play your own — 30 s'));
  assertNoPii(res.body);
});

test('/p/ starter post the owner opted out of: 404', async () => {
  const res = await get('/p/out', storeOf({out: starterPost({shareable: false})}));
  assert.equal(res.status, 404);
});

test('/p/ escapes user text (no HTML injection via caption/name/text)', async () => {
  const res = await get('/p/x', storeOf({
    x: starterPost({
      mediaType: 'text',
      text: '<script>alert(1)</script>',
      displayName: '<img src=x onerror=alert(1)>',
      caption: '"><b>hi',
    }),
  }));
  assert.equal(res.status, 200);
  assert.ok(!res.body.includes('<script>alert(1)'));
  assert.ok(!res.body.includes('<img src=x'));
  assert.ok(!res.body.includes('"><b>hi'));
  assert.ok(res.body.includes('&lt;script&gt;alert(1)&lt;/script&gt;'));
});

test('/p/ drops non-https media URLs', async () => {
  const res = await get('/p/x', storeOf({x: starterPost({playbackUrl: 'javascript:alert(1)', videoUrl: 'http://evil'})}));
  assert.equal(res.status, 200);
  assert.ok(!res.body.includes('javascript:alert'));
  assert.equal(meta(res.body, 'og:video'), null);
});

test('/p/<id>/image.jpg serves a shareable photo post as JPEG, 404s a private one', async () => {
  const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]);
  const photo = {mediaType: 'photo', photoData: jpeg.toString('base64'), videoUrl: null, posterUrl: null};
  const ok = await get('/p/ph/image.jpg', storeOf({ph: starterPost(photo)}));
  assert.equal(ok.status, 200);
  assert.equal(ok.headers['Content-Type'], 'image/jpeg');
  assert.deepEqual(ok.body, jpeg);

  const page = await get('/p/ph', storeOf({ph: starterPost(photo)}));
  assert.equal(meta(page.body, 'og:image'), 'https://taskmaster-app-3d480.web.app/p/ph/image.jpg');

  const hidden = await get('/p/ph/image.jpg', storeOf({ph: friendPost(photo)}));
  assert.equal(hidden.status, 404);
  assert.match(hidden.headers['Content-Type'], /text\/html/);
});

// ---- /c/ ----

test('/c/ is the dare framing of the same post', async () => {
  const res = await get('/c/post1', storeOf({post1: starterPost()}));
  assert.equal(res.status, 200);
  assert.ok(res.body.includes('Sage dares you'));
  assert.ok(meta(res.body, 'og:description').startsWith('Sage dares you.'));
  assert.equal(meta(res.body, 'og:url'), 'https://taskmaster-app-3d480.web.app/c/post1');
  assertNoPii(res.body);
  const priv = await get('/c/priv', storeOf({priv: friendPost()}));
  assert.equal(priv.status, 404);
});

// ---- /t/ ----

test('/t/ starter task: tags for crawlers, straight into the web cold open for people', async () => {
  const store = storeOf({});
  const res = await get('/t/starter-09', store, {from: 'post1'});
  assert.equal(res.status, 200);
  assert.equal(meta(res.body, 'og:title'), starterTask('starter-09-v3').title);
  assert.equal(meta(res.body, 'og:url'), 'https://taskmaster-app-3d480.web.app/t/starter-09-v3');
  assert.ok(res.body.includes('location.replace("https://taskmaster-app-3d480.web.app/?task=starter-09-v3&from=post1")'));
  assert.deepEqual(store.reads, [], 'a task page needs no database read');
});

test('/t/ unknown or non-public task: 404, and junk from= is dropped', async () => {
  assert.equal((await get('/t/task-in-a-friend-game', storeOf({}))).status, 404);
  const res = await get('/t/starter-03', storeOf({}), {from: '"><script>'});
  assert.equal(res.status, 200);
  assert.ok(!res.body.includes('<script>"'));
  assert.ok(res.body.includes('?task=starter-03"'));
});

// ---- /f/ ----

test('/f/ starter finale with every clip shareable: 200 with the montage as og:video', async () => {
  const montage = {
    taskId: 'starter-01-v2', taskTitle: 'Egg on a spoon', gameId: 'starter',
    finaleUrl: 'https://firebasestorage.googleapis.com/v0/b/b/o/montages%2Fstarter%2Ffinale.mp4?alt=media',
    sourcePostIds: ['a', 'b'],
  };
  const store = storeOf(
    {a: starterPost({taskId: 'starter-01-v2'}), b: starterPost({taskId: 'starter-01-v2', posterUrl: undefined})},
    {'starter_starter-01-v2': montage},
  );
  const res = await get('/f/starter_starter-01-v2', store);
  assert.equal(res.status, 200);
  assert.equal(meta(res.body, 'og:video'), montage.finaleUrl);
  assert.equal(meta(res.body, 'og:image'), starterPost().posterUrl.replace(/&/g, '&amp;'));
  assert.equal(meta(res.body, 'og:title'), 'THE FINALE: Egg on a spoon');
  assert.ok(res.body.includes('?task=starter-01-v2"'));
  assertNoPii(res.body);
});

test('/f/ one private clip inside keeps the whole finale private', async () => {
  const montage = {
    taskId: 'task-in-a-friend-game', gameId: SECRET_GAME, taskTitle: 'Private inside joke',
    finaleUrl: 'https://firebasestorage.googleapis.com/v0/b/b/o/montages%2Fg%2Ffinale.mp4?alt=media',
    sourcePostIds: ['a', 'b'],
  };
  const store = storeOf({a: friendPost({shareable: true}), b: friendPost()}, {m1: montage});
  assert.equal((await get('/f/m1', store)).status, 404);
  // ...and once both owners share, it is public.
  const store2 = storeOf({a: friendPost({shareable: true}), b: friendPost({shareable: true})}, {m1: montage});
  const ok = await get('/f/m1', store2);
  assert.equal(ok.status, 200);
  assertNoPii(ok.body);
});

test('/f/ missing montage, no finale yet, or no sources: 404', async () => {
  assert.equal((await get('/f/none', storeOf({}))).status, 404);
  assert.equal((await get('/f/m', storeOf({}, {m: {sourcePostIds: ['a']}}))).status, 404);
  assert.equal((await get('/f/m', storeOf({}, {m: {finaleUrl: 'https://x/f.mp4', sourcePostIds: []}}))).status, 404);
});

// ---- links + handler ----

test('yourTurnUrl: public task carries task and from; anything else goes to the app root', () => {
  assert.equal(yourTurnUrl('starter-03', 'abc'), 'https://taskmaster-app-3d480.web.app/?task=starter-03&from=abc');
  assert.equal(yourTurnUrl(null, 'abc'), 'https://taskmaster-app-3d480.web.app/');
});

test('httpHandler: status, headers and body reach the response; errors are 500 no-store', async () => {
  const calls = {};
  const res = {
    status(s) {
      calls.status = s;
      return this;
    },
    set(h, v) {
      calls.headers = typeof h === 'string' ? {[h]: v} : h;
      return this;
    },
    send(b) {
      calls.body = b;
    },
  };
  const db = () => ({
    collection: () => ({doc: () => ({get: async () => ({exists: true, data: () => starterPost()})})}),
  });
  await httpHandler(db, {error() {}})({path: '/p/abc', query: {}}, res);
  assert.equal(calls.status, 200);
  assert.equal(calls.headers['Cache-Control'], CACHE_OK);
  assert.ok(calls.body.includes('og:title'));

  const broken = () => ({collection: () => ({doc: () => ({get: async () => {
    throw new Error('boom');
  }})})});
  await httpHandler(broken, {error() {}})({path: '/p/abc', query: {}}, res);
  assert.equal(calls.status, 500);
  assert.equal(calls.headers['Cache-Control'], 'no-store');
});

test('page stays small (~10 KB budget)', async () => {
  const res = await get('/p/post1', storeOf({post1: starterPost()}));
  assert.ok(Buffer.byteLength(res.body) < 12 * 1024, `page is ${Buffer.byteLength(res.body)} bytes`);
});

// ---- starter catalog stays in step with the app ----

test('starter_tasks.js mirrors starter_pack_data.dart (ids, order, durations) and contract.js', () => {
  const dart = fs.readFileSync(
    path.join(__dirname, '../../lib/features/tasks/data/datasources/starter_pack_data.dart'), 'utf8');
  const section = (from, to) => dart.slice(dart.indexOf(from), dart.indexOf(to));
  const idsIn = (body) => [...body.matchAll(/id: '([^']+)'/g)].map((m) => m[1]);
  const durationsIn = (body) => [...body.matchAll(/durationSeconds: (\d+)/g)].map((m) => Number(m[1]));
  const gatherIn = (body) => [...body.matchAll(/gatherSeconds: (\d+)/g)].map((m) => Number(m[1]));
  const tasksBody = section('static List<Task> tasks()', 'static List<Task> retiredTasks()');
  const retiredBody = section('static List<Task> retiredTasks()', 'static List<Task> allTasks()');
  const ids = idsIn(tasksBody);
  const retiredIds = idsIn(retiredBody);
  assert.equal(ids.length, 10);
  assert.deepEqual(STARTER_TASKS.map((t) => t.id), ids);
  assert.deepEqual(STARTER_TASKS.map((t) => t.durationSeconds), durationsIn(tasksBody));
  assert.deepEqual(STARTER_TASKS.filter((t) => t.gatherSeconds).map((t) => t.gatherSeconds), gatherIn(tasksBody));
  assert.deepEqual(RETIRED_STARTER_TASKS.map((t) => t.id), retiredIds);
  assert.deepEqual(RETIRED_STARTER_TASKS.map((t) => t.durationSeconds), durationsIn(retiredBody));
  assert.deepEqual(new Set([...ids, ...retiredIds]), STARTER_TASK_IDS);
});

test('old and short starter ids still resolve', () => {
  for (const t of RETIRED_STARTER_TASKS) assert.equal(starterTask(t.id).id, t.id);
  assert.equal(starterTask('starter-09').id, 'starter-09-v3');
  assert.equal(starterTask('starter-01').id, 'starter-01-v2');
  assert.equal(starterTask('starter-99'), null);
});

test('a gather -> reveal task page shows only the gather stage (no spoiler)', async () => {
  const gather = STARTER_TASKS.find((t) => t.gatherPrompt);
  assert.ok(gather, 'expected a gather task in the starter ten');
  const res = await get(`/t/${gather.id}`, storeOf({}));
  assert.equal(res.status, 200);
  assert.ok(res.body.includes(gather.gatherTitle));
  assert.ok(!res.body.includes(gather.title), 'the real task title must not be on the page');
  assert.ok(!res.body.includes(gather.description));
});

// ---- watermark hook ----

test('watermarkFor: starter always branded; friend game clean only for a Pro host', async () => {
  const getGame = async () => ({creatorId: 'host'});
  assert.equal(await watermarkFor({gameId: 'g', isStarter: true, getGame, isProFn: async () => true}), WATERMARK_TEXT);
  assert.equal(await watermarkFor({gameId: 'g', isStarter: false, getGame}), WATERMARK_TEXT);
  assert.equal(await watermarkFor({gameId: 'g', isStarter: false, getGame, isProFn: async (u) => u === 'host'}), null);
  const failing = async () => {
    throw new Error('down');
  };
  assert.equal(await watermarkFor({gameId: 'g', isStarter: false, getGame: failing, isProFn: async () => true}),
    WATERMARK_TEXT);
});

test('watermarkFilter: one drawtext via a text file, empty for no text', () => {
  const tmp = fs.mkdtempSync(path.join(require('os').tmpdir(), 'wm-'));
  const f = watermarkFilter('taskcaster.app', {tmpDir: tmp});
  assert.match(f, /^drawtext=fontfile=.*:textfile=.*:expansion=none/);
  assert.ok(f.includes('fontcolor=white@0.72'));
  assert.equal(watermarkFilter('', {tmpDir: tmp}), '');
  fs.rmSync(tmp, {recursive: true, force: true});
});
