'use strict';

// Arena moderation (App Store 1.2): onReportCreated logs every report and
// takes a post down once three different people have reported it.

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  HIDE_AT_REPORTS,
  REASONS,
  reportDocId,
  decideReport,
  handleReportInStore,
} = require('../src/reports');
const {isMontageablePost} = require('../src/contract');
const {isShareablePost} = require('../src/share_page');

const NOW = '2026-11-11T12:00:00.000Z';
const nowIso = () => NOW;

/** In-memory store: posts by id, reports as a list of docs. */
function makeStore({posts = {}, reports = []} = {}) {
  const hides = [];
  return {
    posts,
    reports,
    hides,
    async getPost(postId) {
      return posts[postId] ? {...posts[postId]} : null;
    },
    async reporterIdsFor(postId) {
      return reports.filter((r) => r.postId === postId).map((r) => r.reporterId);
    },
    async hidePost(postId, fields) {
      hides.push({postId, fields});
      posts[postId] = {...posts[postId], ...fields};
    },
  };
}

const report = (postId, reporterId, reason = 'spam') => ({
  postId,
  authorId: 'author',
  reporterId,
  reason,
  createdAt: NOW,
});

/** File a report the way the trigger sees it: the doc exists, then the handler runs. */
async function file(store, r) {
  store.reports.push(r);
  return handleReportInStore({store, report: r, nowIso});
}

const videoPost = (extra = {}) => ({
  userId: 'author',
  taskId: 'starter-01',
  mediaType: 'video',
  videoStoragePath: 'submissions/author/20261111/0',
  ...extra,
});

test('the four reasons match what the app and the rules use', () => {
  assert.deepEqual([...REASONS], ['inappropriate', 'spam', 'harassment', 'other']);
  assert.equal(HIDE_AT_REPORTS, 3);
});

test('report doc id is one per (post, reporter)', () => {
  assert.equal(reportDocId('p1', 'u1'), 'p1_u1');
});

test('one or two reports are logged but leave the post up', async () => {
  const store = makeStore({posts: {p1: videoPost()}});
  const first = await file(store, report('p1', 'a'));
  assert.deepEqual(first, {postId: 'p1', reportCount: 1, hidden: false, reason: 'below-threshold'});
  const second = await file(store, report('p1', 'b'));
  assert.equal(second.reportCount, 2);
  assert.equal(second.hidden, false);
  assert.equal(store.hides.length, 0);
  assert.equal(store.posts.p1.hidden, undefined);
});

test('the third distinct reporter hides the post', async () => {
  const store = makeStore({posts: {p1: videoPost()}});
  await file(store, report('p1', 'a'));
  await file(store, report('p1', 'b', 'harassment'));
  const third = await file(store, report('p1', 'c', 'inappropriate'));
  assert.deepEqual(third, {postId: 'p1', reportCount: 3, hidden: true, reason: 'threshold-reached'});
  assert.deepEqual(store.hides, [{
    postId: 'p1',
    fields: {hidden: true, hiddenAt: NOW, hiddenBy: 'reports', reportCount: 3},
  }]);
  // ...and the hidden post drops out of montages and public share pages.
  assert.equal(isMontageablePost(store.posts.p1, 'starter-01'), false);
  assert.equal(isShareablePost(store.posts.p1), false);
});

test('a fourth report on an already-hidden post writes nothing more', async () => {
  const store = makeStore({posts: {p1: videoPost()}});
  // eslint-disable-next-line no-await-in-loop
  for (const who of ['a', 'b', 'c']) await file(store, report('p1', who));
  const fourth = await file(store, report('p1', 'd'));
  assert.equal(fourth.hidden, false);
  assert.equal(fourth.reason, 'already-hidden');
  assert.equal(store.hides.length, 1);
});

test('the same reporter counted twice is still one person', async () => {
  const store = makeStore({posts: {p1: videoPost()}});
  await file(store, report('p1', 'a'));
  await file(store, report('p1', 'a'));
  const out = await file(store, report('p1', 'b'));
  assert.equal(out.reportCount, 2);
  assert.equal(out.hidden, false);
});

test('reports on other posts do not count toward this one', async () => {
  const store = makeStore({posts: {p1: videoPost(), p2: videoPost()}});
  await file(store, report('p2', 'a'));
  await file(store, report('p2', 'b'));
  const out = await file(store, report('p1', 'c'));
  assert.equal(out.reportCount, 1);
  assert.equal(out.hidden, false);
});

test('house posts are logged but never auto-hidden', async () => {
  const store = makeStore({posts: {'house-starter-01': {userId: 'house', isHouse: true}}});
  // eslint-disable-next-line no-await-in-loop
  for (const who of ['a', 'b', 'c']) await file(store, report('house-starter-01', who));
  const out = await file(store, report('house-starter-01', 'd'));
  assert.equal(out.hidden, false);
  assert.equal(out.reason, 'house-post');
  assert.equal(store.hides.length, 0);
});

test('a report on a missing post, or with no postId, is a no-op', async () => {
  const store = makeStore();
  const missing = await file(store, report('gone', 'a'));
  assert.equal(missing.reason, 'post-missing');
  const bad = await handleReportInStore({store, report: {reporterId: 'a'}, nowIso});
  assert.equal(bad.reason, 'bad-report');
  assert.equal(store.hides.length, 0);
});

test('decideReport is pure', () => {
  assert.deepEqual(decideReport({post: {}, reportCount: 2}), {hide: false, reason: 'below-threshold'});
  assert.deepEqual(decideReport({post: {}, reportCount: 3}), {hide: true, reason: 'threshold-reached'});
  assert.deepEqual(decideReport({post: null, reportCount: 9}), {hide: false, reason: 'post-missing'});
});

test('an unhidden post is still montageable and shareable', () => {
  assert.equal(isMontageablePost(videoPost(), 'starter-01'), true);
  assert.equal(isShareablePost(videoPost({shareable: true})), true);
  assert.equal(isShareablePost(videoPost({shareable: true, hidden: true})), false);
});
