'use strict';

/**
 * WP-08 universal playback: transcode decisions, the trigger's idempotency
 * (never the same object twice) with ffmpeg mocked, and one real ffmpeg run
 * over a generated 10-bit HLG HEVC fixture (skipped when the local ffmpeg has
 * no libx265 to make the fixture with).
 */

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

process.env.MONTAGE_QUIET = process.env.MONTAGE_QUIET || '1';

const t = require('../src/transcode');
const {runFfmpeg, runFfprobe, runBinary, ffmpegPath} = require('../src/ffmpeg');
const {makeFakeFirestore} = require('./fake_firestore');

const UID = 'u1';
const NAME = `submissions/${UID}/20261105/3`;
const NOW = Date.parse('2026-11-05T12:00:00Z');
const silentLogger = {info() {}, warn() {}, error() {}};

const uploaded = (over = {}) => ({
  name: NAME,
  bucket: 'b',
  generation: '1730800000000001',
  contentType: 'video/quicktime',
  size: '5242880',
  metadata: {gameId: 'g1', taskId: 'starter-03', clipCapSeconds: '30', firebaseStorageDownloadTokens: 'tok'},
  ...over,
});

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/** In-memory clip store with the same claim semantics as firestoreClipStore. */
function fakeStore({posts = {}} = {}) {
  const clips = new Map();
  const postDocs = new Map(Object.entries(posts));
  return {
    clips,
    postDocs,
    async claim(docId, generation, nowMs, fields) {
      const existing = clips.get(docId) || null;
      const d = t.decideClaim(existing, generation, nowMs);
      if (!d.claim) return {claimed: false, reason: d.reason};
      clips.set(docId, {
        ...(existing || {createdAt: new Date(nowMs).toISOString()}),
        ...fields,
        status: 'processing',
        attempts: d.attempts,
        lockedAt: new Date(nowMs).toISOString(),
      });
      return {claimed: true, reason: d.reason};
    },
    async complete(docId, data) {
      clips.set(docId, {...clips.get(docId), ...data, lockedAt: null});
    },
    async fail(docId, error) {
      clips.set(docId, {...clips.get(docId), status: 'failed', error, lockedAt: null});
    },
    async getClip(docId) {
      return clips.get(docId) || null;
    },
    async postIdsForPath(p) {
      return [...postDocs.entries()].filter(([, d]) => d.videoStoragePath === p).map(([id]) => id);
    },
    async updatePost(id, fields) {
      if (!postDocs.has(id)) return;
      postDocs.set(id, {...postDocs.get(id), ...fields});
    },
  };
}

function fakeStorage() {
  const calls = {download: [], poster: [], replace: []};
  return {
    calls,
    async download(name, dest, generation) {
      calls.download.push({name, generation});
      fs.writeFileSync(dest, 'source-bytes');
    },
    async uploadPoster(local, dest) {
      calls.poster.push({local, dest});
    },
    async replaceInPlace(name, local, opts) {
      calls.replace.push({name, local, ...opts});
      return {generation: '1730800000000002'};
    },
    publicUrl: (p) => `https://example.test/${encodeURIComponent(p)}?alt=media`,
  };
}

/** A transcode mock that writes tiny outputs and counts its calls. */
function fakeTranscode({fail = false} = {}) {
  const fn = async (input, outDir, opts) => {
    fn.calls.push({input, opts});
    if (fail) throw new Error('ffmpeg exploded');
    const videoPath = path.join(outDir, 'clip.mp4');
    const posterPath = path.join(outDir, 'poster.jpg');
    fs.writeFileSync(videoPath, Buffer.alloc(1234));
    fs.writeFileSync(posterPath, Buffer.alloc(10));
    return {
      videoPath,
      posterPath,
      source: {codec: 'hevc', width: 1080, height: 1920, durationSeconds: 12},
      output: {codec: 'h264', width: 720, height: 1280, durationSeconds: 12.0333},
      hdr: true,
      tonemapped: true,
    };
  };
  fn.calls = [];
  return fn;
}

// ---------------------------------------------------------------------------
// Pure decisions
// ---------------------------------------------------------------------------

test('parseSubmissionPath accepts clip paths only', () => {
  assert.deepEqual(t.parseSubmissionPath('submissions/abc/20261105/0'), {uid: 'abc', day: '20261105', slot: '0'});
  assert.deepEqual(t.parseSubmissionPath('submissions/abc/guest/4'), {uid: 'abc', day: 'guest', slot: '4'});
  for (const bad of [
    'submissions/abc/20261105', 'submissions/abc/20261105/0/extra', 'transcoded/abc/20261105/0.jpg',
    'montages/g/t/finale.mp4', 'house/starter-01.mp4', '', null, 'submissions/../x/0',
  ]) {
    assert.equal(t.parseSubmissionPath(bad), null, String(bad));
  }
});

