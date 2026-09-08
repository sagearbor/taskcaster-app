# Store listing kit (Google Play + App Store)

Everything the store consoles ask for, answered from what the app actually
does as of v1.4.1. Copy from here into the consoles; keep this file in sync
when a feature changes what data the app touches.

Hosted pages (Firebase Hosting, same deploy as the web app):

| Page | URL | Source |
|---|---|---|
| Privacy policy | https://taskmaster-app-3d480.web.app/privacy/ | `web/privacy/index.html` |
| Terms of service | https://taskmaster-app-3d480.web.app/terms/ | `web/terms/index.html` |
| Delete account | https://taskmaster-app-3d480.web.app/delete-account/ | `web/delete-account/index.html` |
| Invite landing | https://taskmaster-app-3d480.web.app/join/ | `web/join/index.html` |

Both policy pages carry a `TODO(owner)` comment where a support email must be
added before submission — the consoles require a contact address on the
privacy policy page. The delete-account page has the same TODO as an
alternative to its GitHub-issues deletion-request path.

## Blockers before first submission

1. ~~**Account deletion**~~ — **Done 2026-09-08.** Settings -> Account ->
   "Delete Account" deletes `users/{uid}` (which carries `fcmTokens` as a
   field) and the `users/{uid}/friends` subcollection, then calls
   `FirebaseAuth.currentUser.delete()`; a `requires-recent-login` error is
   caught and routed to a re-auth dialog (password field for email/password
   accounts, a "Continue with Google/Apple" button otherwise) that retries
   the deletion. `web/delete-account/index.html` describes the process,
   including a no-app-installed path via GitHub issues. Proven against the
   Firebase emulators (see `test/features/auth/data/delete_account_emulator_test.dart`)
   and covered by bloc/widget tests.
2. **Support email** on the privacy, terms and delete-account pages (see above).
3. **Upload keystore** — `docs/PLAY_RELEASE.md` describes
   `~/taskmaster-upload-keystore.jks`; it is not present on this machine. If it
   is lost, generate a new one *before* the first upload (Play App Signing then
   owns the release key; the upload key can be reset later via support).
4. ~~**Target API level**~~ — **Done 2026-09-08.** `android/app/build.gradle`
   now has `targetSdk = 36` / `compileSdk = 36` (AGP 8.5.2 / Gradle 8.7
   accepted it as-is, no toolchain bump needed); a debug build installs and
   launches cleanly on the `pixel10_api35` emulator. The required 16 KB
   page-size check surfaced a real gap: ARCore core 1.43.0's own libs
   (`libarcore_sdk_c.so`, `libarcore_sdk_jni.so`) are already 16 KB-aligned,
   but **sceneview 2.2.1's transitive dependency on `filament-android`
   1.52.0 is not** — `libfilament-jni.so`, `libfilament-utils-jni.so` and
   `libgltfio-jni.so` all have 4 KB-aligned LOAD segments on the 64-bit ABIs
   Play's requirement covers (arm64-v8a, x86_64). This affects the AR Lab /
   AR mini-games only. Fixing it means bumping `io.github.sceneview` (and
   therefore Filament) to a release with 16 KB-aligned native libs — not
   done here; see `tmp/wrapups/` for the exact repro command.
5. **Firebase for iOS.** `lib/firebase_options.dart` throws `UnsupportedError`
   for iOS; the values in `ios/Runner/GoogleService-Info.plist` need to be
   copied in (or re-run `flutterfire configure --platforms=ios`). Also align
   Xcode's `PRODUCT_BUNDLE_IDENTIFIER` (`com.taskmaster.taskmasterApp`) with
   the plist's `com.sagearbor.taskcaster.app` and set `CFBundleDisplayName`
   to "TaskCaster".

## Google Play — Data safety form

Answer sheet for **Play Console → App content → Data safety**.

**Does your app collect or share any of the required user data types?** Yes.
**Is all of the user data collected by your app encrypted in transit?** Yes (TLS to Firebase).
**Do you provide a way for users to request that their data is deleted?** Yes — in-app (Settings -> Delete Account) and via the delete-account page for anyone without the app installed.

