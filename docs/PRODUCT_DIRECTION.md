# TaskCaster — Product Direction (Round 7, 2026-09-12)

**The bar:** addictively fun and funny like Taskmaster, with almost no friction,
for people who are *not* in the same room and who do not have a TV editor.

**The one-sentence loop:** *Get a task → your time starts now → snap it or write
it → it posts itself (auto-stamped, auto-captioned) → posting unlocks everyone
else's attempt → you grade theirs, they grade yours → scoreboard → next task.*

This document is decisive by design. Where a choice had to be made, it was
made; the reasoning is one line so the next person can overturn it if they
disagree.

---

## 1. Where the app is today (friction log, live web app, phone size)

Walked https://taskmaster-app-3d480.web.app as a brand-new guest on a 390×844
viewport (headless Chrome, iPhone UA). Every point between install and the
first laugh:

| # | Screen | Friction |
|---|--------|----------|
| 1 | Onboarding | A feature list ("Film silly video-task challenges, Drawing Telephone, Trivia, AR…"). Nothing funny yet. Tap 1. |
| 2 | Login | A second full screen before anything fun. Big "Play" is fine, but it is still a gate. Tap 2. |
| 3 | Home | Opens on an **empty** "Invites from friends — No invites yet" box. First thing a new player sees is a shame box. Tap 3 = Play. |
| 4 | Play sheet | **Twelve** options. Quick Play is not obviously "the fun one". Tap 4. |
| 5 | Game detail | Quick Play lands on an admin dashboard ("Epic Journey #4187 · Game in Progress · 0 of 5 tasks · Current Scores"). Not a task. Tap 5 to open the task. |
| 6 | Task | Random picks include two-person tasks for a solo guest ("Mirror each other for 30 seconds", "Guess the drawing on your back", "Film a nature documentary about a human (your camera operator)"). |
| 7 | Task | "Submit by: 23 hours remaining". No *your time starts now*. No pressure, no fun. |
| 8 | Task | "How it works: 1 Film with your camera app → 2 Upload to Google Photos or YouTube → 3 Paste the link." A three-app detour and it is the **only** submission path. This is where a first-time user quits. |
| 9 | Judging | The solo player is their own judge, 0–10. Nobody else ever sees the entry. |
| 10 | After | Nothing to come back for: no feed, no reactions, no notification of a score. |

Load time ~2–3 s; console clean apart from a web push-permission warning.
First task is **five taps deep** and the first laugh never arrives.

---

## 2. The async play loop

Taskmaster works because of three things: a devious task, a ticking clock, and
an audience that reacts. The show gets the audience by editing. We get it by
**making the audience the graders.**

### 2.1 Play (apart, on your own time)

* A task is revealed one at a time. Tapping **Start** stamps `startedAt` for
  *that player* and starts the task timer (30–180 s, per task). This is the
  "your time starts now" moment; it is per player, so nobody has to be online
  together.
* Submitting after `timer + 30 s grace` is allowed but flagged **LATE** (a red
  badge everyone sees; –1 point). Late is funnier than blocked.
* Submission types, all **in-app**, no other apps:
  * **Photo** — camera or gallery, downscaled client-side to ≤720 px JPEG
    (~60–150 KB), stored inline in the post document. No Firebase Storage,
    no cost, works on web/iOS/Android.
  * **Text** — a line or three, for wordplay tasks.
  * **Video link** — kept as an optional third path for people who want it;
    never required by a starter task.
  * *Deliberately not built:* in-app video upload. It needs Firebase Storage
    (billing-metered) and multi-MB uploads on web. Path when wanted: 15 s
    cap, 480p, Storage with a budget alarm. See §7.

### 2.2 Edit (automatic — the player never sees an editing UI)

The owner's rule: **no friction, so any edit step is done autonomously.**
There is no trim screen, no caption box, no sticker picker in the flow. Snap
→ Post. Two taps. Everything that makes a post look "edited" is computed:

* **Auto-stamp.** One of six stickers is chosen from how the attempt went,
  never by the player: submitted in the first third of the timer → `NAILED
  IT`; last third → `TECHNICALLY`; late → `SEND HELP`; text entry → `ART`;
  otherwise `NO REGRETS`. (`DON'T ASK` is reserved for entries with 3+
  viewer taps, see §2.5.)
