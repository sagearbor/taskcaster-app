'use strict';

/**
 * Public share pages (audit WP-09): the viral loop's landing page.
 *
 *   /p/<postId>             one Arena attempt: the clip, its stamp and time,
 *                           and "Your turn — 30 s"
 *   /c/<postId>             the same attempt framed as a dare ("Sage dares
 *                           you"); what the in-app Share button sends
 *   /t/<taskId>             a public (Starter Pack) task: preview tags for
 *                           crawlers, then straight into the web cold open
 *   /f/<montageId>          THE FINALE of a task
 *   /p/<postId>/image.jpg   a photo post's picture, so og:image has a URL
 *
 * Firebase Hosting rewrites those paths here (firebase.json). Every response
 * is a ~10 KB static HTML page — no Flutter, no client Firestore — with
 * Open Graph / Twitter tags so iMessage, WhatsApp, Slack and X render the
 * poster and title, and a Cache-Control that lets the Hosting CDN absorb
 * repeat hits.
 *
 * PRIVACY. Only a post that is shareable (see [isShareablePost]) is ever
 * rendered; anything else gets the same generic 404 as a post that does not
 * exist, so a private post's existence does not leak. A page never contains a
 * uid, an email, a game id, a full name (first word of the display name
 * only) or anything from the private `games` collection. A finale is public
 * only when EVERY clip spliced into it is.
 *
 * Pure apart from the injected `store`, so all of it runs under node:test.
 */

const {starterTask} = require('./starter_tasks');

const SITE = 'https://taskmaster-app-3d480.web.app';
const APP_STORE_URL = 'https://apps.apple.com/app/id6824157028';
const APP_STORE_ID = '6824157028';
const ANDROID_PACKAGE = 'com.sagearbor.taskcaster.app';
const PLAY_URL = `https://play.google.com/store/apps/details?id=${ANDROID_PACKAGE}`;
const FALLBACK_IMAGE = `${SITE}/icons/Icon-512.png`;

/** Firestore-style ids; mirrors InviteLinks._idPattern in the app. */
const ID_RE = /^[A-Za-z0-9_-]{1,128}$/;

/** Cap on finale source posts checked (the renderer splices at most 12). */
const MAX_FINALE_SOURCES = 12;

const DEFAULT_TURN_SECONDS = 30;

const CACHE_OK = 'public, max-age=300, s-maxage=300';
const CACHE_MISS = 'public, max-age=60, s-maxage=60';

// ---------------------------------------------------------------------------
// Routing
// ---------------------------------------------------------------------------

/**
 * @param {string} path the request path, e.g. `/p/abc123`
 * @returns {null | {kind: 'post'|'challenge'|'task'|'finale'|'postImage', id: string}}
 */
function parseSharePath(path) {
  if (typeof path !== 'string') return null;
  const segments = path.split('?')[0].split('/').filter(Boolean);
  if (segments.length < 2 || segments.length > 3) return null;
  const [route, id, extra] = segments;
  if (!ID_RE.test(id)) return null;
  if (extra !== undefined) {
    return route === 'p' && extra === 'image.jpg' ? {kind: 'postImage', id} : null;
  }
  const kind = {p: 'post', c: 'challenge', t: 'task', f: 'finale'}[route];
  return kind ? {kind, id} : null;
}

// ---------------------------------------------------------------------------
// Privacy
// ---------------------------------------------------------------------------

/**
 * Whether a post may appear on a public page.
 *
 *   shareable === true   the owner said yes (the in-app Share button sets it)
 *   shareable === false  the owner said no, whatever the task
 *   absent              public only when it is public by design: a Starter
 *                        Pack attempt (shown cross-game in the Arena to
 *                        everyone) or a seeded house entry. A friend-game
 *                        post stays private until its owner shares it.
 */
function isShareablePost(post) {
  if (!post || typeof post !== 'object') return false;
  if (post.shareable === true) return true;
  if (post.shareable === false) return false;
  if (post.isHouse === true) return true;
  const task = starterTask(post.taskId);
  return task !== null && task.id === post.taskId;
}