| Data type | Collected? | Shared? | Required or optional | Purpose | Notes |
|---|---|---|---|---|---|
| Personal info → Name | Yes | No | Optional (guest play needs none) | App functionality | Display name chosen by user or from Google/Apple |
| Personal info → Email address | Yes | No | Optional | App functionality, account management | Email/password, Google or Apple sign-in |
| Personal info → User IDs | Yes | No | Required | App functionality | Firebase Auth UID (anonymous for guests) |
| Photos and videos → Videos | No (links only) | No | — | — | Users paste links to videos hosted elsewhere; the app never uploads media |
| Messages → Other in-app messages | Yes | No | Optional | App functionality | Task answers, drawings (Drawing Telephone), community tasks; visible to other players in the same game |
| App activity → Other user-generated content | Yes | No | Optional | App functionality | Game names, scores, judging results |
| App activity → In-app actions | No | No | — | — | No analytics SDK |
| App info and performance → Crash logs | No | No | — | — | No Crashlytics/Sentry |
| Device or other IDs | Yes | No | Optional | App functionality | FCM push token, only if notifications are allowed |
| Location | **No** | No | — | — | `ACCESS_FINE_LOCATION` is requested only because Android requires it for Bluetooth scanning (Nearby Connections); the app never reads a location. Say so in the permission declaration if asked. |
| Contacts, Calendar, Health, Financial, Web browsing, SMS/call log, Audio, Files | No | No | — | — | |

**Data handling practices:** data is not shared with third parties; not used for
advertising; not sold. Processing occurs on Google Firebase (a processor).

**Security practices:** encrypted in transit; self-service in-app account and data deletion.

### Other Play "App content" answers

| Section | Answer |
|---|---|
| Ads | **No**, this app does not contain ads (the ad/purchase services were removed; nothing in the UI shows ads) |
| App access | Not all functionality is restricted — guest play works without an account. Provide a tester account anyway (email/password) so reviewers can test social features. |
| Content rating (IARC) | Answer "No" to violence, sexual content, drugs, gambling, profanity; **Yes** to "users can interact / share user-generated content" and "users can share location"? → **No** for location. Expected rating: Everyone / PEGI 3 with "Users Interact" descriptor. |
| Target audience | 13+ (not designed for children); do not opt into Families. |
| News app | No |
| COVID-19 contact tracing | No |
| Data safety | See table above |
| Government app | No |
| Financial features | None |
| Health | None |
| Privacy policy URL | https://taskmaster-app-3d480.web.app/privacy/ |
| Account deletion URL | https://taskmaster-app-3d480.web.app/delete-account/ |

### Declared permissions that need a justification

| Permission | Justification text |
|---|---|
| `CAMERA` | Augmented-reality mini-games render on the live camera view. Requested only when the user starts an AR game; not required to install. |
| `BLUETOOTH_*`, `NEARBY_WIFI_DEVICES`, `ACCESS_FINE_LOCATION` | Offline local multiplayer between phones in the same room via Google Nearby Connections. Location is required by Android for BLE discovery on older versions; the app does not read or store location. |
| `POST_NOTIFICATIONS` (via firebase_messaging) | Game invites and turn reminders the user opts into. |

## Google Play — Store listing

| Field | Value |
|---|---|
| App name (30) | TaskCaster Party |
| Short description (80) | Silly party games with friends: video tasks, drawing telephone, trivia, AR. |
| Category | Games → Party (or Casual) |
| Tags | party, multiplayer, drawing, trivia |
| Contact email | (owner) |
| Website | https://taskmaster-app-3d480.web.app |

**Full description (≤ 4000 chars)**

