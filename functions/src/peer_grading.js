'use strict';

/**
 * WP-13 friend games: everyone grades everyone.
 *
 * A friend game with `settings.judgingMode == 'group'` has no human judge.
 * Once a player has posted their entry for a task, they grade every other
 * player's entry for that task, 1..5, the same scale as the Arena. Each grade
 * is its own document, written by the grader and nobody else:
 *
 *   games/{gameId}/peer_grades/{taskId}__{targetUid}__{graderUid}
 *     {taskId, taskIndex, targetUid, graderUid, score, createdAt}
 *
 * firestore.rules makes that doc create-only, under the grader's own uid,
 * never on their own entry, only once both players have posted. Clients can
 * never write a score: this module derives them, server-side, with the Admin
 * SDK.
 *
 * An entry LOCKS when every other player who has not skipped the task has
 * graded it, or 24 hours after the task opened, whichever is first. Its
 * points are `round(mean x 2)` (0..10, the Arena's crowd formula, so the
 * friend scoreboard uses the same 0..10 scale as a human judge); an entry
 * nobody graded locks at 0. Each lock is recorded once in a server-owned
 * ledger the client cannot write:
 *
 *   games/{gameId}/peer_results/{taskId}__{uid}
 *     {taskId, uid, points, mean, gradeCount, lockedAt}
 *
 * players[].totalScore is recomputed from that ledger on every settle, so a
 * player who scribbles on the game's `tasks` array (which the games rule has to
 * let them write) can neither score themselves nor be scored twice.
 *
 * A task COMPLETES when every player has a locked entry or skipped it (after
 * the 24 h window, a player who never posted no longer holds it up). The game
 * then moves to the next task, or ends after the last one.
 *
 * `settleTask` is pure; `settleInStore` applies it inside one transaction
 * against a small store interface (Firestore in production, an in-memory fake
 * in tests).
 */

const GROUP = 'group';

/**
 * An entry's score locks this long after the task opened at most. A task opens
 * when it becomes the current task (`task.openedAt`, stamped by the client on
 * start/advance and by this module when it advances); tasks without that stamp
 * (written before it existed) open at their first entry, or — for the current
 * task — the first time the settle pass sees them, so even a task nobody posts
 * to always expires.
 */
const LOCK_AFTER_MS = 24 * 60 * 60 * 1000;

const GAMES = 'games';
const PEER_GRADES = 'peer_grades';
const PEER_RESULTS = 'peer_results';

/** Doc id of one grade: one per (task, entry, grader), so a second is refused. */
const gradeDocId = (taskId, targetUid, graderUid) => `${taskId}__${targetUid}__${graderUid}`;

/** Doc id of one locked entry in the ledger. */
const resultDocId = (taskId, uid) => `${taskId}__${uid}`;

const POSTED = new Set(['submitted', 'judged']);

function isGroupGame(game) {
  return Boolean(game && game.settings && game.settings.judgingMode === GROUP);
}

function rosterOf(game) {
  if (Array.isArray(game.playerIds) && game.playerIds.length) return game.playerIds.slice();
  return (Array.isArray(game.players) ? game.players : [])
    .map((p) => p && p.userId)
    .filter(Boolean);
}

/** Task points for a list of 1..5 grades: round(mean x 2), 0..10; 0 if none. */
function pointsFor(scores) {
  if (!scores.length) return {mean: 0, points: 0};
  const mean = scores.reduce((a, b) => a + b, 0) / scores.length;
  return {mean, points: Math.min(10, Math.max(0, Math.round(mean * 2)))};
}

function isValidScore(score) {
  return Number.isInteger(score) && score >= 1 && score <= 5;
}

/**
 * Pure: what should lock for one task right now.
 *
 * @param {object} args
 * @param {object} args.game     the game document
 * @param {string} args.taskId
 * @param {object[]} args.grades the task's peer_grades docs
 * @param {Record<string, object>} args.results  uid -> ledger entry already locked for this task
 * @param {number} args.nowMs
 * @returns {null | {
 *   taskIndex: number,
 *   locks: {uid: string, points: number, mean: number, gradeCount: number}[],
 *   peerGraders: Record<string, string[]>,
 *   complete: boolean,
 *   expired: boolean,
 *   openedAt: string|null,   ISO time the 24 h window opened
 * }}
 */
