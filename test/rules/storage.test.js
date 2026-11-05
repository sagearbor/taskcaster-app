// Storage security rules tests for player video submissions
// (submissions/{uid}/{yyyyMMdd}/{slot}). Run via test/rules/run.sh
// (firebase emulators:exec).
const { assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const {
  ref,
  uploadBytes,
  deleteObject,
  listAll,
  getBytes,
} = require('firebase/storage');
const { makeTestEnv } = require('./helpers');

const MB = 1024 * 1024;

function bytes(n) {
  return new Uint8Array(n).fill(7);
}

// yyyyMMdd in UTC, the same key storage.rules builds from request.time and
// VideoPolicy.dayKey() builds on the client.
function dayKey(date) {
  const two = (n) => String(n).padStart(2, '0');
  return `${date.getUTCFullYear()}${two(date.getUTCMonth() + 1)}${two(date.getUTCDate())}`;
}

// testEnv.clearStorage() only deletes objects at the bucket ROOT (it calls
// listAll() on the root and never descends into prefixes), so nested clips
// like submissions/u1/<day>/0 survived between tests. That never mattered
// while the create rule ignored existing objects; with the `resource == null`
// no-overwrite guard it makes every later test's upload to the same slot fail.
async function clearStorageDeep(testEnv) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const walk = async (r) => {
      const { items, prefixes } = await listAll(r);
      await Promise.all(items.map((item) => deleteObject(item)));
      for (const p of prefixes) {
        // eslint-disable-next-line no-await-in-loop
        await walk(p);
      }
    };
    await walk(ref(ctx.storage()));
  });
}

