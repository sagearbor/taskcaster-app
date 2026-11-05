# Monetization: Free + TaskCaster Pro

TaskCaster is free to play. One optional subscription, **TaskCaster Pro**,
pays for the things that cost real money (video storage and egress, ffmpeg
transcodes and montage renders). There are **no ads** (the Play "Ads"
declaration stays **No**) and no other in-app purchases.

Implemented in audit work package WP-11 (2026-11-05). Pattern ported from
`oralhistory_timeline` (docs/SUBSCRIPTIONS.md there).

## The rule that never bends: the free loop is never blocked

The paywall never appears on cold open, invite / join, the first task,
grading, or Watch together. It appears only:

1. when a player hits a plan limit (a clip that does not fit), in a sheet
   whose **first** option is the free way out, "Post it as a photo instead";
2. from **Settings > TaskCaster Pro**.

Every screen goes through one door, `PaywallLauncher`
(`lib/features/paywall/presentation/paywall_launcher.dart`), and
`test/features/paywall/paywall_placement_test.dart` walks the cold-open,
join, first-task and grading flows with a recording launcher to prove it
stays shut, plus a source scan so no other screen can reach the paywall.

## Tiers

| | Guest (anonymous) | Free (signed in) | Pro |
|---|---|---|---|
| Price | free | free | **$5 / month** or **$25 / year** |
| Video clips | 5 in total, up to 20 s | 3 a day, up to 20 s | 15 a day, up to 60 s |
| Upload size cap | 32 MiB | 32 MiB | 96 MiB |
| Photo and text posts | yes | yes | yes |
| Create / join friend games (up to 8) | yes | yes | yes |
| Arena watch and grade | yes | yes | yes |
| Starter Pack montages (shared) | yes | yes | yes |
| Friend-game finale + moments reel | no | no | **yes, for games the Pro user hosts; every player in that game gets them** |
| Clip retention | 90 days | 90 days; favorites 1 year | while subscribed; deleted within 1 year after Pro ends |

Store products (one subscription group, "TaskCaster Pro"):

- `taskcaster_pro_monthly`: $5 / month
- `taskcaster_pro_yearly`: $25 / year

Round prices only (owner rule). RevenueCat entitlement: **`pro`**. Offering:
`default`, with the monthly and annual packages.

The tier table lives in two places that must agree:
`functions/src/plans.js` (enforced) and `lib/core/services/plans/plans.dart`
(UI only). `storage.rules` repeats the slot and size caps.

## Retention (owner rule 2026-11-05)

Data is never kept indefinitely, and no copy may say "forever" or
"unlimited storage" (`test/core/services/plans/plans_test.dart` checks).

- Free and guest clips are deleted **90 days** after upload. A "favorite"
  (spliced into a montage, or graded 4+ on average) is kept **1 year**.
- Pro clips are kept **while the subscription is active**. After it lapses
  the clips fall back to the free rules, with at least 90 days of grace to
  resubscribe, and are deleted **no later than 1 year after the lapse date**.
- **Account deletion is immediate** (`functions/src/account_deletion.js`),
  whatever the plan.

The sweep is `sweepClipRetention` (daily, 04:30 UTC,
`functions/src/retention.js`). It is cheap: every `clips/{id}` doc carries
`retainUntil`, the next moment its verdict could change, so a run is one
paged query `retainUntil <= now`. Kept clips get a new `retainUntil` (their
deadline, or the end of the paid period for an active Pro user) and leave the
result set. Clips created before WP-11 are walked once in `createdAt` order
with a cursor in `retention_state/clips`. Deleting a clip removes the Storage
object, its poster and the doc, and marks the feed posts that showed it
`videoExpired: true` (the app's player already shows its calm placeholder for
a missing clip). Each run is bounded (10 pages of 200 clips); a backlog
drains over a few days.

## How the plan reaches the server (never trust the client)

```
App (purchases_flutter)  --buy-->  App Store / Google Play
        |                                   |
        | Purchases.logIn(firebaseUid)      v
        |                              RevenueCat
        |                                   | webhook (Authorization header)
        v                                   v
 refreshEntitlement (callable) ---> users/{uid}.plan*   <--- revenuecatWebhook
                                          |
          storage.rules (firestore.get)   |   transcode trims, montage trigger,
          clip slots + size caps   <------+-----> retention sweep
```

- **Identity.** The Firebase uid is the RevenueCat app user id. The app
  re-identifies on every auth change (`PurchasesIdentitySync` in
  `lib/main.dart`). A guest must first "Continue with Apple / Google" (WP-01
  linking keeps the uid) before buying; RevenueCat is never configured for an
  anonymous uid.
- **Server-owned fields** on `users/{uid}`, written only by Cloud Functions:
  `plan`, `planExpiresAt`, `planLapsedAt`, `planSource`, `planStatus`,
  `planWillRenew`, `planBillingIssue`, `planCancelReason`, `planProductId`,
  `planPendingProductId`, `planStore`, `planEnvironment`, `planUpdatedAt`,
  `planLastEventMs`, `planLastEventType`, `usage`. `firestore.rules`
  (`serverOwnedPlanFields()`) refuses any client create or update that
  touches them.