test('shouldTranscode ignores everything but a fresh player clip', () => {
  assert.equal(t.shouldTranscode(uploaded()).handle, true);
  const reasons = {
    'not-a-submission': uploaded({name: 'transcoded/u1/20261105/3.jpg', contentType: 'image/jpeg'}),
    'own-output': uploaded({contentType: 'video/mp4', metadata: {[t.MARKER]: '1'}}),
    'not-video': uploaded({contentType: 'image/png'}),
    empty: uploaded({size: '0'}),
    'too-large': uploaded({size: String(200 * 1024 * 1024)}),
  };
  for (const [reason, object] of Object.entries(reasons)) {
    assert.deepEqual(
      {handle: t.shouldTranscode(object).handle, reason: t.shouldTranscode(object).reason},
      {handle: false, reason},
    );
  }
  assert.equal(t.shouldTranscode(uploaded({name: 'montages/g/t/finale.mp4'})).reason, 'not-a-submission');
});

test('decideClaim: ready/failed are final, a fresh lock blocks, a stale lock is retaken once', () => {
  const gen = '7';
  assert.deepEqual(t.decideClaim(null, gen, NOW), {claim: true, reason: 'new', attempts: 1});
  assert.equal(t.decideClaim({status: 'ready', sourceGeneration: gen}, gen, NOW).reason, 'already-transcoded');
  assert.equal(t.decideClaim({status: 'failed', sourceGeneration: gen}, gen, NOW).reason, 'already-failed');
  const fresh = {status: 'processing', sourceGeneration: gen, attempts: 1, lockedAt: new Date(NOW - 60000).toISOString()};
  assert.equal(t.decideClaim(fresh, gen, NOW).reason, 'in-progress');
  const stale = {...fresh, lockedAt: new Date(NOW - (t.LOCK_MINUTES + 1) * 60000).toISOString()};
  assert.deepEqual(t.decideClaim(stale, gen, NOW), {claim: true, reason: 'retake-stale', attempts: 2});
  assert.equal(t.decideClaim({...stale, attempts: t.MAX_ATTEMPTS}, gen, NOW).reason, 'attempts-exhausted');
  assert.equal(t.decideClaim({...stale, sourceGeneration: '8'}, gen, NOW).reason, 'generation-mismatch');
});

test('clipCapSeconds: metadata may shorten the server cap, never lengthen it', () => {
  assert.equal(t.clipCapSeconds({}), 30);
  assert.equal(t.clipCapSeconds({clipCapSeconds: '20'}), 20);
  assert.equal(t.clipCapSeconds({clipCapSeconds: '600'}), 30);
  assert.equal(t.clipCapSeconds({clipCapSeconds: 'abc'}), 30);
  assert.equal(t.clipCapSeconds({clipCapSeconds: '0'}), 30);
});

test('fit720 caps both orientations at 720p and never upscales', () => {
  assert.deepEqual(t.fit720(3840, 2160), {width: 1280, height: 720});
  assert.deepEqual(t.fit720(1080, 1920), {width: 720, height: 1280});
  assert.deepEqual(t.fit720(2160, 3840), {width: 720, height: 1280});
  assert.deepEqual(t.fit720(640, 360), {width: 640, height: 360});
  const sq = t.fit720(1440, 1440);
  assert.deepEqual(sq, {width: 720, height: 720});
});

test('videoFilter tone-maps HDR with zscale, degrades without it, caps fps at 30', () => {
  const hlg = {colorTransfer: 'arib-std-b67', colorPrimaries: 'bt2020', fps: 59.94};
  const hdr = t.videoFilter({info: hlg, width: 720, height: 1280, zscale: true});
  assert.match(hdr, /^zscale=w=720:h=1280:t=linear/);
  assert.match(hdr, /tonemap=tonemap=hable/);
  assert.match(hdr, /zscale=t=bt709:m=bt709:r=tv,format=yuv420p/);
  assert.match(hdr, /fps=30$/);

  const pq = t.videoFilter({info: {colorTransfer: 'smpte2084', fps: 30}, width: 1280, height: 720, zscale: true});
  assert.match(pq, /tonemap/);
  assert.doesNotMatch(pq, /fps=/);

  const noZ = t.videoFilter({info: hlg, width: 720, height: 1280, zscale: false});
  assert.match(noZ, /^scale=720:1280.*out_color_matrix=bt709/);
  assert.doesNotMatch(noZ, /tonemap/);

  const sdr = t.videoFilter({info: {colorTransfer: 'bt709', fps: 30}, width: 640, height: 360, zscale: true});
  assert.match(sdr, /^scale=640:360/);
});