describe('storage.rules — submissions/{uid}/{day}/{slot}', function () {
  this.timeout(180000);
  let testEnv;

  before(async () => {
    testEnv = await makeTestEnv();
  });

  afterEach(async () => {
    await clearStorageDeep(testEnv);
  });

  after(async () => {
    await testEnv.cleanup();
  });

  // The only writable day folder is TODAY (UTC, server clock). Computed per
  // run; a run that straddles UTC midnight could flake, which is acceptable.
  const DAY = dayKey(new Date());
  const path0 = `submissions/u1/${DAY}/0`;

  // WP-04: a made-up date used to give one uid 10 fresh slots per fake day.
  it('a fake past day (19990101) is denied, even for the owner', async () => {
    const storage = testEnv.authenticatedContext('u1').storage();
    await assertFails(
      uploadBytes(ref(storage, 'submissions/u1/19990101/0'), bytes(1024), {
        contentType: 'video/mp4',
      })
    );
  });

  it('yesterday and tomorrow are denied (only today is writable)', async () => {
    const storage = testEnv.authenticatedContext('u1').storage();
    const DAY_MS = 24 * 60 * 60 * 1000;
    for (const offset of [-DAY_MS, DAY_MS]) {
      const other = dayKey(new Date(Date.now() + offset));
      // eslint-disable-next-line no-await-in-loop
      await assertFails(
        uploadBytes(ref(storage, `submissions/u1/${other}/0`), bytes(1024), {
          contentType: 'video/mp4',
        })
      );
    }
  });

  it('today\'s slot 0 is accepted once; a second write to it is denied', async () => {
    const storage = testEnv.authenticatedContext('u3').storage();
    const p = `submissions/u3/${DAY}/0`;
    await assertSucceeds(
      uploadBytes(ref(storage, p), bytes(1024), { contentType: 'video/mp4' })
    );
    await assertFails(
      uploadBytes(ref(storage, p), bytes(2048), { contentType: 'video/mp4' })
    );
  });

  it('a deeper path under today\'s folder is denied', async () => {
    const storage = testEnv.authenticatedContext('u1').storage();
    await assertFails(
      uploadBytes(ref(storage, `submissions/u1/${DAY}/0/extra`), bytes(1024), {
        contentType: 'video/mp4',
      })
    );
  });

  it('the owner can create at submissions/u1/<day>/0 with contentType video/mp4', async () => {
    const storage = testEnv.authenticatedContext('u1').storage();
    await assertSucceeds(
      uploadBytes(ref(storage, path0), bytes(1024), { contentType: 'video/mp4' })
    );
  });

  it('a different uid cannot create under someone else\'s uid folder', async () => {
    const storage = testEnv.authenticatedContext('u2').storage();
    await assertFails(
      uploadBytes(ref(storage, path0), bytes(1024), { contentType: 'video/mp4' })
    );
  });

  it('an unauthenticated caller cannot create', async () => {
    const storage = testEnv.unauthenticatedContext().storage();
    await assertFails(
      uploadBytes(ref(storage, path0), bytes(1024), { contentType: 'video/mp4' })
    );
  });

  it('a non-digit slot (\'a\') is denied', async () => {
    const storage = testEnv.authenticatedContext('u1').storage();
    await assertFails(
      uploadBytes(ref(storage, `submissions/u1/${DAY}/a`), bytes(1024), {
        contentType: 'video/mp4',
      })
    );
  });

  it('a two-digit slot (\'10\') is denied', async () => {
    const storage = testEnv.authenticatedContext('u1').storage();
    await assertFails(
      uploadBytes(ref(storage, `submissions/u1/${DAY}/10`), bytes(1024), {
        contentType: 'video/mp4',
      })
    );
  });

  it('a non-yyyyMMdd day (\'2026-09-12\') is denied', async () => {
    const storage = testEnv.authenticatedContext('u1').storage();
    await assertFails(
      uploadBytes(ref(storage, 'submissions/u1/2026-09-12/0'), bytes(1024), {
        contentType: 'video/mp4',
      })
    );
  });

  it('a non-video contentType (image/jpeg) is denied', async () => {
    const storage = testEnv.authenticatedContext('u1').storage();
    await assertFails(
      uploadBytes(ref(storage, path0), bytes(1024), { contentType: 'image/jpeg' })
    );
  });

  it('a 33 MiB upload is denied (over the 32 MiB cap)', async () => {
    // ~33 MiB, well under the ~90 s effort budget on the local emulator.
    await assertFails(
      uploadBytes(
        ref(testEnv.authenticatedContext('u1').storage(), path0),
        bytes(33 * MB),
        { contentType: 'video/mp4' }
      )
    );
  });

  it('anyone, even unauthenticated, can get an object by its path', async () => {
    const owner = testEnv.authenticatedContext('u1').storage();
    await uploadBytes(ref(owner, path0), bytes(1024), { contentType: 'video/mp4' });
    const anon = testEnv.unauthenticatedContext().storage();
    await assertSucceeds(getBytes(ref(anon, path0)));
  });

  // WP-04: listing used to be open, so anyone could enumerate every clip.
  it('nobody can list a day, uid or submissions prefix (get only)', async () => {
    const owner = testEnv.authenticatedContext('u1').storage();
    await uploadBytes(ref(owner, path0), bytes(1024), { contentType: 'video/mp4' });
    const anon = testEnv.unauthenticatedContext().storage();
    for (const storage of [anon, owner]) {
      for (const prefix of [`submissions/u1/${DAY}`, 'submissions/u1', 'submissions']) {
        // eslint-disable-next-line no-await-in-loop
        await assertFails(listAll(ref(storage, prefix)));
      }
    }
  });

  // WP-04: owner delete used to free the slot for another upload that day.
  it('the owner cannot delete their own clip (it would free the slot)', async () => {
    const storage = testEnv.authenticatedContext('u1').storage();
    await uploadBytes(ref(storage, path0), bytes(1024), { contentType: 'video/mp4' });
    await assertFails(deleteObject(ref(storage, path0)));
    // ...and the slot is still taken.
    await assertFails(
      uploadBytes(ref(storage, path0), bytes(1024), { contentType: 'video/mp4' })
    );
  });

  it('a different uid cannot delete someone else\'s clip', async () => {
    const owner = testEnv.authenticatedContext('u1').storage();
    await uploadBytes(ref(owner, path0), bytes(1024), { contentType: 'video/mp4' });
    const other = testEnv.authenticatedContext('u2').storage();
    await assertFails(deleteObject(ref(other, path0)));
  });

  it('a path outside submissions/ is denied for everyone, even the owner', async () => {
    const OTHER_PATH = 'other/u1/file.mp4';

    // Write is denied for anyone, including the object's "owner".
    const owner = testEnv.authenticatedContext('u1').storage();
    await assertFails(
      uploadBytes(ref(owner, OTHER_PATH), bytes(1024), { contentType: 'video/mp4' })
    );

    // Seed the object bypassing rules (since no one can legitimately create
    // it) so we can prove read is ALSO denied, not just "not found".
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await uploadBytes(ref(ctx.storage(), OTHER_PATH), bytes(1024), {
        contentType: 'video/mp4',
      });
    });

    await assertFails(getBytes(ref(owner, OTHER_PATH)));
    const anon = testEnv.unauthenticatedContext().storage();
    await assertFails(getBytes(ref(anon, OTHER_PATH)));
  });
});