> Gather your friends, in one room or across the world, and take on ridiculous tasks. One player judges, everyone else competes.
>
> **Video tasks** — 225+ prebuilt challenges across physical, creative, mental and more. Film your attempt, paste the link, and let the judge score it. Add your own tasks or pick from the community.
>
> **Drawing Telephone** — draw, describe, draw again. Works online or completely offline between phones in the same room.
>
> **Trivia** — buzz in against your friends.
>
> **Balloon Blitz and Tower Trials** — AR mini-games on phones that support ARCore.
>
> **Clue Hunt** — one phone hides, the others hunt with warmer/colder hints.
>
> Team mode, secret missions, task modifiers, public games you can clone, and a scoreboard that reveals results one at a time.
>
> Play as a guest instantly or sign in to keep your games across devices. No ads.
>
> TaskCaster Party is an independent fan project and is not affiliated with any television programme.

## App Store Connect

| Field | Value |
|---|---|
| Name (30) | TaskCaster Party |
| Subtitle (30) | Party games with friends |
| Primary category | Games → Party |
| Secondary category | Games → Trivia |
| Age rating | 12+ (Infrequent/Mild Cartoon violence: No; Unrestricted Web Access: No; user-generated content → 12+ recommended because players exchange content) |
| Privacy policy URL | https://taskmaster-app-3d480.web.app/privacy/ |
| Sign in with Apple | Already implemented (required because Google sign-in is offered) |
| App Privacy "nutrition label" | Contact Info (email, name), Identifiers (user ID), User Content (other), Usage Data: none, Diagnostics: none — all "linked to you", none "used to track you" |
| Export compliance | Uses only standard HTTPS encryption → exempt (`ITSAppUsesNonExemptEncryption = NO` in Info.plist) |

## Assets checklist

Source icon: `assets/icons/app_icon.png` (1024×1024), adaptive foreground
`assets/icons/app_icon_foreground.png` on `#4A148C`.

| Asset | Spec | Status |
|---|---|---|
| Android launcher icons (all densities + adaptive) | generated by `dart run flutter_launcher_icons` | Done (`android/app/src/main/res/mipmap-*`) |
| Play hi-res icon | 512×512 PNG, 32-bit, no alpha needed | Export from `app_icon.png` |
| Play feature graphic | 1024×500 PNG/JPEG, no transparency | To make (purple gradient + logo + "TaskCaster Party") |
| Play phone screenshots | 2–8, 16:9 or 9:16, 320–3840 px each side | To capture (list below) |
| Play 7" / 10" tablet screenshots | optional but recommended, ≥ 1 each | Optional |
| iOS app icon | 1024×1024, no alpha | Enable `ios: true` in `flutter_launcher_icons` and regenerate |
| iOS 6.9" screenshots | 1320×2868 (portrait), 3–10 | To capture |
| iOS 6.5" screenshots | 1284×2778 or 1242×2688 | To capture (can be scaled from 6.9") |
| iPad 13" screenshots | only if the app is not iPhone-only — mark iPhone-only in Xcode to skip | Decide |

### Screenshot shot list (same order on both stores)

Capture on a Pixel-class emulator at 1080×2400 (Play) and an iPhone 16 Pro
Max simulator (iOS), light theme, with a guest account:

1. Onboarding — "Party games for everyone"
2. Home — invites section + Play
3. Play sheet — choosing a game mode
4. Game lobby — invite code + player list
5. Task view — a prebuilt task with the submit box
6. Judging screen — scoring a submission
7. Scoreboard — animated reveal
8. Drawing Telephone canvas (offline mode badge visible)

Add a short caption per screenshot in the listing (e.g. "225+ ready-made
tasks", "Draw, describe, draw again", "Judge your friends").

## Release checklist (per upload)

1. `pubspec.yaml` version bump (`1.4.1+33` → next; `+N` must increase).
2. `flutter test` green; `flutter analyze` no errors.
3. `scripts/make-release.sh` → `build/app/outputs/bundle/release/app-release.aab`
   (needs JDK 17 selected: `flutter config --jdk-dir=<jdk17>` — see
   `docs/PLAY_RELEASE.md`; Android Studio's bundled JDK 25 is too new for the
   project's Gradle 8.7).
4. Upload to **Internal testing** first; never straight to production.
5. Smoke test on the installed Play build: guest play, create game, join by
   code, Google sign-in, Apple sign-in (iOS).