test('transcodeArgs: H.264 high yuv420p bt709, faststart, capped, metadata stripped', () => {
  const args = t.transcodeArgs({
    input: 'in.mov', output: 'out.mp4', maxSeconds: 30, zscale: true,
    info: {width: 1080, height: 1920, colorTransfer: 'arib-std-b67', fps: 30},
  });
  const after = (flag) => args[args.indexOf(flag) + 1];
  assert.equal(after('-c:v'), 'libx264');
  assert.equal(after('-profile:v'), 'high');
  assert.equal(after('-pix_fmt'), 'yuv420p');
  assert.equal(after('-crf'), '26');
  assert.equal(after('-color_trc'), 'bt709');
  assert.equal(after('-movflags'), '+faststart');
  assert.equal(after('-t'), '30');
  assert.equal(after('-map_metadata'), '-1');
  assert.equal(after('-c:a'), 'aac');
  assert.equal(after('-b:a'), '96k');
  assert.ok(args.includes('0:a:0?'), 'audio is optional');
  assert.equal(args[args.length - 1], 'out.mp4');
});

// ---------------------------------------------------------------------------
// Trigger: handleFinalized with ffmpeg mocked
// ---------------------------------------------------------------------------

test('a clip upload is transcoded once: poster, in-place replace, clip doc, posts patched', async () => {
  const store = fakeStore({posts: {
    p1: {mediaType: 'video', videoStoragePath: NAME, videoUrl: 'https://orig'},
    p2: {mediaType: 'video', videoStoragePath: 'submissions/u2/20261105/0'},
  }});
  const storage = fakeStorage();
  const transcode = fakeTranscode();

  const res = await t.handleFinalized(uploaded(), {store, storage, transcode, nowMs: NOW, logger: silentLogger});
  assert.equal(res.status, 'ready');
  assert.equal(transcode.calls.length, 1);
  assert.equal(transcode.calls[0].opts.maxSeconds, 30);

  assert.deepEqual(storage.calls.download, [{name: NAME, generation: '1730800000000001'}]);
  assert.equal(storage.calls.poster[0].dest, `transcoded/${UID}/20261105/3.jpg`);
  const rep = storage.calls.replace[0];
  assert.equal(rep.name, NAME, 'the original is replaced in place (its bytes are gone)');
  assert.equal(rep.ifGenerationMatch, '1730800000000001');
  assert.equal(rep.metadata[t.MARKER], '1');
  assert.equal(rep.metadata.tcHdr, '1');

  const clip = store.clips.get(`${UID}_20261105_3`);
  assert.equal(clip.status, 'ready');
  assert.equal(clip.uid, UID);
  assert.equal(clip.day, '20261105');
  assert.equal(clip.slot, '3');
  assert.equal(clip.gameId, 'g1');
  assert.ok(clip.createdAt, 'createdAt is the retention clock');
  assert.equal(clip.playbackPath, NAME);
  assert.equal(clip.posterPath, `transcoded/${UID}/20261105/3.jpg`);
  assert.equal(clip.outputBytes, 1234);
  assert.equal(clip.durationSeconds, 12.03);
  assert.equal(clip.hdr, true);

  const p1 = store.postDocs.get('p1');
  assert.equal(p1.playbackUrl, storage.publicUrl(NAME));
  assert.equal(p1.posterUrl, storage.publicUrl(`transcoded/${UID}/20261105/3.jpg`));
  assert.equal(p1.videoContentType, 'video/mp4');
  assert.equal(p1.videoBytes, 1234);
  assert.equal(p1.videoUrl, 'https://orig', 'videoUrl is left alone (it now serves the mp4)');
  assert.equal(store.postDocs.get('p2').playbackUrl, undefined, 'other posts untouched');
});

test('idempotency: a redelivered event and our own replace never transcode again', async () => {
  const store = fakeStore();
  const storage = fakeStorage();
  const transcode = fakeTranscode();
  const deps = {store, storage, transcode, nowMs: NOW, logger: silentLogger};

  assert.equal((await t.handleFinalized(uploaded(), deps)).status, 'ready');
  // At-least-once delivery: the same event again.
  assert.deepEqual(await t.handleFinalized(uploaded(), deps), {status: 'skipped', reason: 'already-transcoded'});
  // The finalize event our in-place replace produces.
  const own = uploaded({generation: '1730800000000002', contentType: 'video/mp4',
    metadata: {[t.MARKER]: '1', firebaseStorageDownloadTokens: 'tok'}});
  assert.deepEqual(await t.handleFinalized(own, deps), {status: 'skipped', reason: 'own-output'});
  // The poster upload.
  const poster = {name: `transcoded/${UID}/20261105/3.jpg`, contentType: 'image/jpeg', size: '9000', metadata: {}};
  assert.equal((await t.handleFinalized(poster, deps)).reason, 'not-a-submission');

  assert.equal(transcode.calls.length, 1);
  assert.equal(storage.calls.replace.length, 1);
});

