// Firestore security rules tests for the games block (WP-02): who may change
// what in a game. Each closed attack is paired with the legitimate client
// write it must NOT break. Run via test/rules/run.sh (firebase emulators:exec).
const { assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { doc, setDoc, updateDoc, getDoc } = require('firebase/firestore');
const { makeTestEnv } = require('./helpers');

const CREATOR = 'creator';
const JUDGE = 'judge';
const PLAYER = 'player';
const STRANGER = 'stranger';

function player(userId, totalScore = 0, displayName = userId) {
  return { userId, displayName, totalScore };
}

function task(statuses = {}) {
  return {
    id: 't1',
    title: 'Build a tower',
    description: 'Tallest wins',
    taskType: 'video',
    status: 'waiting_for_submissions',
    submissions: [],
    playerStatuses: statuses,
  };
}

// A game in the shape GameRepositoryImpl.createGame + joins produce.
function game(overrides = {}) {
  return {
    gameName: 'Game Night',
    creatorId: CREATOR,
    judgeId: JUDGE,
    status: 'inProgress',
    inviteCode: 'ABC234',
    createdAt: '2026-11-05T10:00:00.000',
    players: [player(CREATOR, 3), player(JUDGE), player(PLAYER, 5)],
    playerIds: [CREATOR, JUDGE, PLAYER],
    tasks: [
      task({
        [CREATOR]: { playerId: CREATOR, state: 'not_started' },
        [PLAYER]: { playerId: PLAYER, state: 'not_started' },
      }),
    ],
    settings: { maxPlayers: null },
    currentTaskIndex: 0,
    isPublic: false,
    cloneCount: 0,
    ...overrides,
  };
}

describe('firestore.rules — games', function () {
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

  async function seed(data, id = 'g1') {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `games/${id}`), data);
    });
  }

  async function current(id = 'g1') {
    let data;
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      data = (await getDoc(doc(ctx.firestore(), `games/${id}`))).data();
    });
    return data;
  }

  function as(uid) {
    return testEnv.authenticatedContext(uid).firestore();
  }

  // The fields a joiner writes (GameRepositoryImpl.joinGame).
  function joinWrite(data, uid, extra = {}) {
    return {
      players: [...data.players, { ...player(uid), ...extra }],
      playerIds: [...data.playerIds, uid],
    };
  }

  // ---- Joining --------------------------------------------------------------

  describe('join', () => {
    it('ALLOWED: a stranger joins a lobby game (appends exactly themselves)', async () => {
      const g = game({ status: 'lobby' });
      await seed(g);
      await assertSucceeds(updateDoc(doc(as(STRANGER), 'games/g1'), joinWrite(g, STRANGER)));
    });

    it('ALLOWED: a stranger joins a Quick Play game already in progress', async () => {
      const g = game({ gameKind: 'quick' });
      await seed(g);
      await assertSucceeds(updateDoc(doc(as(STRANGER), 'games/g1'), joinWrite(g, STRANGER)));
    });

    it('DENIED: joining an ordinary game that has already started', async () => {
      const g = game();
      await seed(g);
      await assertFails(updateDoc(doc(as(STRANGER), 'games/g1'), joinWrite(g, STRANGER)));
    });

    it('DENIED: joining a full game', async () => {
      const g = game({ status: 'lobby', settings: { maxPlayers: 3 } });
      await seed(g);
      await assertFails(updateDoc(doc(as(STRANGER), 'games/g1'), joinWrite(g, STRANGER)));
    });

    it('DENIED: joining with a head start (totalScore > 0)', async () => {
      const g = game({ status: 'lobby' });
      await seed(g);
      await assertFails(
        updateDoc(doc(as(STRANGER), 'games/g1'), joinWrite(g, STRANGER, { totalScore: 50 }))
      );
    });

    it('DENIED: joining as someone else', async () => {
      const g = game({ status: 'lobby' });
      await seed(g);
      await assertFails(
        updateDoc(doc(as(STRANGER), 'games/g1'), {
          players: [...g.players, player('someone-else')],
          playerIds: [...g.playerIds, STRANGER],
        })
      );
    });

    it("DENIED: a joiner rewriting another player's totalScore on the way in", async () => {
      const g = game({ status: 'lobby' });
      await seed(g);
      const players = g.players.map((p) => (p.userId === PLAYER ? { ...p, totalScore: 0 } : p));
      await assertFails(
        updateDoc(doc(as(STRANGER), 'games/g1'), {
          players: [...players, player(STRANGER)],
          playerIds: [...g.playerIds, STRANGER],
        })
      );
    });

    it('DENIED: a joiner also changing status or tasks', async () => {
      const g = game({ status: 'lobby' });
      await seed(g);
      await assertFails(
        updateDoc(doc(as(STRANGER), 'games/g1'), { ...joinWrite(g, STRANGER), status: 'completed' })
      );
      await assertFails(
        updateDoc(doc(as(STRANGER), 'games/g1'), { ...joinWrite(g, STRANGER), tasks: [] })
      );
    });
  });

  // ---- Strangers --------------------------------------------------------------

  describe('stranger (not a member)', () => {
    it("DENIED: rewriting players' totalScore", async () => {
      const g = game();
      await seed(g);
      await assertFails(
        updateDoc(doc(as(STRANGER), 'games/g1'), {
          players: g.players.map((p) => ({ ...p, totalScore: 0 })),
        })
      );
    });

    it('DENIED: rewriting tasks', async () => {
      await seed(game());
      await assertFails(updateDoc(doc(as(STRANGER), 'games/g1'), { tasks: [] }));
    });

    it('DENIED: changing status', async () => {
      await seed(game());
      await assertFails(updateDoc(doc(as(STRANGER), 'games/g1'), { status: 'completed' }));
    });

    it('DENIED: adding themselves to playerIds only (to gain member rights)', async () => {
      const g = game();
      await seed(g);
      await assertFails(
        updateDoc(doc(as(STRANGER), 'games/g1'), { playerIds: [...g.playerIds, STRANGER] })
      );
    });

    it('ALLOWED: cloning a public template bumps cloneCount by one', async () => {
      await seed(game({ isPublic: true, cloneCount: 4 }));
      await assertSucceeds(updateDoc(doc(as(STRANGER), 'games/g1'), { cloneCount: 5 }));
    });

    it('DENIED: cloneCount on a private game, or by more than one', async () => {
      await seed(game({ isPublic: false, cloneCount: 4 }), 'private');
      await assertFails(updateDoc(doc(as(STRANGER), 'games/private'), { cloneCount: 5 }));
      await seed(game({ isPublic: true, cloneCount: 4 }), 'public');
      await assertFails(updateDoc(doc(as(STRANGER), 'games/public'), { cloneCount: 100 }));
    });
  });

  // ---- Players (members who are neither judge nor creator) -------------------

  describe('player (member)', () => {
    it('ALLOWED: recording their own submission (tasks only)', async () => {
      const g = game();
      await seed(g);
      const tasks = [
        {
          ...g.tasks[0],
          playerStatuses: {
            ...g.tasks[0].playerStatuses,
            [PLAYER]: { playerId: PLAYER, state: 'submitted', submissionUrl: 'arena:p1' },
          },
        },
      ];
      await assertSucceeds(updateDoc(doc(as(PLAYER), 'games/g1'), { tasks }));
    });

    it('DENIED: self-scoring (raising their own totalScore)', async () => {
      const g = game();
      await seed(g);
      const players = g.players.map((p) => (p.userId === PLAYER ? { ...p, totalScore: 99 } : p));
      await assertFails(updateDoc(doc(as(PLAYER), 'games/g1'), { players }));
    });

    it("DENIED: zeroing another player's score", async () => {
      const g = game();
      await seed(g);
      const players = g.players.map((p) => (p.userId === CREATOR ? { ...p, totalScore: 0 } : p));
      await assertFails(updateDoc(doc(as(PLAYER), 'games/g1'), { players }));
    });

    it('DENIED: changing status, currentTaskIndex, creatorId, judgeId or inviteCode', async () => {
      await seed(game());
      const db = as(PLAYER);
      await assertFails(updateDoc(doc(db, 'games/g1'), { status: 'completed' }));
      await assertFails(updateDoc(doc(db, 'games/g1'), { currentTaskIndex: 1 }));
      await assertFails(updateDoc(doc(db, 'games/g1'), { creatorId: PLAYER }));
      await assertFails(updateDoc(doc(db, 'games/g1'), { judgeId: PLAYER }));
      await assertFails(updateDoc(doc(db, 'games/g1'), { inviteCode: 'ZZZZZZ' }));
    });

    it('ALLOWED: leaving (own entry, own uid and own statuses removed)', async () => {
      const g = game();
      await seed(g);
      const tasks = [
        { ...g.tasks[0], playerStatuses: { [CREATOR]: g.tasks[0].playerStatuses[CREATOR] } },
      ];
      await assertSucceeds(
        updateDoc(doc(as(PLAYER), 'games/g1'), {
          players: g.players.filter((p) => p.userId !== PLAYER),
          playerIds: g.playerIds.filter((id) => id !== PLAYER),
          tasks,
        })
      );
    });

    it('DENIED: "leaving" while kicking someone else or changing their score', async () => {
      const g = game();
      await seed(g);
      const db = as(PLAYER);
      // Removes the creator's entry instead of their own.
      await assertFails(
        updateDoc(doc(db, 'games/g1'), {
          players: g.players.filter((p) => p.userId !== CREATOR),
          playerIds: g.playerIds.filter((id) => id !== PLAYER),
        })
      );
      // Leaves, but rewrites the creator's score on the way out.
      await assertFails(
        updateDoc(doc(db, 'games/g1'), {
          players: g.players
            .filter((p) => p.userId !== PLAYER)
            .map((p) => (p.userId === CREATOR ? { ...p, totalScore: 0 } : p)),
          playerIds: g.playerIds.filter((id) => id !== PLAYER),
        })
      );
    });
  });

  // ---- Judge and creator -------------------------------------------------------

  describe('judge and creator', () => {
    it('ALLOWED: the judge writes scores, tasks and status', async () => {
      const g = game();
      await seed(g);
      const players = g.players.map((p) => (p.userId === PLAYER ? { ...p, totalScore: 12 } : p));
      await assertSucceeds(
        updateDoc(doc(as(JUDGE), 'games/g1'), { players, status: 'completed', currentTaskIndex: 0 })
      );
    });

    it('DENIED: the judge taking over the game, the judge chair or the invite code', async () => {
      await seed(game());
      const db = as(JUDGE);
      await assertFails(updateDoc(doc(db, 'games/g1'), { creatorId: JUDGE }));
      await assertFails(updateDoc(doc(db, 'games/g1'), { judgeId: STRANGER }));
      await assertFails(updateDoc(doc(db, 'games/g1'), { inviteCode: 'ZZZZZZ' }));
    });

    it('ALLOWED: the creator advances the game and edits settings', async () => {
      await seed(game());
      const db = as(CREATOR);
      await assertSucceeds(updateDoc(doc(db, 'games/g1'), { currentTaskIndex: 1 }));
      await assertSucceeds(updateDoc(doc(db, 'games/g1'), { isPublic: true, judgeId: PLAYER }));
      expect((await current()).judgeId === PLAYER);
    });

    it('DENIED: the creator giving the game away', async () => {
      await seed(game());
      await assertFails(updateDoc(doc(as(CREATOR), 'games/g1'), { creatorId: STRANGER }));
    });

    it('ALLOWED: the creator creates a game they own; DENIED for someone else', async () => {
      await assertSucceeds(setDoc(doc(as(CREATOR), 'games/new1'), game()));
      await assertFails(setDoc(doc(as(STRANGER), 'games/new2'), game()));
    });
  });
});

// Tiny local assertion so the file needs no assertion library.
function expect(condition) {
  if (!condition) throw new Error('expectation failed');
}
