# agent.md — taskmaster-app

## Overview
Cross-platform Flutter app for TaskCaster-style party games. Firebase backend, targets iOS/Android/Web simultaneously. Live at https://taskmaster-app-3d480.web.app

## Tech Stack
- Flutter / Dart
- Firebase (Auth, Firestore, Hosting)
- Provider / flutter_bloc state management
- Codemagic (CI/CD)

## Status (last commits)
- Web MVP. App compiles clean (was 111 analyzer errors — all fixed) and the
  full test suite is green (161 tests, incl. a headless game-loop integration
  test under `test/integration/`).
- Core loop implemented end-to-end: create → join → add tasks → start →
  submit → judge → scoreboard. (joinGame/addTasksToGame/submitTaskAnswer were
  previously no-op stubs — now implemented.)
- Quick Play live; Firebase Auth + Firestore on web; 225+ prebuilt tasks.
- Firestore rules hardened (no game hijacking / arbitrary community-task edits).
- Public games gallery: mark a game public, discover others' games, clone as template.
- Android runs on the emulator with real Firebase; iOS Firebase config still
  missing. No ads/IAP (placeholders removed). Toolchain: Flutter 3.47 stable.
- Store kit: `docs/STORE_LISTING.md` (data safety, listing copy, assets,
  blockers: account deletion, support email, keystore).
- **Next:** account deletion flow → Play internal testing; iOS Firebase
  options + bundle id; notifications (FCM).

## How to Run
```bash
flutter pub get
flutter run -d chrome    # web
flutter run -d linux     # desktop
flutter doctor           # check environment
```

## Open Tasks
- Phase 3: Reduce Friction (Async-Optimized features)
- Mobile deployment (Google Play + App Store)
- Cloud Functions (deferred, optional)
- See `DEVELOPMENT_CHECKLIST.md` — start next incomplete section

## Branch
- Main: `main`
- Sophie working branch: `sophieArborBot_firstBranch`

## Test Strategy
```bash
flutter test             # all tests
flutter test test/unit/  # unit tests only
```
- Unit tests for BLoCs and repositories
- Widget tests for UI components
- Multi-device testing: see `MULTI_DEVICE_TESTING_GUIDE.md`
- Manual: verify game creation, real-time sync, Quick Play on web