* **Auto-caption.** The task's *twist* line and the player's elapsed time
  ("Done in 41 s") are rendered on the post; that is the caption.
* **Auto-frame.** Photos are downscaled and cropped to 4:5 client-side.
* **Optional, after posting, never blocking:** the "Posted" screen has a
  single-line "Add a word for the judge" field. Skipping it is the default.

### 2.3 Watch & grade (the Arena) — gated by doing

**You only get to see other people's attempts at a task once you have
submitted your own.** This is the core engagement loop and the first-run copy
says it plainly: *"Post yours to unlock everyone else's."* It works in the
room (everyone snaps, then everyone watches) and apart (you unlock a task's
entries whenever you get round to it).

* Every submission from a starter game is posted to the **Arena** (players in
  friend games get a "Share to the Arena" toggle, default on).
* The Arena queue shows only posts for tasks the viewer has submitted (in any
  game). A player who has done 3 of the 10 starter tasks sees entries for
  those 3. House entries obey the same gate.
* Any signed-in user, **guests included**, grades posts **1–5** against the
  task's one-line rubric ("Grade for: emotional truth of the vegetable"). One
  grade per user per post; never your own post.
* Ordering: **boosted first, then fewest grades, then newest** — so every
  post gets seen, and grading is fast (a queue, not a scroll).
* Crowd score flows back into the game: task points = `round(mean × 2)`
  (0–10), locked in when the post has **3 grades, or 1 grade and is 30 min
  old** (so a lone tester still gets a score, and a single stranger cannot
  decide a fresh post alone).
* **Grade-to-get-graded:** the "Your post is waiting for the crowd" card shows
  "Grade 3 entries to jump the queue" — grading three posts marks your own
  posts `boosted`, which sorts them to the front.

### 2.4 Watch together (same room, one phone)

For the dinner-table case: any game (friend game or starter) has a **Watch
together** button on a task once the viewer has submitted. It plays every
entry for that task back to back, full screen, from one phone — photo or text
with the auto-caption, ~6 s each, tap to advance, results card at the end.
Nothing is required from the other phones. First version tonight if time
allows; otherwise stubbed and documented.

### 2.5 Viewer taps (optional highlight signal, never required)

While watching (Arena or Watch together) a viewer can tap the screen at a
funny moment. Each tap increments `tapCount` on the post (and, for a future
video version, records the timestamp). Taps are never required, never block
playback or posting, and have no UI beyond a tiny burst. They feed ranking
(fewest-grades ties broken by taps) and the `DON'T ASK` auto-stamp; later
they steer automatic trimming. First version tonight if time allows.

### 2.6 Incentive model and where ads sit

The owner's flip: players making funny entries are **creating content**;
spectators want to watch and grade it. So:

* **Playing is free, forever.** Players are the supply.
* **Watching/grading is free with ads.** One `AdSlotCard` every 6 posts in the
  Arena queue, plus one on the scoreboard reveal. Tonight these are inert
  placeholder cards gated by `AppConfig.adsEnabled = false` — the layout and
  cadence are real, the ad SDK is not (no account/payment allowed).
* **Later, paid:** "Arena Pass" removes ads and gives priority grading for
  your own posts; "Sponsored task" is a task in the pack with a brand twist.
  Not built.

---

## 3. What changes in mechanics

| Today | New |
|-------|-----|
| Submission = external video URL | Photo / text in-app; link optional |
| Manual caption / no edit | Automatic stamp + caption from timing; no edit UI |
| Everyone's entries visible any time | **Reveal gating**: see a task's entries only after you post yours |
| No same-room playback | **Watch together**: one phone plays all entries back to back |
| 24 h deadline, no timer for most tasks | Per-player **Start** → task timer → LATE badge |
| Judge is a person (solo = yourself) | Starter pack is **crowd-judged**; friend games keep a human judge and may also share to the Arena |
| No audience | The **Arena**: watch-and-grade queue, 1–5, one grade per user |
| Score only from the judge | Crowd score locks into the game (3 grades or 1 grade + 30 min) |
| Random 5 tasks from a 127-task library | **Starter Pack**: 10 hand-written solo-at-home tasks, in a fixed order, as every new player's first game |
| Home = invites box + Play | Home = **Your next task** card → Arena → Play with friends |
| First task at tap 5 | First task at **tap 2** |

