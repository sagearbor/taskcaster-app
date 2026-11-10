'use strict';

/**
 * scripts/purge_test_posts.js: which posts are test-walk candidates, and the
 * reversible hide / unhide / mark-stale updates. Pure functions over fixture
 * docs; nothing here touches Firestore.
 */

const test = require('node:test');
const assert = require('node:assert/strict');

const {
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
} = require('../scripts/purge_test_posts');

const AUDIT_UID = 'xUsHQrBtTwdCETXLdmaZgsgaLcp2';
const NOW = '2026-11-09T12:00:00.000Z';

const post = (id, extra = {}) => ({
  id,
  userId: 'real-user',
  displayName: 'Priya',
  gameId: 'g-solo',
  taskId: 'starter-06',
  mediaType: 'video',
  videoStoragePath: `submissions/real-user/20261109/${id}`,
  posterUrl: `https://cdn.example/${id}.jpg`,
  createdAt: '2026-11-09T10:00:00.000Z',
  ...extra,
});

const FIXTURES = [
  post('walk-photo', {userId: AUDIT_UID, displayName: 'Guest', mediaType: 'photo',
    photoData: 'AAAA', createdAt: '2026-11-09T09:00:00.000Z'}),
  post('walk-text', {userId: AUDIT_UID, displayName: 'Plucky Teapot', mediaType: 'text',
    text: 'test', createdAt: '2026-11-09T09:01:00.000Z'}),
  post('colorbars', {userId: 'old-walker', displayName: 'Guest', createdAt: '2026-10-01T09:00:00.000Z'}),
  post('house-06', {userId: 'house', isHouse: true, displayName: 'Guest'}),
  post('house-flagless', {userId: 'house', displayName: 'Guest'}),
  post('real', {}),
  post('real-same-name', {displayName: 'Guestimate'}),
];

test('the default uid list is the 2026-11-09 audit walk', () => {
  assert.deepEqual(DEFAULT_UIDS, [AUDIT_UID]);
});

test('candidates: listed uid or displayName Guest, never a house post', () => {
  const rows = selectCandidates(FIXTURES);
  assert.deepEqual(rows.map((r) => r.id), ['colorbars', 'walk-photo', 'walk-text']);
  const byId = Object.fromEntries(rows.map((r) => [r.id, r]));
  assert.deepEqual(byId['walk-photo'].reasons, ['uid', 'guest-name']);
  assert.deepEqual(byId['walk-text'].reasons, ['uid']);
  assert.deepEqual(byId.colorbars.reasons, ['guest-name']);
  // The poster frame is carried through for human review.
  assert.equal(byId.colorbars.posterUrl, 'https://cdn.example/colorbars.jpg');
  assert.equal(byId['walk-photo'].hasPhoto, true);
});

test('candidates: --uids replaces the default list', () => {
  const rows = selectCandidates(FIXTURES, {uids: ['real-user']});
  const ids = rows.map((r) => r.id).sort();
  // real-user's posts by uid, plus every non-house Guest post by name.
  assert.deepEqual(ids, ['colorbars', 'real', 'real-same-name', 'walk-photo']);
  assert.equal(rows.find((r) => r.id === 'walk-text'), undefined);
});

test('candidates: duplicates (the two queries overlap) appear once; junk input is ignored', () => {
  const rows = selectCandidates([FIXTURES[0], FIXTURES[0], null, {}, {id: 7}]);
  assert.deepEqual(rows.map((r) => r.id), ['walk-photo']);
  assert.deepEqual(selectCandidates(undefined), []);
});

test('candidates: already-hidden posts are listed and flagged', () => {
  const rows = selectCandidates([post('h', {userId: AUDIT_UID, shareable: false, hiddenReason: HIDDEN_REASON})]);
  assert.equal(rows[0].hidden, true);
  assert.match(formatCandidate(rows[0]), /already hidden/);
});

test('formatCandidate prints the posterUrl for a video', () => {
  const [row] = selectCandidates([post('v', {userId: AUDIT_UID})]);
  const line = formatCandidate(row);
  assert.match(line, /poster=https:\/\/cdn\.example\/v\.jpg/);
  assert.match(line, /\[uid\]/);
});

test('ids file round-trips and ignores comments and blank lines', () => {
  const rows = selectCandidates(FIXTURES);
  const text = idsFileText(rows);
  assert.deepEqual(parseIdsFile(text), ['colorbars', 'walk-photo', 'walk-text']);
  assert.deepEqual(parseIdsFile('\n  a  # note\n# b\nc\na\n'), ['a', 'c']);
});