function settleTask({game, taskId, grades, results, nowMs}) {
  if (!isGroupGame(game)) return null;
  const tasks = Array.isArray(game.tasks) ? game.tasks : [];
  const taskIndex = tasks.findIndex((t) => t && t.id === taskId);
  if (taskIndex < 0) return null;
  const task = tasks[taskIndex];
  const roster = rosterOf(game);
  if (!roster.length) return null;
  const inRoster = new Set(roster);

  const statuses = (task.playerStatuses && typeof task.playerStatuses === 'object') ? task.playerStatuses : {};
  const stateOf = (uid) => (statuses[uid] && statuses[uid].state) || 'not_started';
  const posted = (uid) => POSTED.has(stateOf(uid));
  const skipped = (uid) => stateOf(uid) === 'skipped';

  // Every valid grade, once per (entry, grader).
  const byTarget = new Map();
  for (const g of grades || []) {
    if (!g || g.taskId !== taskId) continue;
    if (!inRoster.has(g.graderUid) || !inRoster.has(g.targetUid)) continue;
    if (g.graderUid === g.targetUid || !isValidScore(g.score)) continue;
    if (!byTarget.has(g.targetUid)) byTarget.set(g.targetUid, new Map());
    const forTarget = byTarget.get(g.targetUid);
    if (!forTarget.has(g.graderUid)) forTarget.set(g.graderUid, g.score);
  }

  // The 24 h window opens when the task did (or at its first entry, if earlier
  // or unstamped). The current task with neither opens now, so it still expires.
  const stamped = Date.parse(task.openedAt || '');
  let openedAt = Number.isFinite(stamped) ? stamped : null;
  for (const uid of roster) {
    if (!posted(uid)) continue;
    const at = Date.parse(statuses[uid].submittedAt || '');
    if (Number.isFinite(at) && (openedAt === null || at < openedAt)) openedAt = at;
  }
  if (openedAt === null && (game.currentTaskIndex || 0) === taskIndex) openedAt = nowMs;
  const expired = openedAt !== null && nowMs - openedAt >= LOCK_AFTER_MS;

  const locked = new Set(Object.keys(results || {}));
  const locks = [];
  for (const uid of roster) {
    if (!posted(uid) || locked.has(uid)) continue;
    const given = byTarget.get(uid) || new Map();
    const required = roster.filter((p) => p !== uid && !skipped(p));
    if (!expired && !required.every((p) => given.has(p))) continue;
    const scores = [...given.values()];
    const {mean, points} = pointsFor(scores);
    locks.push({uid, points, mean, gradeCount: scores.length});
    locked.add(uid);
  }

  const complete = roster.every((uid) =>
    locked.has(uid) || skipped(uid) || (expired && !posted(uid)));

  const peerGraders = {};
  for (const [target, given] of byTarget) peerGraders[target] = [...given.keys()].sort();

  return {
    taskIndex, locks, peerGraders, complete, expired,
    openedAt: openedAt === null ? null : new Date(openedAt).toISOString(),
  };
}

/**
 * Pure: the game-document fields to write after [outcome] for [game].
 * [allResults] is every ledger entry for the game (all tasks), including the
 * ones just locked. Returns null when nothing changes.
 */
function gameUpdatesFor({game, outcome, allResults, nowIso}) {
  const tasks = (game.tasks || []).map((t) => t);
  const task = {...tasks[outcome.taskIndex]};
  const statuses = {...(task.playerStatuses || {})};
  const submissions = Array.isArray(task.submissions) ? task.submissions.slice() : [];

  for (const lock of outcome.locks) {
    const prev = statuses[lock.uid] || {playerId: lock.uid};
    statuses[lock.uid] = {...prev, playerId: lock.uid, state: 'judged', score: lock.points, scoredAt: nowIso};
    const i = submissions.findIndex((s) => s && s.userId === lock.uid);
    if (i >= 0) submissions[i] = {...submissions[i], score: lock.points, isJudged: true};
  }
  task.playerStatuses = statuses;
  task.submissions = submissions;
  task.peerGraders = outcome.peerGraders;
  if (!task.openedAt && outcome.openedAt) task.openedAt = outcome.openedAt;
  if (outcome.complete) task.status = 'completed';
  tasks[outcome.taskIndex] = task;

  const totals = {};
  for (const r of allResults) {
    if (!r || typeof r.uid !== 'string') continue;
    totals[r.uid] = (totals[r.uid] || 0) + (Number.isFinite(r.points) ? r.points : 0);
  }
  const players = (game.players || []).map((p) =>
    (p && p.userId ? {...p, totalScore: totals[p.userId] || 0} : p));

  const updates = {tasks, players};
  if (outcome.complete) {
    const allDone = tasks.length > 0 && tasks.every((t) => t && t.status === 'completed');
    if (allDone) {
      updates.status = 'completed';
    } else if ((game.currentTaskIndex || 0) === outcome.taskIndex && outcome.taskIndex < tasks.length - 1) {
      updates.currentTaskIndex = outcome.taskIndex + 1;
      const next = tasks[outcome.taskIndex + 1];
      if (next && !next.openedAt) tasks[outcome.taskIndex + 1] = {...next, openedAt: nowIso};
    }
  }

  const before = JSON.stringify({tasks: game.tasks, players: game.players});
  const after = JSON.stringify({tasks, players});
  if (before === after && !('status' in updates) && !('currentTaskIndex' in updates)) return null;
  return updates;
}

/**
 * Settle one task inside a transaction. [store.runTransaction] hands the
 * callback a `tx` with:
 *   getGame(gameId) -> object|null
 *   getGrades(gameId, taskId) -> object[]
 *   getResults(gameId) -> object[]   (every ledger entry for the game)
 *   setResult(gameId, docId, data)
 *   updateGame(gameId, fields)
 *
 * Returns {status, locks} where locks are the entries that locked in THIS run
 * (for the push), or a status saying why nothing happened.
 */