/** "Sage Arbor" -> "Sage". Never the full name, never empty. */
function firstName(displayName) {
  const first = String(displayName || '').trim().split(/\s+/)[0] || '';
  // Strip anything that looks like an email local part before the @.
  const clean = first.includes('@') ? '' : first.slice(0, 24);
  return clean || 'Someone';
}

const httpsUrl = (value) =>
  typeof value === 'string' && /^https:\/\/[^\s"'<>]+$/.test(value) ? value : null;

/**
 * The ONLY fields of a post that reach a public page. Anything not copied
 * here (userId, gameId, graderIds, storage paths, ...) cannot leak.
 */
function publicPostView(id, post) {
  const task = starterTask(post.taskId);
  const isVideo = post.mediaType === 'video';
  const isPhoto = post.mediaType === 'photo' &&
    typeof post.photoData === 'string' && post.photoData.length > 0;
  const tapCount = Number.isFinite(post.tapCount) ? post.tapCount : 0;
  return {
    id,
    name: post.isHouse ? 'Greg\'s assistant' : firstName(post.displayName),
    taskTitle: String(post.taskTitle || (task && task.title) || 'a TaskCaster task').slice(0, 160),
    // Only a PUBLIC task id is ever echoed back (it is in the app bundle
    // anyway); a friend game's task id stays out of the page.
    starterTaskId: task ? task.id : null,
    turnSeconds: (task && task.durationSeconds) ||
      (Number.isFinite(post.timerSeconds) && post.timerSeconds > 0 ? post.timerSeconds : DEFAULT_TURN_SECONDS),
    mediaType: isVideo ? 'video' : isPhoto ? 'photo' : 'text',
    videoUrl: isVideo ? httpsUrl(post.playbackUrl) || httpsUrl(post.videoUrl) : null,
    posterUrl: isVideo ? httpsUrl(post.posterUrl) : null,
    imageUrl: isPhoto ? `${SITE}/p/${id}/image.jpg` : null,
    text: post.mediaType === 'text' || post.mediaType === 'link'
      ? String(post.text || post.caption || '').slice(0, 600)
      : null,
    caption: typeof post.caption === 'string' ? post.caption.slice(0, 200) : null,
    stamp: tapCount >= 3 ? 'DON\'T ASK' : typeof post.stamp === 'string' ? post.stamp.slice(0, 24) : null,
    elapsedSeconds: Number.isFinite(post.elapsedSeconds) && post.elapsedSeconds >= 0
      ? Math.round(post.elapsedSeconds)
      : null,
  };
}

// ---------------------------------------------------------------------------
// Links
// ---------------------------------------------------------------------------

/**
 * Where "Your turn" goes: the Flutter web app, which reads `?task=` (and
 * `?from=`, the post being answered) at startup and opens that task with
 * the clock ready to start when the camera opens. A task that is not public
 * falls back to the app's own first task.
 */
function yourTurnUrl(starterTaskId, fromPostId) {
  if (!starterTaskId) return `${SITE}/`;
  const from = fromPostId ? `&from=${encodeURIComponent(fromPostId)}` : '';
  return `${SITE}/?task=${encodeURIComponent(starterTaskId)}${from}`;
}

/** Android: open the installed app on this exact link, else the Play Store. */
function androidIntentUrl(canonicalPath) {
  return `intent://${SITE.replace('https://', '')}${canonicalPath}` +
    `#Intent;scheme=https;package=${ANDROID_PACKAGE};` +
    `S.browser_fallback_url=${encodeURIComponent(PLAY_URL)};end`;
}

// ---------------------------------------------------------------------------
// HTML
// ---------------------------------------------------------------------------

const ESCAPES = {'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', '\'': '&#39;'};
const esc = (s) => String(s === null || s === undefined ? '' : s).replace(/[&<>"']/g, (c) => ESCAPES[c]);

/** A value safe inside a <script> string literal. */
const jsString = (s) => JSON.stringify(String(s)).replace(/</g, '\\u003c');

const STYLE = `
*{box-sizing:border-box;margin:0;padding:0}
/* Colours mirror the app's tokens (lib/core/theme/app_theme.dart, app_tokens.dart). */
:root{--violet:#6D28D9;--deep:#4C1D95;--coral:#FB5779;--gold:#FBBF24;--ink:#211B33;
--bg:#17121F;--bar:#2A2150;--surface-high:#2C2542;--on:#EDE9F5;--muted:#AEA4C6}
html,body{background:var(--bg)}
body{min-height:100vh;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
color:var(--on);background:linear-gradient(165deg,var(--bg) 0%,var(--bar) 50%,var(--deep) 100%);
display:flex;justify-content:center;padding:18px 16px 28px}
main{width:100%;max-width:440px;display:flex;flex-direction:column;gap:14px}
.brand{display:flex;align-items:center;justify-content:center;gap:8px;font-weight:800;letter-spacing:3px;font-size:13px;color:var(--on);text-decoration:none}
.brand i{font-style:normal;color:var(--gold);font-size:18px}
.dare{font-size:15px;color:var(--on);text-align:center}
h1{font-size:23px;line-height:1.2;text-align:center;font-weight:800}
h1 span{color:var(--gold)}
.stage{position:relative;border-radius:22px;overflow:hidden;background:#0d0818;aspect-ratio:4/5;
box-shadow:0 22px 50px rgba(0,0,0,.5);border:1px solid rgba(255,255,255,.12)}
.stage video,.stage img{width:100%;height:100%;object-fit:cover;display:block}
.stage .text{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;padding:28px;
font-size:21px;line-height:1.4;text-align:center;white-space:pre-line;background:linear-gradient(160deg,var(--surface-high),var(--deep))}
/* Below the clip's burned-in top label band. */
.stamp{position:absolute;top:56px;right:12px;transform:rotate(8deg);background:var(--gold);color:var(--ink);
font-weight:900;font-size:15px;letter-spacing:1px;padding:7px 12px;border-radius:9px;border:3px solid var(--ink);
box-shadow:0 6px 16px rgba(0,0,0,.4);animation:slap .5s cubic-bezier(.2,1.6,.4,1) both .3s}
@keyframes slap{from{transform:rotate(-20deg) scale(2.2);opacity:0}to{transform:rotate(8deg) scale(1);opacity:1}}
.time{position:absolute;left:12px;bottom:12px;background:rgba(13,8,24,.78);color:#fff;font-weight:800;
font-variant-numeric:tabular-nums;padding:6px 10px;border-radius:10px;font-size:14px}
/* Bottom-centre: house clips burn a label into the top band (e.g.
   "HOUSE · GREG'S ASSISTANT") and a clock into the bottom-right corner; the
   elapsed chip owns bottom-left. */
.sound{position:absolute;left:50%;bottom:12px;transform:translateX(-50%);white-space:nowrap;border:0;background:rgba(13,8,24,.78);color:#fff;
font-size:13px;font-weight:700;padding:7px 11px;border-radius:10px;cursor:pointer}
.caption{font-size:14px;color:var(--muted);text-align:center;font-style:italic}
.turn{display:block;text-align:center;text-decoration:none;color:#fff;background:var(--coral);
font-size:21px;font-weight:900;padding:19px 18px;border-radius:18px;box-shadow:0 10px 28px rgba(251,87,121,.45);
animation:pulse 2.2s ease-in-out infinite 1.2s}
.turn:active{transform:scale(.98)}
@keyframes pulse{0%,100%{box-shadow:0 10px 28px rgba(251,87,121,.45)}50%{box-shadow:0 10px 38px rgba(251,87,121,.8)}}
.hint{font-size:13px;color:var(--muted);text-align:center;margin-top:-4px}
.row{display:flex;gap:10px}
.row a{flex:1;text-align:center;text-decoration:none;color:var(--on);font-weight:700;font-size:15px;
padding:13px 8px;border-radius:14px;border:1px solid rgba(255,255,255,.28);background:rgba(255,255,255,.06)}
footer{font-size:12px;color:var(--muted);text-align:center;margin-top:6px}
@media (prefers-reduced-motion:reduce){.stamp,.turn{animation:none}}
`;

/** The tiny inline script: "Open in app" per platform, tap-to-unmute. */
function pageScript(canonicalPath, redirectTo) {
  return `(function(){var ua=navigator.userAgent||'';var a=document.getElementById('open-app');
if(a){if(/android/i.test(ua)){a.href=${jsString(androidIntentUrl(canonicalPath))};}
else if(/iphone|ipad|ipod/i.test(ua)){a.href=${jsString(APP_STORE_URL)};}
else{a.style.display='none';}}
var v=document.querySelector('video'),b=document.getElementById('sound');
if(v&&b){b.onclick=function(){v.muted=!v.muted;if(!v.muted){v.currentTime=0;v.play();}b.textContent=v.muted?'\\uD83D\\uDD07 Tap for sound':'\\uD83D\\uDD0A Sound on';};}
${redirectTo ? `location.replace(${jsString(redirectTo)});` : ''}})();`;
}

/**
 * The meta block. og:video is only set for an https mp4 — iMessage and
 * WhatsApp play it inline; X/Slack fall back to og:image.
 */
function metaTags({title, description, canonical, image, video}) {
  const tags = [
    ['property', 'og:site_name', 'TaskCaster'],
    ['property', 'og:title', title],
    ['property', 'og:description', description],
    ['property', 'og:url', canonical],
    ['property', 'og:type', video ? 'video.other' : 'website'],
    ['property', 'og:image', image || FALLBACK_IMAGE],
    ['property', 'og:image:alt', title],
    ['name', 'twitter:card', image ? 'summary_large_image' : 'summary'],
    ['name', 'twitter:title', title],
    ['name', 'twitter:description', description],
    ['name', 'twitter:image', image || FALLBACK_IMAGE],
  ];
  if (video) {
    tags.push(
      ['property', 'og:video', video],
      ['property', 'og:video:secure_url', video],
      ['property', 'og:video:type', 'video/mp4'],
    );
  }
  return tags.map(([attr, key, value]) => `<meta ${attr}="${key}" content="${esc(value)}">`).join('\n');
}

function layout({title, description, canonicalPath, image, video, body, redirectTo}) {
  const canonical = `${SITE}${canonicalPath}`;
  return `<!doctype html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>${esc(title)} · TaskCaster</title>
<meta name="description" content="${esc(description)}">
<meta name="theme-color" content="#2A2150">
<meta name="apple-itunes-app" content="app-id=${APP_STORE_ID}, app-argument=${esc(canonical)}">
<link rel="canonical" href="${esc(canonical)}">
${metaTags({title, description, canonical, image, video})}
<style>${STYLE}</style>
</head><body><main>
<a class="brand" href="${SITE}/"><i>★</i>TASKCASTER</a>
${body}
<footer>Tiny ridiculous tasks. Judged by strangers. Free.</footer>
</main>
<script>${pageScript(canonicalPath, redirectTo)}</script>
</body></html>`;
}

function stageFor(view) {
  const stamp = view.stamp ? `<div class="stamp">${esc(view.stamp)}</div>` : '';
  const time = view.elapsedSeconds !== null ? `<div class="time">⏱ ${view.elapsedSeconds} s</div>` : '';
  let media;
  if (view.mediaType === 'video' && view.videoUrl) {
    const poster = view.posterUrl ? ` poster="${esc(view.posterUrl)}"` : '';
    media = `<video src="${esc(view.videoUrl)}"${poster} autoplay muted loop playsinline preload="metadata"></video>` +
      '<button class="sound" id="sound" type="button">🔇 Tap for sound</button>';
  } else if (view.mediaType === 'photo' && view.imageUrl) {
    media = `<img src="${esc(view.imageUrl)}" alt="${esc(view.taskTitle)}">`;
  } else {
    media = `<div class="text">${esc(view.text || view.caption || '…')}</div>`;
  }
  return `<div class="stage">${media}${stamp}${time}</div>`;
}

function actions({turnUrl, turnSeconds, turnLabel}) {
  return `<a class="turn" id="your-turn" href="${esc(turnUrl)}">${esc(turnLabel || `Your turn — ${turnSeconds} s`)}</a>
<p class="hint">Same task. The clock starts when your camera opens. No account needed.</p>
<div class="row"><a id="open-app" href="${esc(APP_STORE_URL)}">Open in app</a><a id="play-browser" href="${SITE}/">Play in browser</a></div>`;
}

function renderPostPage(view, {challenge}) {
  const canonicalPath = `/${challenge ? 'c' : 'p'}/${view.id}`;
  const title = `${view.name} vs. ${view.taskTitle}`;
  const verdict = [view.stamp ? `"${view.stamp}"` : null,
    view.elapsedSeconds !== null ? `in ${view.elapsedSeconds} s` : null].filter(Boolean).join(' ');
  const description = challenge
    ? `${view.name} dares you. ${verdict ? `${verdict}. ` : ''}Your turn — ${view.turnSeconds} s.`
    : `${verdict ? `${verdict}. ` : ''}Think you can do better? Your turn — ${view.turnSeconds} s.`;
  const turnUrl = yourTurnUrl(view.starterTaskId, view.id);
  const body = `${challenge ? `<p class="dare">${esc(view.name)} dares you to beat this.</p>` : ''}
<h1>${esc(view.name)} <span>vs.</span> ${esc(view.taskTitle)}</h1>
${stageFor(view)}
${view.caption && view.mediaType !== 'text' ? `<p class="caption">${esc(view.caption)}</p>` : ''}
${actions({
    turnUrl,
    turnSeconds: view.turnSeconds,
    turnLabel: view.starterTaskId ? null : `Play your own — ${DEFAULT_TURN_SECONDS} s`,
  })}`;
  return layout({
    title,
    description,
    canonicalPath,
    image: view.posterUrl || view.imageUrl,
    video: view.videoUrl,
    body,
  });
}

function renderTaskPage(task, fromPostId) {
  const turnUrl = yourTurnUrl(task.id, fromPostId);
  const body = `<p class="dare">Your task, should you accept it…</p>
<h1>${esc(task.title)}</h1>
<div class="stage" style="aspect-ratio:5/3"><div class="text">${esc(task.description)}</div></div>
${actions({turnUrl, turnSeconds: task.durationSeconds})}`;
  return layout({
    title: task.title,
    description: `${task.description} Your turn — ${task.durationSeconds} s.`,
    canonicalPath: `/t/${task.id}`,
    image: null,
    video: null,
    body,
    // People go straight in; crawlers (no JS) read the tags above.
    redirectTo: turnUrl,
  });
}

function renderFinalePage(id, {taskTitle, finaleUrl, posterUrl, starterTaskId, turnSeconds}) {
  const view = {
    mediaType: 'video', videoUrl: finaleUrl, posterUrl, taskTitle, stamp: null, elapsedSeconds: null,
  };
  const title = `THE FINALE: ${taskTitle}`;
  const body = `<p class="dare">Every attempt. The last two seconds of each.</p>
<h1><span>THE FINALE</span><br>${esc(taskTitle)}</h1>
${stageFor(view)}
${actions({
    turnUrl: yourTurnUrl(starterTaskId, null),
    turnSeconds,
    turnLabel: starterTaskId ? null : `Play your own — ${DEFAULT_TURN_SECONDS} s`,
  })}`;
  return layout({
    title,
    description: `Everyone tried "${taskTitle}". Watch how it ended. Your turn — ${turnSeconds} s.`,
    canonicalPath: `/f/${id}`,
    image: posterUrl,
    video: finaleUrl,
    body,
  });
}

function renderNotFound() {
  return layout({
    title: 'Nothing to see here',
    description: 'This one is private, or it has gone. Play a task instead.',
    canonicalPath: '/',
    image: null,
    video: null,
    body: `<h1>This one's private <span>(or gone)</span></h1>
<div class="stage" style="aspect-ratio:5/3"><div class="text">🙈</div></div>
${actions({turnUrl: `${SITE}/`, turnSeconds: DEFAULT_TURN_SECONDS, turnLabel: `Play a task — ${DEFAULT_TURN_SECONDS} s`})}`,
  });
}

// ---------------------------------------------------------------------------
// Request handling
// ---------------------------------------------------------------------------

const SECURITY_HEADERS = {
  'X-Content-Type-Options': 'nosniff',
  'Referrer-Policy': 'strict-origin-when-cross-origin',
  // Shared user content: link previews yes, search engines no.
  'X-Robots-Tag': 'noindex',
};

const html = (status, body) => ({
  status,
  headers: {
    'Content-Type': 'text/html; charset=utf-8',
    'Cache-Control': status === 200 ? CACHE_OK : CACHE_MISS,
    ...SECURITY_HEADERS,
  },
  body,
});

const notFound = () => html(404, renderNotFound());

/**
 * @param {{path: string, query?: object, store: {
 *   getPost(id: string): Promise<object|null>,
 *   getMontage(id: string): Promise<object|null>,
 * }}} req
 * @returns {Promise<{status: number, headers: object, body: string|Buffer}>}
 */
async function handleShareRequest({path, query = {}, store}) {
  const route = parseSharePath(path);
  if (!route) return notFound();

  if (route.kind === 'task') {
    const task = starterTask(route.id);
    if (!task) return notFound();
    const from = typeof query.from === 'string' && ID_RE.test(query.from) ? query.from : null;
    return html(200, renderTaskPage(task, from));
  }

  if (route.kind === 'finale') return finale(route.id, store);

  const post = await store.getPost(route.id);
  if (!isShareablePost(post)) return notFound();

  if (route.kind === 'postImage') {
    if (post.mediaType !== 'photo' || typeof post.photoData !== 'string' || !post.photoData) {
      return notFound();
    }
    return {
      status: 200,
      headers: {'Content-Type': 'image/jpeg', 'Cache-Control': CACHE_OK, ...SECURITY_HEADERS},
      body: Buffer.from(post.photoData, 'base64'),
    };
  }

  const view = publicPostView(route.id, post);
  return html(200, renderPostPage(view, {challenge: route.kind === 'challenge'}));
}

async function finale(id, store) {
  const montage = await store.getMontage(id);
  const finaleUrl = montage && httpsUrl(montage.finaleUrl);
  if (!finaleUrl) return notFound();

  // Public only when every clip in it is: one private friend-game clip
  // spliced in keeps the whole finale private.
  const sourceIds = Array.isArray(montage.sourcePostIds) ? montage.sourcePostIds : [];
  if (!sourceIds.length || sourceIds.length > MAX_FINALE_SOURCES) return notFound();
  const posts = await Promise.all(
    sourceIds.map((sid) => (typeof sid === 'string' && ID_RE.test(sid) ? store.getPost(sid) : null)),
  );
  if (!posts.every(isShareablePost)) return notFound();

  const task = starterTask(montage.taskId);
  const poster = posts.map((p) => httpsUrl(p.posterUrl)).find(Boolean) || null;
  return html(200, renderFinalePage(id, {
    taskTitle: String(montage.taskTitle || (task && task.title) || 'a TaskCaster task').slice(0, 160),
    finaleUrl,
    posterUrl: poster,
    starterTaskId: task ? task.id : null,
    turnSeconds: task ? task.durationSeconds : DEFAULT_TURN_SECONDS,
  }));
}

/**
 * The HTTPS function's shape: tiny and cheap. Scale to zero; one 256 MiB
 * instance serves 40 requests at once, and the Hosting CDN caches each page
 * (s-maxage) so a viral link costs a handful of invocations, not thousands.
 */
const FUNCTION_OPTS = {
  region: 'us-central1',
  memory: '256MiB',
  cpu: 1,
  concurrency: 40,
  minInstances: 0,
  maxInstances: 10,
  timeoutSeconds: 15,
};

/** The Express-style handler for `onRequest`. `db` is a () => Firestore. */
function httpHandler(db, logger) {
  return async (req, res) => {
    let out;
    try {
      out = await handleShareRequest({path: req.path, query: req.query, store: firestoreShareStore(db())});
    } catch (err) {
      logger.error('share: render failed', {path: req.path, error: err.message});
      res.status(500).set('Cache-Control', 'no-store').send('Something went wrong.');
      return;
    }
    res.status(out.status).set(out.headers).send(out.body);
  };
}

/** The Admin SDK side of [handleShareRequest]'s store. */
function firestoreShareStore(db) {
  const read = async (collection, id) => {
    const snap = await db.collection(collection).doc(id).get();
    return snap.exists ? snap.data() : null;
  };
  return {
    getPost: (id) => read('feed_posts', id),
    getMontage: (id) => read('montages', id),
  };
}

module.exports = {
  SITE,
  CACHE_OK,
  parseSharePath,
  isShareablePost,
  firstName,
  publicPostView,
  yourTurnUrl,
  handleShareRequest,
  firestoreShareStore,
  FUNCTION_OPTS,
  httpHandler,
};