- **Effective plan** = `plan == 'pro'` and (`planExpiresAt` is null or in the
  future). The same test runs in `functions/src/plans.js`, `storage.rules`
  and `UserPlan.fromUserDoc`, so a late EXPIRATION webhook cannot keep Pro
  alive.
- **`revenuecatWebhook`** (HTTPS) checks the `Authorization` header against
  the Secret Manager secret `REVENUECAT_WEBHOOK_AUTH` (constant-time) and maps:

  | Event | Effect |
  |---|---|
  | INITIAL_PURCHASE, RENEWAL, UNCANCELLATION, SUBSCRIPTION_EXTENDED, ... | `plan: pro` until `expiration_at_ms`, `planLapsedAt: null` |
  | CANCELLATION | stays `pro` until expiry, `planWillRenew: false` (a refund's expiry is the refund time, so it ends at once) |
  | BILLING_ISSUE | stays `pro` through the grace period |
  | PRODUCT_CHANGE | records `planPendingProductId`; plan and expiry unchanged until the renewal |
  | EXPIRATION | `plan: free`, `planLapsedAt` = expiry (starts the retention clock) |
  | TRANSFER | the old uid goes free; the new uid is refreshed over REST |

  Ignored: events older than `planLastEventMs` (retries / out of order),
  `$RCAnonymousID`-only events, other products, and any uid with no Firebase
  Auth account (a deleted account stays deleted).
- **`refreshEntitlement`** (callable, signed-in non-anonymous only) re-reads
  the subscriber from RevenueCat's REST API with `REVENUECAT_SECRET_API_KEY`.
  The app calls it after a purchase or Restore Purchases so the plan card
  flips in seconds even if the webhook is slow.
- **Enforcement points:**
  - `storage.rules`: guest `submissions/{uid}/guest/{0-4}` (anonymous auth
    only); signed in `submissions/{uid}/{today}/{0-2}` up to 32 MiB, or with
    active Pro `{0-9,a-e}` up to 96 MiB. Create-only, no client delete.
  - `onClipUploaded` (transcode) trims every clip to its uploader's plan cap
    (20 s / 60 s), read server-side; the upload's metadata can only shorten
    it.
  - `onFeedPostCreated` queues a friend-game montage only when the game's
    `creatorId` is Pro (`host-not-pro` otherwise). Starter Pack montages are
    free for everyone.
  - Future Pro-only callables use `entitlements.assertPro()`, which throws
    `resource-exhausted` with `{reason: 'plan-limit', limitKey,
    upgradePlan: 'pro'}`.

## Web

No in-app purchase on the web. The paywall shows the plan and "Pro is
available in the TaskCaster iOS and Android app". Pro bought on mobile works
on the web too, because the plan lives in Firestore. (RevenueCat Web Billing
can be added later.)

## Configuration

Public SDK keys are dart-defines (safe to ship; empty means "Pro is not
available in this build", and the free app works unchanged):

```
--dart-define=REVENUECAT_IOS_KEY=appl_xxx
--dart-define=REVENUECAT_ANDROID_KEY=goog_xxx
```

Secrets (Secret Manager, bound with `defineSecret` in `functions/src/index.js`):

```
firebase functions:secrets:set REVENUECAT_WEBHOOK_AUTH      # any long random string, also pasted into RevenueCat
firebase functions:secrets:set REVENUECAT_SECRET_API_KEY    # RevenueCat project secret key, sk_...
```

Webhook URL for RevenueCat (Project settings > Integrations > Webhooks):
`https://us-central1-taskmaster-app-3d480.cloudfunctions.net/revenuecatWebhook`,
Authorization header value = the `REVENUECAT_WEBHOOK_AUTH` secret.

Storage rules read Firestore (`firestore.get`): the first
`firebase deploy --only storage` asks to grant the Storage service agent
cross-service read access; accept it.

## Testing

- `cd functions && npm test`: `plans.test.js` (tier table, retention verdicts,
  the one-year hard cap), `revenuecat.test.js` (a fixture per event type,
  stale events, anonymous ids, deleted accounts, REST refresh),
  `retention.test.js` (paging, keepers, lapse grace, legacy walk,
  idempotency), `cost_guards.test.js` (Pro-host montages).
- `test/rules/run.sh`: `plans.test.js` (a client writing `plan: 'pro'` is
  denied; free 4th clip today denied, Pro allowed; guest 5 lifetime; expired
  Pro is free).
- `flutter test`: `test/core/services/plans/`, `test/features/paywall/`
  (paywall states on mobile / web / guest / Pro, the limit prompt, and the
  placement rules). `MockPlanRepository` and `FakePurchasesService` keep
  RevenueCat out of every test.
- Sandbox purchase: a TestFlight / Play internal build with the keys, a
  sandbox tester, buy monthly, and the Settings plan card shows Pro within
  seconds.
