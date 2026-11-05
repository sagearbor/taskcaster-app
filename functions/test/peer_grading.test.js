'use strict';

// WP-13 friend games: everyone grades everyone. The lock rules (all other
// players graded, or 24 h), the points formula, the server-owned totals, and a
// whole 3-player game played to the end with nobody as judge.

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  LOCK_AFTER_MS,
  gradeDocId,
  resultDocId,
  pointsFor,
  settleTask,
  settleInStore,
  tasksToSweep,
  scoreInNotification,
} = require('../src/peer_grading');
const {deletePeerData} = require('../src/account_deletion');

const T0 = Date.parse('2026-11-05T10:00:00.000Z');
const iso = (ms) => new Date(ms).toISOString();

const player = (userId) => ({userId, displayName: userId, totalScore: 0});

function makeTask(id, uids) {
  return {
    id,
    title: `Task ${id}`,
    status: 'waiting_for_submissions',
    submissions: [],
    playerStatuses: Object.fromEntries(uids.map((u) => [u, {playerId: u, state: 'not_started'}])),
  };
}

function makeGame({uids = ['a', 'b', 'c'], taskIds = ['t1'], mode = 'group'} = {}) {
  return {
    gameName: 'Friday',
    creatorId: uids[0],
    judgeId: '',
    status: 'inProgress',
    players: uids.map(player),
    playerIds: uids.slice(),
    tasks: taskIds.map((id) => makeTask(id, uids)),
    settings: {judgingMode: mode},
    currentTaskIndex: 0,
  };
}

/** A player posts their entry (what submitTaskAnswer writes). */
function post(game, taskId, uid, atMs = T0) {
  const task = game.tasks.find((t) => t.id === taskId);
  task.playerStatuses[uid] = {...task.playerStatuses[uid], state: 'submitted', submittedAt: iso(atMs)};
  task.submissions = [...task.submissions.filter((s) => s.userId !== uid),
    {id: `s-${uid}`, userId: uid, score: 0, isJudged: false, submittedAt: iso(atMs)}];
}

const grade = (taskId, targetUid, graderUid, score) => ({taskId, targetUid, graderUid, score});

// ---------------------------------------------------------------------------
// Pure rules
// ---------------------------------------------------------------------------

test('points are round(mean x 2) on 0..10, and 0 with no grades', () => {
  assert.deepEqual(pointsFor([]), {mean: 0, points: 0});
  assert.equal(pointsFor([5, 5]).points, 10);
  assert.equal(pointsFor([1]).points, 2);
  assert.equal(pointsFor([3, 4]).points, 7); // mean 3.5 -> 7
  assert.equal(pointsFor([4, 4, 5]).points, 9); // mean 4.33 -> 8.67 -> 9
});

test('grade and result doc ids bind task, entry and grader', () => {
  assert.equal(gradeDocId('t1', 'b', 'a'), 't1__b__a');
  assert.equal(resultDocId('t1', 'b'), 't1__b');
});

test('judge-mode games (and games without the field) are never settled', () => {
  const g = makeGame({mode: 'judge'});
  post(g, 't1', 'a');
  assert.equal(settleTask({game: g, taskId: 't1', grades: [], results: {}, nowMs: T0}), null);
  delete g.settings.judgingMode;
  assert.equal(settleTask({game: g, taskId: 't1', grades: [], results: {}, nowMs: T0}), null);
});

test('an entry stays open until EVERY other player has graded it', () => {
  const g = makeGame();
  post(g, 't1', 'a');
  post(g, 't1', 'b');
  const out = settleTask({game: g, taskId: 't1', grades: [grade('t1', 'a', 'b', 4)], results: {}, nowMs: T0 + 1000});
  assert.deepEqual(out.locks, [], 'c has not graded a yet');
  assert.equal(out.complete, false);
  assert.deepEqual(out.peerGraders, {a: ['b']});
});

test('an entry locks with the average once all other players have graded it', () => {
  const g = makeGame();
  post(g, 't1', 'a');
  post(g, 't1', 'b');
  post(g, 't1', 'c');
  const out = settleTask({
    game: g, taskId: 't1', results: {}, nowMs: T0 + 1000,
    grades: [grade('t1', 'a', 'b', 4), grade('t1', 'a', 'c', 5)],
  });
  assert.deepEqual(out.locks, [{uid: 'a', points: 9, mean: 4.5, gradeCount: 2}]);
  assert.equal(out.complete, false, 'b and c are still open');
});