test('hide: private + reason, remembering the previous shareable', () => {
  assert.deepEqual(hideUpdate(post('p', {shareable: true}), NOW).update, {
    shareable: false, hiddenReason: HIDDEN_REASON, hiddenAt: NOW, hiddenPrevShareable: true,
  });
  assert.equal(hideUpdate(post('p'), NOW).update.hiddenPrevShareable, null);
  assert.deepEqual(hideUpdate(post('h', {userId: 'house', isHouse: true}), NOW), {skip: 'house'});
  assert.deepEqual(hideUpdate(null, NOW), {skip: 'missing'});
  assert.deepEqual(hideUpdate(post('x', {hiddenReason: HIDDEN_REASON}), NOW), {skip: 'already-hidden'});
});

test('unhide restores exactly what hide changed', () => {
  const before = post('p', {shareable: true});
  const hidden = {...before, ...hideUpdate(before, NOW).update};
  const {update} = unhideUpdate(hidden);
  assert.equal(update.shareable, true);
  assert.equal(update.hiddenReason, DELETE);

  // An absent flag comes back absent.
  const flagless = post('q');
  const hidden2 = {...flagless, ...hideUpdate(flagless, NOW).update};
  assert.equal(unhideUpdate(hidden2).update.shareable, DELETE);

  // A post its owner made private is not ours to unhide.
  assert.deepEqual(unhideUpdate(post('r', {shareable: false})), {skip: 'not-hidden-by-this-script'});
});

test('toFirestore swaps DELETE for FieldValue.delete()', () => {
  const FieldValue = {delete: () => 'DEL'};
  assert.deepEqual(toFirestore({a: 1, b: DELETE, c: null}, FieldValue), {a: 1, b: 'DEL', c: null});
});

test('affectedMontages: video posts only, starter tasks share one scope', () => {
  const m = affectedMontages([
    post('a', {gameId: 'g1'}),
    post('b', {gameId: 'g2'}),
    post('c', {mediaType: 'photo', taskId: 'starter-07'}),
    post('d', {gameId: 'friends', taskId: 'task-9'}),
  ]);
  assert.deepEqual([...m.keys()].sort(), ['friends_task-9', 'starter_starter-06']);
});

test('eligibleClipCount ignores hidden posts', () => {
  const scope = [
    post('a'),
    post('b', {shareable: false, hiddenReason: HIDDEN_REASON}),
    post('c', {taskId: 'starter-07'}),
    post('h', {userId: 'house', isHouse: true}),
  ];
  assert.equal(eligibleClipCount(scope, 'starter-06'), 1);
});

test('stale montage with clips left: queued for the settle pass', () => {
  const {update} = staleMontageUpdate(
    {status: 'ready', finaleUrl: 'f', momentsUrl: 'm', pendingCount: 0, lockedAt: 'x'}, 2, NOW);
  assert.equal(update.status, 'pending');
  assert.equal(update.pendingCount, 3);
  assert.equal(update.pendingSince, NOW);
  assert.equal(update.lockedAt, null);
  assert.equal(update.finaleUrl, undefined, 'the old finale keeps playing until replaced');
});

test('stale montage with no clips left: URLs parked, not deleted', () => {
  const {update} = staleMontageUpdate({status: 'ready', finaleUrl: 'f', momentsUrl: 'm'}, 0, NOW);
  assert.equal(update.staleFinaleUrl, 'f');
  assert.equal(update.staleMomentsUrl, 'm');
  assert.equal(update.finaleUrl, DELETE);
  assert.equal(update.momentsUrl, DELETE);
  assert.equal(update.status, 'failed');
  assert.deepEqual(staleMontageUpdate({status: 'failed'}, 0, NOW), {skip: 'nothing-to-park'});
  assert.deepEqual(staleMontageUpdate(null, 3, NOW), {skip: 'no-montage'});
});

test('stale montage after an unhide: parked URLs come back and it re-renders', () => {
  const {update} = staleMontageUpdate(
    {status: 'failed', staleFinaleUrl: 'f', staleMomentsUrl: 'm'}, 1, NOW);
  assert.equal(update.finaleUrl, 'f');
  assert.equal(update.momentsUrl, 'm');
  assert.equal(update.staleFinaleUrl, DELETE);
  assert.equal(update.status, 'pending');
});

test('args: dry run by default, no delete mode, writes need a mode and ids', () => {
  const a = parseArgs([]);
  assert.equal(a.hide || a.unhide || a.markStale || a.write, false);
  assert.deepEqual(a.uids, DEFAULT_UIDS);
  assert.deepEqual(parseArgs(['--uids', 'a, b']).uids, ['a', 'b']);
  assert.throws(() => parseArgs(['--delete']), /no delete mode/);
  assert.throws(() => parseArgs(['--hide']), /--ids/);
  assert.throws(() => parseArgs(['--write']), /only applies/);
  assert.throws(() => parseArgs(['--hide', '--unhide', '--ids', 'f']), /Pick one/);
  assert.throws(() => parseArgs(['--ids']), /needs a value/);
  const h = parseArgs(['--hide', '--ids', 'f.txt', '--write']);
  assert.equal(h.hide && h.write, true);
  assert.equal(h.ids, 'f.txt');
});
