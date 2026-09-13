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

describe('storage.rules — submissions/{uid}/{day}/{slot}', function () {
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

  const DAY = '20260912';
  const path0 = `submissions/u1/${DAY}/0`;

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

  // SKIPPED — not a rules bug, an emulator limitation. Per Firebase's own
  // docs (Granular operations, core-syntax) and firebase/firebase-js-sdk#5079:
  // `create` governs ALL writes to file *contents*, including an overwrite
  // of an existing object, UNLESS the bucket has GCS Object Versioning
  // enabled, in which case a write to an existing path is correctly
  // evaluated as `update` instead. The production bucket
  // (gs://taskmaster-app-3d480.firebasestorage.app) DOES have Object
  // Versioning enabled (paired with a lifecycle rule that expires only
  // noncurrent versions after 1 day), so in production this write is denied
  // by `allow update: if false` — see the "OVERWRITE PROTECTION" note at the
  // top of storage.rules. The Firebase Storage EMULATOR does not implement
  // Object Versioning, so `resource` is always null on a content write here
  // and this same-path re-upload is always evaluated (and allowed) under the
  // `create` rule above regardless of the bucket's real versioning state.
  // Confirmed against this exact rules file: the second uploadBytes below
  // currently SUCCEEDS in the emulator. Left skipped, not deleted, because
  // there is no way to exercise the production behavior locally.
  it.skip('a second write to an already-created object is denied (create-only)', async () => {
    const storage = testEnv.authenticatedContext('u1').storage();
    await assertSucceeds(
      uploadBytes(ref(storage, path0), bytes(1024), { contentType: 'video/mp4' })
    );
    await assertFails(
      uploadBytes(ref(storage, path0), bytes(2048), { contentType: 'video/mp4' })
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

  it('anyone, even unauthenticated, can read an object', async () => {
    const owner = testEnv.authenticatedContext('u1').storage();
    await uploadBytes(ref(owner, path0), bytes(1024), { contentType: 'video/mp4' });
    const anon = testEnv.unauthenticatedContext().storage();
    await assertSucceeds(getBytes(ref(anon, path0)));
  });

  it('anyone, even unauthenticated, can list a day\'s prefix', async () => {
    const owner = testEnv.authenticatedContext('u1').storage();
    await uploadBytes(ref(owner, path0), bytes(1024), { contentType: 'video/mp4' });
    const anon = testEnv.unauthenticatedContext().storage();
    const result = await assertSucceeds(listAll(ref(anon, `submissions/u1/${DAY}`)));
    if (result.items.length !== 1) {
      throw new Error(`expected 1 item, got ${result.items.length}`);
    }
  });

  it('the owner can delete their own clip', async () => {
    const storage = testEnv.authenticatedContext('u1').storage();
    await uploadBytes(ref(storage, path0), bytes(1024), { contentType: 'video/mp4' });
    await assertSucceeds(deleteObject(ref(storage, path0)));
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