test('self-grades, strangers, bad scores and duplicates are ignored', () => {
  const g = makeGame();
  post(g, 't1', 'a');
  post(g, 't1', 'b');
  post(g, 't1', 'c');
  const out = settleTask({
    game: g, taskId: 't1', results: {}, nowMs: T0 + 1000,
    grades: [
      grade('t1', 'a', 'a', 5), // self
      grade('t1', 'a', 'zed', 5), // not in the game
      grade('t1', 'a', 'b', 9), // out of range
      grade('t2', 'a', 'c', 5), // another task
      grade('t1', 'a', 'b', 2),
      grade('t1', 'a', 'b', 5), // duplicate: first one counts
      grade('t1', 'a', 'c', 2),
    ],
  });
  assert.deepEqual(out.locks, [{uid: 'a', points: 4, mean: 2, gradeCount: 2}]);
});

test('a player who skipped is not waited on', () => {
  const g = makeGame();
  post(g, 't1', 'a');
  post(g, 't1', 'b');
  g.tasks[0].playerStatuses.c.state = 'skipped';
  const out = settleTask({
    game: g, taskId: 't1', results: {}, nowMs: T0 + 1000,
    grades: [grade('t1', 'a', 'b', 3), grade('t1', 'b', 'a', 5)],
  });
  assert.deepEqual(out.locks.map((l) => l.uid).sort(), ['a', 'b']);
  assert.equal(out.complete, true);
});

test('after 24 h everything locks with whatever grades exist, and the task completes', () => {
  const g = makeGame();
  post(g, 't1', 'a', T0);
  post(g, 't1', 'b', T0 + 60_000);
  // c never posts; only b graded a.
  const grades = [grade('t1', 'a', 'b', 4)];
  const early = settleTask({game: g, taskId: 't1', grades, results: {}, nowMs: T0 + LOCK_AFTER_MS - 1});
  assert.deepEqual(early.locks, []);
  const late = settleTask({game: g, taskId: 't1', grades, results: {}, nowMs: T0 + LOCK_AFTER_MS});
  assert.equal(late.expired, true);
  assert.deepEqual(late.locks, [
    {uid: 'a', points: 8, mean: 4, gradeCount: 1},
    {uid: 'b', points: 0, mean: 0, gradeCount: 0},
  ]);
  assert.equal(late.complete, true, 'c no longer holds the task up');
});

test('an already-locked entry is never locked (or scored) twice', () => {
  const g = makeGame({uids: ['a', 'b']});
  post(g, 't1', 'a');
  post(g, 't1', 'b');
  const out = settleTask({
    game: g, taskId: 't1', nowMs: T0 + 1000,
    grades: [grade('t1', 'a', 'b', 5), grade('t1', 'b', 'a', 1)],
    results: {a: {uid: 'a', taskId: 't1', points: 10}},
  });
  assert.deepEqual(out.locks.map((l) => l.uid), ['b']);
  assert.equal(out.complete, true);
});

test('the sweep visits open tasks with at least one entry, in group games only', () => {
  const g = makeGame({taskIds: ['t1', 't2', 't3']});
  post(g, 't1', 'a');
  g.tasks[2].status = 'completed';
  g.tasks[2].playerStatuses.a.state = 'judged';
  assert.deepEqual(tasksToSweep(g), ['t1']);
  assert.deepEqual(tasksToSweep({...g, settings: {}}), []);
  assert.deepEqual(tasksToSweep({...g, status: 'completed'}), []);
});

test('the push names the score, never the graders', () => {
  const n = scoreInNotification({gameId: 'g', taskId: 't1', taskTitle: 'Egg race', lock: {uid: 'a', points: 9, mean: 4.5, gradeCount: 2}});
  assert.equal(n.title, 'Your score for "Egg race" is in');
  assert.match(n.body, /9\/10/);
  assert.doesNotMatch(n.body, /\bb\b|\bc\b/);
  assert.equal(n.data.gameId, 'g');
});

// ---------------------------------------------------------------------------
// settleInStore against an in-memory store
// ---------------------------------------------------------------------------

function memoryStore(game) {
  const state = {game: JSON.parse(JSON.stringify(game)), grades: new Map(), results: new Map(), transactions: 0};
  return {
    state,
    addGrade(g) {
      const id = gradeDocId(g.taskId, g.targetUid, g.graderUid);
      if (state.grades.has(id)) throw new Error('already graded'); // the rules refuse it
      state.grades.set(id, g);
    },
    async runTransaction(fn) {
      state.transactions += 1;
      const writes = [];
      const tx = {
        getGame: async () => JSON.parse(JSON.stringify(state.game)),
        getGrades: async (_gameId, taskId) => [...state.grades.values()].filter((g) => g.taskId === taskId),
        getResults: async () => [...state.results.values()],
        setResult: (_gameId, id, data) => writes.push(() => state.results.set(id, data)),
        updateGame: (_gameId, fields) => writes.push(() => Object.assign(state.game, fields)),
      };
      const out = await fn(tx);
      writes.forEach((w) => w());
      return out;
    },
  };
}