Data model (backward compatible, all new fields optional):

* `Task`: `+submissionType` (`photo|text|video|any`), `+rubric`, `+twist`.
* `Submission`: `+mediaType`, `+text`, `+caption` (auto), `+stamp` (auto), `+isLate`, `+elapsedSeconds`, `+feedPostId`.
* `GameSettings`: `+crowdJudged`, `+shareToArena`.
* `Game.gameKind = 'starter'` for the starter-pack game.
* New collection `feed_posts/{id}`: `{gameId, taskId, taskTitle, rubric,
  userId, displayName, mediaType, photoData?, text?, videoUrl?, caption,
  stamp, isLate, elapsedSeconds, createdAt, gradeCount, gradeSum, boosted,
  tapCount}` and subcollection
  `grades/{uid}: {score, createdAt}`. Rules: read signed-in; create by owner
  (`photoData` ≤ 400 KB); grade create-once by uid ≠ owner; post updates by
  non-owners may touch only `gradeCount`/`gradeSum`/`boosted` (+1 / +1..5).

---

## 4. A crisp first run

1. **Cold open** (replaces onboarding + login for new users):
   a dark card, the app name, and *the first task itself* ("Your first task,
   should you accept it…") with one button: **Start — 90 s**. The legal
   footer stays. Tapping it signs in as a guest silently, creates the
   Starter Pack game, and opens the task with the timer already running.
   **Tap 1.**
2. **Task screen**: the timer is the hero; below it two big buttons —
   **📷 Snap it** / **✍️ Write it** (depending on the task's type). **Tap 2**
   opens the camera / keyboard.
3. **Post** happens on the same tap as the capture confirm. No edit screen.
4. **Reveal**: "Posted. You've unlocked everyone else's attempt at this task."
   with a **See theirs** button into the Arena (this is where a new player
   first *laughs*, within ~90 s of install) and the *next* task teased.
5. **Home** for returning users: "Your next task" hero (task 4 of 10, timer),
   "Waiting for the crowd: 2 posts", **Arena** button, then "Play with
   friends" (the existing Play sheet, unchanged).

Copy rules: second person, imperative, one twist per task, no exclamation
marks in the UI except stamps. The judge is always "the crowd".

---

## 5. The 10 starter tasks

Every task: doable alone, at home, with a phone, in under three minutes, and
funny whether you succeed or fail. Timer is the *doing* time; the 30 s grace
applies to all. Rubric is the single line the grader sees. Twist is shown
under the task after **Start**.

| # | id | Title | Type | Timer |
|---|----|-------|------|-------|
| 1 | starter-01 | A vegetable that has just received terrible news | photo | 90 s |
| 2 | starter-02 | The tallest tower of things that were never meant to be stacked | photo | 120 s |
| 3 | starter-03 | Rename a household object | text | 60 s |
| 4 | starter-04 | Hide in plain sight | photo | 120 s |
| 5 | starter-05 | The worst sandwich that is still technically food | photo | 180 s |
| 6 | starter-06 | A famous painting, using only what is within arm's reach | photo | 180 s |
| 7 | starter-07 | A three-line horror story about your fridge | text | 90 s |
| 8 | starter-08 | Wear as many things on your head as possible | photo | 60 s |
| 9 | starter-09 | The face of someone who has just remembered the oven is on — in another country | photo | 30 s |
| 10 | starter-10 | Your autobiography | photo | 90 s |

### starter-01 — A vegetable that has just received terrible news
**Copy:** Find a vegetable. If you have no vegetables, find the most
vegetable-adjacent thing in your home and do not tell us what it is.
Photograph it at the exact moment it receives devastating news. Lighting,
angle and emotional truth all count. **Twist:** The news must be implied by
the photo alone; no text on the vegetable. **Rubric:** Emotional truth of the
vegetable. **Photo · 90 s.**

### starter-02 — The tallest tower of things that were never meant to be stacked
**Copy:** Build the tallest freestanding tower you can from objects that have
no business being stacked. It must stand on its own for the photo. A shoe
must be involved somewhere. **Twist:** Nothing in the tower may be a box.
**Rubric:** Height × how much you fear for it. **Photo · 120 s.**

### starter-03 — Rename a household object
**Copy:** Pick any object in the room. Give it the name it clearly should have
had all along, and a one-line slogan to sell it. Type both. **Twist:** The
name must not contain any part of the object's real name. **Rubric:** Would
you buy it. **Text · 60 s.**

### starter-04 — Hide in plain sight
**Copy:** Take a photo of a room with you in it. The crowd must need at least
three seconds to find you. Being fully hidden is cheating; that is just a
photo of a room. **Twist:** Some part of your face must be visible.
**Rubric:** Seconds to find you, then style points. **Photo · 120 s.**

### starter-05 — The worst sandwich that is still technically food
**Copy:** Assemble the worst sandwich you can from what is in your kitchen.
Every ingredient must be edible. Photograph it with pride and list the
ingredients in the caption. Do not eat it. We are not asking you to eat it.
**Twist:** It must be cut in half for the photo. **Rubric:** Horror, then
plausibility that it is food. **Photo · 180 s.**

### starter-06 — A famous painting, using only what is within arm's reach
**Copy:** Without moving from where you are, recreate a famous painting with
whatever you can reach. You may be in it. Name the painting in the caption.
**Twist:** No phones or screens in the picture except the one taking it.
**Rubric:** Could you name the painting before reading the caption.
**Photo · 180 s.**

### starter-07 — A three-line horror story about your fridge
**Copy:** Write a horror story about your fridge in exactly three lines. It
must be based on something actually in your fridge right now. **Twist:** The
last line must be a single word. **Rubric:** Chills, then the word.
**Text · 90 s.**

### starter-08 — Wear as many things on your head as possible
**Copy:** Balance as many objects as you can on your head. Balanced, not tied,
not held. Take the photo one moment before disaster. **Twist:** Count them in
the caption; the crowd will check. **Rubric:** Number of things × your
dignity. **Photo · 60 s.**

### starter-09 — The face of someone who has just remembered the oven is on — in another country
**Copy:** Selfie. You have just remembered that you left the oven on. You are
currently in a different country. It is 3 a.m. there. Show us every layer of
that realisation in one face. **Twist:** No hands in the photo. **Rubric:**
Number of distinct regrets visible. **Photo · 30 s.**

### starter-10 — Your autobiography
**Copy:** Hold up the cover of your autobiography. The title is the last thing
you said out loud today. Make the cover: pose, props, expression. Put the
title in the caption. **Twist:** The cover must include a review quote from a
household object. **Rubric:** Would you read it. **Photo · 90 s.**

House entries: each task ships with one seeded **house entry** in the Arena
("Greg's assistant" as the poster) so a brand-new player always has something
to grade immediately, and the Arena never looks empty. House entries are text
posts and are clearly labelled `HOUSE`.

---

## 6. Build plan for this round (what ships)

1. Models + Firestore rules + `FeedRepository` (Firestore and mock) + `ArenaBloc`.
2. Starter Pack data (§5) and `GamesBloc.StartStarterPack` (idempotent per user).
3. Task screen: Start → timer → Snap/Write → auto-stamp/caption → post; LATE badge. No edit UI.
4. Crowd score applier (client-side, owner of the solo game is its judge).
5. Cold-open first run (tap 1 = Start, tap 2 = camera/keyboard) and new Home.
6. Arena screen (queue gated by what you've submitted, 1–5 grade, ad-slot cadence, house entries, viewer taps).
6b. Watch together (first version) if time allows.
7. Full suite green, web redeploy, headless-browser verification.

## 7. Deliberately not doing tonight

* In-app video upload (cost + web upload friction; see §2.1).
* Real ads SDK or payments (owner's rule: no accounts, no payment details).
* Push notifications for "you got graded" (web push needs a VAPID key round
  trip with the owner; the model already stores everything needed).
* AI judging. The `AITaskService` hook exists; an LLM "first reaction" line
  on each post would be a strong follow-up.
* Trimming/filters and any manual editing. Stamps and captions are automatic;
  viewer taps are the future signal for automatic trimming of video.