test('idempotency: two concurrent deliveries -> exactly one transcode', async () => {
  const store = fakeStore();
  const storage = fakeStorage();
  const transcode = fakeTranscode();
  const deps = {store, storage, transcode, nowMs: NOW, logger: silentLogger};
  const results = await Promise.all([t.handleFinalized(uploaded(), deps), t.handleFinalized(uploaded(), deps)]);
  assert.deepEqual(results.map((r) => r.status).sort(), ['ready', 'skipped']);
  assert.equal(transcode.calls.length, 1);
});

test('a failed transcode is final, leaves the original alone, and is not retried', async () => {
  const store = fakeStore();
  const storage = fakeStorage();
  const bad = fakeTranscode({fail: true});
  const deps = {store, storage, transcode: bad, nowMs: NOW, logger: silentLogger};
  const res = await t.handleFinalized(uploaded(), deps);
  assert.equal(res.status, 'failed');
  assert.equal(storage.calls.replace.length, 0, 'original untouched');
  assert.equal(storage.calls.poster.length, 0);
  assert.equal(store.clips.get(`${UID}_20261105_3`).status, 'failed');

  assert.equal((await t.handleFinalized(uploaded(), deps)).reason, 'already-failed');
  assert.equal(bad.calls.length, 1);
});

test('a crashed run (stale lock) is retaken at most MAX_ATTEMPTS times in total', async () => {
  const store = fakeStore();
  const id = `${UID}_20261105_3`;
  store.clips.set(id, {
    status: 'processing', sourceGeneration: '1730800000000001', attempts: 1,
    lockedAt: new Date(NOW - 30 * 60000).toISOString(), createdAt: 'then',
  });
  const transcode = fakeTranscode();
  const res = await t.handleFinalized(uploaded(), {store, storage: fakeStorage(), transcode, nowMs: NOW, logger: silentLogger});
  assert.equal(res.status, 'ready');
  assert.equal(store.clips.get(id).createdAt, 'then', 'createdAt is set once, never moved');
  assert.equal(store.clips.get(id).attempts, 2);

  store.clips.set(id, {...store.clips.get(id), status: 'processing', lockedAt: new Date(NOW - 30 * 60000).toISOString()});
  assert.equal((await t.handleFinalized(uploaded(), {store, storage: fakeStorage(), transcode, nowMs: NOW,
    logger: silentLogger})).reason, 'attempts-exhausted');
  assert.equal(transcode.calls.length, 1);
});

test('the upload metadata can only shorten the duration cap', async () => {
  const transcode = fakeTranscode();
  await t.handleFinalized(uploaded({metadata: {clipCapSeconds: '15'}}),
    {store: fakeStore(), storage: fakeStorage(), transcode, nowMs: NOW, logger: silentLogger});
  await t.handleFinalized(uploaded({name: 'submissions/u1/20261105/4', metadata: {clipCapSeconds: '9999'}}),
    {store: fakeStore(), storage: fakeStorage(), transcode, nowMs: NOW, logger: silentLogger});
  assert.deepEqual(transcode.calls.map((c) => c.opts.maxSeconds), [15, 30]);
});

test('applyClipToPost: a post created after the transcode gets the URLs; before, nothing', async () => {
  const store = fakeStore({posts: {late: {mediaType: 'video', videoStoragePath: NAME}}});
  const post = {id: 'late', mediaType: 'video', videoStoragePath: NAME};

  assert.deepEqual(await t.applyClipToPost(post, {store}), {applied: false, reason: 'no-clip'});

  await t.handleFinalized(uploaded(), {store, storage: fakeStorage(), transcode: fakeTranscode(), nowMs: NOW,
    logger: silentLogger});
  store.postDocs.set('late', {mediaType: 'video', videoStoragePath: NAME}); // as if created now
  const res = await t.applyClipToPost(post, {store});
  assert.equal(res.applied, true);
  assert.match(store.postDocs.get('late').playbackUrl, /submissions/);

  assert.equal((await t.applyClipToPost({id: 'x', mediaType: 'photo'}, {store})).applied, false);
  assert.equal((await t.applyClipToPost({id: 'h', mediaType: 'video', videoStoragePath: 'house/starter-01.mp4'},
    {store})).applied, false);
});