describe('storage.rules — house/{file}', function () {
  this.timeout(180000);
  let testEnv;

  before(async () => {
    testEnv = await makeTestEnv();
  });

  afterEach(async () => {
    await testEnv.clearStorage();
  });

  after(async () => {
    await testEnv.cleanup();
  });

  const HOUSE_PATH = 'house/starter-01.mp4';

  it('an unauthenticated caller can read a house clip', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await uploadBytes(ref(ctx.storage(), HOUSE_PATH), bytes(1024), {
        contentType: 'video/mp4',
      });
    });
    const anon = testEnv.unauthenticatedContext().storage();
    await assertSucceeds(getBytes(ref(anon, HOUSE_PATH)));
  });

  it('a signed-in user cannot create a house clip', async () => {
    const storage = testEnv.authenticatedContext('u1').storage();
    await assertFails(
      uploadBytes(ref(storage, HOUSE_PATH), bytes(1024), { contentType: 'video/mp4' })
    );
  });

  it('an unauthenticated caller cannot create a house clip', async () => {
    const storage = testEnv.unauthenticatedContext().storage();
    await assertFails(
      uploadBytes(ref(storage, HOUSE_PATH), bytes(1024), { contentType: 'video/mp4' })
    );
  });
});

describe('storage.rules — montages/{gameId}/{taskId}/{file}', function () {
  this.timeout(180000);
  let testEnv;

  before(async () => {
    testEnv = await makeTestEnv();
  });

  afterEach(async () => {
    await testEnv.clearStorage();
  });

  after(async () => {
    await testEnv.cleanup();
  });

  const MONTAGE_PATH = 'montages/game1/starter-01/finale.mp4';

  it('an unauthenticated caller can read a montage', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await uploadBytes(ref(ctx.storage(), MONTAGE_PATH), bytes(1024), {
        contentType: 'video/mp4',
      });
    });
    const anon = testEnv.unauthenticatedContext().storage();
    await assertSucceeds(getBytes(ref(anon, MONTAGE_PATH)));
  });

  it('a signed-in user cannot create a montage', async () => {
    const storage = testEnv.authenticatedContext('u1').storage();
    await assertFails(
      uploadBytes(ref(storage, MONTAGE_PATH), bytes(1024), { contentType: 'video/mp4' })
    );
  });

  it('an unauthenticated caller cannot create a montage', async () => {
    const storage = testEnv.unauthenticatedContext().storage();
    await assertFails(
      uploadBytes(ref(storage, MONTAGE_PATH), bytes(1024), { contentType: 'video/mp4' })
    );
  });
});