async function settleInStore({store, gameId, taskId, nowMs}) {
  return store.runTransaction(async (tx) => {
    const game = await tx.getGame(gameId);
    if (!game) return {status: 'no-game', locks: []};
    if (!isGroupGame(game)) return {status: 'not-group', locks: []};
    if (game.status !== 'inProgress') return {status: 'not-in-progress', locks: []};

    const [grades, ledger] = await Promise.all([tx.getGrades(gameId, taskId), tx.getResults(gameId)]);
    const results = {};
    for (const r of ledger) if (r && r.taskId === taskId) results[r.uid] = r;

    const outcome = settleTask({game, taskId, grades, results, nowMs});
    if (!outcome) return {status: 'no-task', locks: []};

    const nowIso = new Date(nowMs).toISOString();
    for (const lock of outcome.locks) {
      tx.setResult(gameId, resultDocId(taskId, lock.uid), {
        taskId, uid: lock.uid, points: lock.points, mean: lock.mean,
        gradeCount: lock.gradeCount, lockedAt: nowIso,
      });
    }
    const allResults = [...ledger, ...outcome.locks.map((l) => ({taskId, ...l}))];
    const updates = gameUpdatesFor({game, outcome, allResults, nowIso});
    if (updates) tx.updateGame(gameId, updates);

    const task = game.tasks[outcome.taskIndex] || {};
    return {
      status: updates ? 'settled' : 'unchanged',
      locks: outcome.locks,
      complete: outcome.complete,
      taskTitle: task.title || '',
      gameName: game.gameName || '',
    };
  });
}

/** The Admin-SDK store for settleInStore. */
function firestorePeerStore({db}) {
  const gameRef = (gameId) => db.collection(GAMES).doc(gameId);
  return {
    runTransaction(fn) {
      return db.runTransaction(async (t) => {
        const writes = [];
        const tx = {
          async getGame(gameId) {
            const snap = await t.get(gameRef(gameId));
            return snap.exists ? snap.data() : null;
          },
          async getGrades(gameId, taskId) {
            const snap = await t.get(gameRef(gameId).collection(PEER_GRADES).where('taskId', '==', taskId));
            return snap.docs.map((d) => d.data());
          },
          async getResults(gameId) {
            const snap = await t.get(gameRef(gameId).collection(PEER_RESULTS));
            return snap.docs.map((d) => d.data());
          },
          // Firestore wants every read before the first write; queue writes.
          setResult(gameId, docId, data) {
            writes.push(() => t.set(gameRef(gameId).collection(PEER_RESULTS).doc(docId), data));
          },
          updateGame(gameId, fields) {
            writes.push(() => t.update(gameRef(gameId), fields));
          },
        };
        const out = await fn(tx);
        for (const w of writes) w();
        return out;
      });
    },

    /** In-progress group games, for the scheduled settle pass. */
    async listOpenGroupGames(limit = 300) {
      const snap = await db.collection(GAMES)
        .where('settings.judgingMode', '==', GROUP)
        .where('status', '==', 'inProgress')
        .limit(limit)
        .get();
      return snap.docs.map((d) => ({id: d.id, ...d.data()}));
    },
  };
}

/**
 * Pure: which tasks of an open group game the scheduled pass should settle —
 * the current task (its 24 h clock runs even with no entries) and any other
 * not completed that has at least one entry (a skip or a leave can also be
 * the last thing a task was waiting on).
 */
function tasksToSweep(game) {
  if (!isGroupGame(game) || game.status !== 'inProgress') return [];
  const current = game.currentTaskIndex || 0;
  return (game.tasks || [])
    .filter((t, i) => t && t.status !== 'completed' && (i === current || t.openedAt ||
      Object.values(t.playerStatuses || {}).some((s) => s && POSTED.has(s.state))))
    .map((t) => t.id);
}

/** What the "your score is in" push says. Grader identities never appear. */
function scoreInNotification({gameId, taskId, taskTitle, lock}) {
  const graded = lock.gradeCount === 1 ? '1 grade' : `${lock.gradeCount} grades`;
  return {
    title: taskTitle ? `Your score for "${taskTitle}" is in` : 'Your score is in',
    body: lock.gradeCount > 0 ?
      `The crew gave you ${lock.points}/10 (${graded}, avg ${lock.mean.toFixed(1)}).` :
      'Nobody graded it in time, so it scored 0.',
    tag: `peer-${gameId}-${taskId}`,
    data: {gameId, taskId, url: '/'},
  };
}

module.exports = {
  GROUP,
  LOCK_AFTER_MS,
  PEER_GRADES,
  PEER_RESULTS,
  gradeDocId,
  resultDocId,
  isGroupGame,
  pointsFor,
  settleTask,
  gameUpdatesFor,
  settleInStore,
  firestorePeerStore,
  tasksToSweep,
  scoreInNotification,
};