test('a 3-player group game completes every task with no player marked judge', async () => {
  const uids = ['a', 'b', 'c'];
  const store = memoryStore(makeGame({uids, taskIds: ['t1', 't2']}));
  const settle = (taskId, nowMs = T0 + 5000) => settleInStore({store, gameId: 'g', taskId, nowMs});
  const scores = {t1: {a: 5, b: 3, c: 4}, t2: {a: 2, b: 5, c: 5}};

  for (const [index, taskId] of ['t1', 't2'].entries()) {
    assert.equal(store.state.game.currentTaskIndex, index);
    for (const uid of uids) post(store.state.game, taskId, uid);
    for (const grader of uids) {
      for (const target of uids) {
        if (target === grader) continue;
        store.addGrade(grade(taskId, target, grader, scores[taskId][target]));
        // eslint-disable-next-line no-await-in-loop
        await settle(taskId);
      }
    }
    const task = store.state.game.tasks[index];
    assert.equal(task.status, 'completed', `${taskId} completed`);
    for (const uid of uids) {
      assert.equal(task.playerStatuses[uid].state, 'judged');
      assert.equal(task.playerStatuses[uid].score, scores[taskId][uid] * 2);
      assert.equal(task.submissions.find((s) => s.userId === uid).isJudged, true);
    }
  }

  const game = store.state.game;
  assert.equal(game.status, 'completed');
  assert.equal(game.judgeId, '', 'nobody is the judge');
  const totals = Object.fromEntries(game.players.map((p) => [p.userId, p.totalScore]));
  assert.deepEqual(totals, {a: 14, b: 16, c: 18});
  assert.equal(store.state.results.size, 6, 'one ledger entry per player per task');
});

test('totals come from the ledger, so a scribbled totalScore is overwritten', async () => {
  const store = memoryStore(makeGame({uids: ['a', 'b']}));
  post(store.state.game, 't1', 'a');
  post(store.state.game, 't1', 'b');
  store.state.game.players[0].totalScore = 999; // tampered
  store.addGrade(grade('t1', 'b', 'a', 1));
  const out = await settleInStore({store, gameId: 'g', taskId: 't1', nowMs: T0 + 1});
  assert.deepEqual(out.locks.map((l) => l.uid), ['b']);
  assert.deepEqual(store.state.game.players.map((p) => p.totalScore), [0, 2]);
});

test('settling a judge-mode or finished game writes nothing', async () => {
  const judge = memoryStore(makeGame({mode: 'judge'}));
  assert.equal((await settleInStore({store: judge, gameId: 'g', taskId: 't1', nowMs: T0})).status, 'not-group');
  const done = memoryStore({...makeGame(), status: 'completed'});
  assert.equal((await settleInStore({store: done, gameId: 'g', taskId: 't1', nowMs: T0})).status, 'not-in-progress');
});

// ---------------------------------------------------------------------------
// Account deletion
// ---------------------------------------------------------------------------

function fakeGroupDb(docs) {
  const deleted = [];
  const ref = (path) => ({path});
  return {
    deleted,
    collectionGroup(name) {
      return {
        where(field, op, value) {
          assert.equal(op, '==');
          return {
            async get() {
              const hits = Object.entries(docs)
                .filter(([path, data]) => path.split('/').slice(-2)[0] === name && data[field] === value)
                .map(([path]) => ({ref: ref(path)}));
              return {docs: hits, size: hits.length};
            },
          };
        },
      };
    },
    batch() {
      const pending = [];
      return {
        delete: (r) => pending.push(r.path),
        commit: async () => deleted.push(...pending),
      };
    },
  };
}

test('account deletion removes the user\'s peer grades (given and received) and locked scores', async () => {
  const db = fakeGroupDb({
    'games/g/peer_grades/t1__b__doomed': {graderUid: 'doomed', targetUid: 'b'},
    'games/g/peer_grades/t1__doomed__b': {graderUid: 'b', targetUid: 'doomed'},
    'games/g/peer_grades/t1__c__b': {graderUid: 'b', targetUid: 'c'},
    'games/g/peer_results/t1__doomed': {uid: 'doomed', points: 8},
    'games/g/peer_results/t1__b': {uid: 'b', points: 6},
  });
  const n = await deletePeerData(db, 'doomed');
  assert.equal(n, 3);
  assert.deepEqual(db.deleted.sort(), [
    'games/g/peer_grades/t1__b__doomed',
    'games/g/peer_grades/t1__doomed__b',
    'games/g/peer_results/t1__doomed',
  ]);
});
