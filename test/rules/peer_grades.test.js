// Firestore security rules tests for WP-13 friend-game peer grades:
// games/{gameId}/peer_grades/{taskId}__{targetUid}__{graderUid}. Each closed
// attack is paired with the legitimate client write it must not break.
// Run via test/rules/run.sh (firebase emulators:exec).
const { assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const {
  doc, setDoc, getDoc, updateDoc, deleteDoc, serverTimestamp,
} = require('firebase/firestore');
const { makeTestEnv } = require('./helpers');

const ALICE = 'alice'; // creator, plays
const BOB = 'bob';
const CARA = 'cara';
const STRANGER = 'stranger';

function player(userId, totalScore = 0) {
  return { userId, displayName: userId, totalScore };
}

function status(playerId, state) {
  return { playerId, state, submittedAt: state === 'not_started' ? null : '2026-11-05T10:00:00.000' };
}

// A group-graded game: Alice and Bob have posted task t1, Cara has not.
function game(overrides = {}) {
  return {
    gameName: 'Friday',
    creatorId: ALICE,
    judgeId: '',
    status: 'inProgress',
    inviteCode: 'ABC234',
    createdAt: '2026-11-05T10:00:00.000',
    players: [player(ALICE), player(BOB), player(CARA)],
    playerIds: [ALICE, BOB, CARA],
    tasks: [{
      id: 't1',
      title: 'Egg race',
      description: '',
      taskType: 'video',
      status: 'waiting_for_submissions',
      submissions: [],
      playerStatuses: {
        [ALICE]: status(ALICE, 'submitted'),
        [BOB]: status(BOB, 'submitted'),
        [CARA]: status(CARA, 'not_started'),
      },
    }],
    settings: { judgingMode: 'group', maxPlayers: null },
    currentTaskIndex: 0,
    ...overrides,
  };
}

function grade(grader, target, score = 4, extra = {}) {
  return {
    taskId: 't1',
    taskIndex: 0,
    targetUid: target,
    graderUid: grader,
    score,
    createdAt: serverTimestamp(),
    ...extra,
  };
}

const gradePath = (target, grader, taskId = 't1') =>
  `games/g1/peer_grades/${taskId}__${target}__${grader}`;

describe('firestore.rules — friend-game peer grades (WP-13)', function () {
  this.timeout(60000);
  let testEnv;

  before(async () => {
    testEnv = await makeTestEnv();
  });

  afterEach(async () => {
    await testEnv.clearFirestore();
  });

  after(async () => {
    await testEnv.cleanup();
  });

  async function seed(data = game()) {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'games/g1'), data);
    });
  }

  async function seedDoc(path, data) {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), path), data);
    });
  }

  function as(uid) {
    return testEnv.authenticatedContext(uid).firestore();
  }

  // ---- The legitimate path --------------------------------------------------

  it('ALLOWED: a player who posted grades another posted entry, as themselves', async () => {
    await seed();
    await assertSucceeds(setDoc(doc(as(BOB), gradePath(ALICE, BOB)), grade(BOB, ALICE, 4)));
  });

  it('ALLOWED: a grader whose own entry has already locked (judged) still grades', async () => {
    const g = game();
    g.tasks[0].playerStatuses[BOB].state = 'judged';
    await seed(g);
    await assertSucceeds(setDoc(doc(as(BOB), gradePath(ALICE, BOB)), grade(BOB, ALICE, 5)));
  });

  it('ALLOWED: the grader reads back their own grade', async () => {
    await seed();
    await seedDoc(gradePath(ALICE, BOB), { ...grade(BOB, ALICE), createdAt: new Date() });
    await assertSucceeds(getDoc(doc(as(BOB), gradePath(ALICE, BOB))));
  });

  // ---- Self, twice, impersonation -------------------------------------------

  it('DENIED: grading yourself', async () => {
    await seed();
    await assertFails(setDoc(doc(as(BOB), gradePath(BOB, BOB)), grade(BOB, BOB, 5)));
  });

  it('DENIED: grading the same entry twice (the second write is an update)', async () => {
    await seed();
    await assertSucceeds(setDoc(doc(as(BOB), gradePath(ALICE, BOB)), grade(BOB, ALICE, 1)));
    await assertFails(setDoc(doc(as(BOB), gradePath(ALICE, BOB)), grade(BOB, ALICE, 5)));
    await assertFails(updateDoc(doc(as(BOB), gradePath(ALICE, BOB)), { score: 5 }));
  });

  it('DENIED: withdrawing a grade', async () => {
    await seed();
    await seedDoc(gradePath(ALICE, BOB), { ...grade(BOB, ALICE), createdAt: new Date() });
    await assertFails(deleteDoc(doc(as(BOB), gradePath(ALICE, BOB))));
  });

  it('DENIED: grading under someone else\'s uid (body or doc id)', async () => {
    await seed();
    // Bob writes a doc claiming Alice graded... Alice? No: claims Cara graded Alice.
    await assertFails(setDoc(doc(as(BOB), gradePath(ALICE, CARA)), grade(CARA, ALICE, 1)));
    // Body says Bob, id says Cara.
    await assertFails(setDoc(doc(as(BOB), gradePath(ALICE, CARA)), grade(BOB, ALICE, 1)));
  });

  it('DENIED: a doc id that does not match the grade (a second grade under a new id)', async () => {
    await seed();
    await assertFails(setDoc(doc(as(BOB), `games/g1/peer_grades/t1__${ALICE}__${BOB}__again`), grade(BOB, ALICE, 5)));
  });

  // ---- Gating -----------------------------------------------------------------

  it('DENIED: grading before you have posted your own entry', async () => {
    await seed();
    await assertFails(setDoc(doc(as(CARA), gradePath(ALICE, CARA)), grade(CARA, ALICE, 5)));
  });

  it('DENIED: grading an entry that has not been posted', async () => {
    await seed();
    await assertFails(setDoc(doc(as(BOB), gradePath(CARA, BOB)), grade(BOB, CARA, 1)));
  });

  it('DENIED: grading an entry whose score has already locked', async () => {
    const g = game();
    g.tasks[0].playerStatuses[ALICE].state = 'judged';
    await seed(g);
    await assertFails(setDoc(doc(as(BOB), gradePath(ALICE, BOB)), grade(BOB, ALICE, 1)));
  });

  it('DENIED: a stranger grading', async () => {
    const g = game();
    g.tasks[0].playerStatuses[STRANGER] = status(STRANGER, 'submitted');
    await seed(g);
    await assertFails(setDoc(doc(as(STRANGER), gradePath(ALICE, STRANGER)), grade(STRANGER, ALICE, 1)));
  });

  it('DENIED: peer grades in a judge-mode game (and in one without the field)', async () => {
    await seed(game({ settings: { judgingMode: 'judge' } }));
    await assertFails(setDoc(doc(as(BOB), gradePath(ALICE, BOB)), grade(BOB, ALICE, 4)));
    await seed(game({ settings: { maxPlayers: null } }));
    await assertFails(setDoc(doc(as(BOB), gradePath(ALICE, BOB)), grade(BOB, ALICE, 4)));
  });

  it('DENIED: grading in a finished game', async () => {
    await seed(game({ status: 'completed' }));
    await assertFails(setDoc(doc(as(BOB), gradePath(ALICE, BOB)), grade(BOB, ALICE, 4)));
  });

  it('DENIED: a score outside 1..5, a non-int, extra fields, a client clock', async () => {
    await seed();
    const ref = () => doc(as(BOB), gradePath(ALICE, BOB));
    await assertFails(setDoc(ref(), grade(BOB, ALICE, 0)));
    await assertFails(setDoc(ref(), grade(BOB, ALICE, 6)));
    await assertFails(setDoc(ref(), grade(BOB, ALICE, 4.5)));
    await assertFails(setDoc(ref(), grade(BOB, ALICE, 4, { points: 10 })));
    await assertFails(setDoc(ref(), grade(BOB, ALICE, 4, { createdAt: new Date('2030-01-01') })));
  });

  it('DENIED: a taskIndex that points at a different task', async () => {
    const g = game();
    g.tasks.push({ ...g.tasks[0], id: 't2' });
    await seed(g);
    await assertFails(setDoc(doc(as(BOB), gradePath(ALICE, BOB)), grade(BOB, ALICE, 4, { taskIndex: 1 })));
  });

  // ---- Reading and tampering ---------------------------------------------------

  it('DENIED: reading someone else\'s grade (grades are anonymous)', async () => {
    await seed();
    await seedDoc(gradePath(ALICE, BOB), { ...grade(BOB, ALICE), createdAt: new Date() });
    await assertFails(getDoc(doc(as(ALICE), gradePath(ALICE, BOB))));
  });

  it('DENIED: writing the server\'s score ledger; members may read it', async () => {
    await seed();
    await assertFails(setDoc(doc(as(ALICE), 'games/g1/peer_results/t1__alice'), { uid: ALICE, points: 10 }));
    await seedDoc('games/g1/peer_results/t1__alice', { taskId: 't1', uid: ALICE, points: 8 });
    await assertSucceeds(getDoc(doc(as(BOB), 'games/g1/peer_results/t1__alice')));
    await assertFails(getDoc(doc(as(STRANGER), 'games/g1/peer_results/t1__alice')));
  });

  it('DENIED: a player tampering with others\' scores on the game doc', async () => {
    const g = game();
    await seed(g);
    const players = [player(ALICE), player(BOB, 0), player(CARA, 0)];
    players[1].totalScore = 50;
    await assertFails(updateDoc(doc(as(BOB), 'games/g1'), { players }));
  });

  it('DENIED: the creator rewriting scores in a started group game', async () => {
    await seed();
    const players = [player(ALICE, 99), player(BOB), player(CARA)];
    await assertFails(updateDoc(doc(as(ALICE), 'games/g1'), { players }));
  });

  it('ALLOWED: the creator still edits a started group game\'s other fields (e.g. adds a task)', async () => {
    const g = game();
    await seed(g);
    await assertSucceeds(updateDoc(doc(as(ALICE), 'games/g1'), {
      tasks: [...g.tasks, { ...g.tasks[0], id: 't2', playerStatuses: {} }],
    }));
  });

  it('ALLOWED: the creator still sets up the roster of a group game in the lobby (rematch)', async () => {
    await seed(game({ status: 'lobby' }));
    await assertSucceeds(updateDoc(doc(as(ALICE), 'games/g1'), {
      players: [player(ALICE), player(BOB), player(CARA), player('dan')],
      playerIds: [ALICE, BOB, CARA, 'dan'],
    }));
  });
});