test('firestoreClipStore.claim is a real transaction: a second claim is refused', async () => {
  const db = makeFakeFirestore();
  class DeleteSentinel {}
  const FieldValue = {serverTimestamp: () => 'SERVER_TS', delete: () => new DeleteSentinel()};
  const store = t.firestoreClipStore({db, FieldValue});
  const fields = {uid: UID, sourcePath: NAME};
  assert.deepEqual(await store.claim('c1', '5', NOW, fields), {claimed: true, reason: 'new'});
  assert.deepEqual(await store.claim('c1', '5', NOW, fields), {claimed: false, reason: 'in-progress'});
  const doc = db.peek('clips/c1');
  assert.equal(doc.status, 'processing');
  assert.equal(doc.createdAt, 'SERVER_TS');
  await store.complete('c1', {status: 'ready'});
  assert.equal(db.peek('clips/c1').status, 'ready');
  assert.deepEqual(await store.claim('c1', '5', NOW + 3600000, fields), {claimed: false, reason: 'already-transcoded'});
});

// ---------------------------------------------------------------------------
// Real ffmpeg: HEVC 10-bit HLG in, H.264 SDR bt709 out
// ---------------------------------------------------------------------------

async function canEncodeHevc() {
  try {
    const {stdout} = await runBinary(ffmpegPath(), ['-hide_banner', '-encoders'], {label: 'caps'});
    return /\blibx265\b/.test(stdout);
  } catch {
    return false;
  }
}

test('real ffmpeg: an HEVC HDR (HLG, 10-bit) .mov becomes 720p H.264 yuv420p bt709 + poster',
  {timeout: 180000}, async (ctx) => {
    if (!(await canEncodeHevc())) {
      ctx.skip('local ffmpeg has no libx265 to build the HEVC fixture');
      return;
    }
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'tc-transcode-test-'));
    try {
      const src = path.join(dir, 'iphone.mov');
      // An iPhone-like source: 1080x1920 portrait, 60 fps, HEVC Main10, HLG
      // BT.2020, AAC, in a QuickTime container, 3 s long.
      await runFfmpeg([
        '-f', 'lavfi', '-i', 'testsrc2=s=1080x1920:r=60:d=3',
        '-f', 'lavfi', '-i', 'sine=f=440:r=44100:d=3',
        '-map', '0:v', '-map', '1:a',
        '-vf', 'format=yuv420p10le',
        '-c:v', 'libx265', '-preset', 'ultrafast', '-x265-params', 'log-level=error',
        '-tag:v', 'hvc1',
        '-color_primaries', 'bt2020', '-color_trc', 'arib-std-b67', '-colorspace', 'bt2020nc',
        '-c:a', 'aac', '-b:a', '96k', src,
      ]);

      const out = fs.mkdtempSync(path.join(dir, 'out-'));
      const result = await t.transcodeFile(src, out, {maxSeconds: 2});
      assert.equal(result.source.codec, 'hevc');
      assert.equal(result.hdr, true);

      const {stdout} = await runFfprobe([
        '-v', 'error', '-print_format', 'json', '-show_streams', '-show_format', result.videoPath,
      ]);
      const parsed = JSON.parse(stdout);
      const v = parsed.streams.find((s) => s.codec_type === 'video');
      const a = parsed.streams.find((s) => s.codec_type === 'audio');
      assert.equal(v.codec_name, 'h264');
      assert.equal(v.profile, 'High');
      assert.equal(v.pix_fmt, 'yuv420p');
      assert.equal(v.color_transfer, 'bt709');
      assert.equal(v.color_primaries, 'bt709');
      assert.equal(v.color_space, 'bt709');
      assert.equal(v.width, 720);
      assert.equal(v.height, 1280);
      const [num, den] = String(v.avg_frame_rate).split('/').map(Number);
      assert.ok(Math.abs(num / (den || 1) - 30) < 0.5, `fps ${v.avg_frame_rate}`);
      assert.equal(a.codec_name, 'aac');
      assert.ok(Number(parsed.format.duration) <= 2.1, `duration ${parsed.format.duration} capped at 2 s`);
      assert.ok(fs.statSync(result.posterPath).size > 1000, 'poster jpg written');
      if (result.tonemapped === false) ctx.diagnostic('ffmpeg has no zscale: HDR was not tone-mapped');
    } finally {
      fs.rmSync(dir, {recursive: true, force: true});
    }
  });
