# TaskCaster Party App
An unofficial, fan-made mobile and web application for playing TaskCaster-style party games with friends, whether you're in the same room or across the globe.

## 🚀 Project Status
**Live App:** https://taskmaster-app-3d480.web.app
**Current:** Web MVP — compiles clean, full test suite green (161 tests). Core
game loop (create → join → start → submit → judge → scoreboard) implemented
and integration-tested against mock services.
**Next:** Google Play internal testing, then App Store. Store-listing copy,
Data-safety answers, asset checklist and the remaining submission blockers
(account deletion, support email, keystore) live in `docs/STORE_LISTING.md`.

### Known Gaps
- **Android is wired** (`google-services.json`, real Android
  `FirebaseOptions`, launcher icons, Play application id
  `com.sagearbor.taskcaster.app`) and runs on an emulator. **iOS is not:**
  `firebase_options.dart` still throws for iOS and the Xcode bundle id does
  not match `GoogleService-Info.plist`. See `docs/MOBILE_SETUP.md`.
- **No monetization.** The old placeholder ad / in-app-purchase services were
  removed; nothing in the UI shows ads or a store. `docs/MONETIZATION.md`
  keeps the integration plan for later.
- **Account deletion** is not implemented yet — required by both stores for
  apps with sign-up (see `docs/STORE_LISTING.md`).
- **Toolchain:** Flutter 3.22.2 / Dart 3.4.3 (full suite green there).
  Newer Flutter (3.47) needs three `CardThemeData`/`DialogThemeData` renames
  in `app_theme.dart` plus Gradle 8.14 / AGP 8.11.1 / Kotlin 2.2.20 — see
  `docs/PLAY_RELEASE.md`. Android builds need a JDK 17–24: run
  `flutter config --jdk-dir=<path to JDK 17>` once if Android Studio's
  bundled JDK is newer (Flutter prefers that JDK over `JAVA_HOME`).

### For Next Development Session
Tell AI: *"Read DEVELOPMENT_CHECKLIST.md and implement the next incomplete section"*

## ✨ Features Implemented

### Core Features ✅
- **Game Creation & Management**: Create and manage party games
- **User Authentication**: Login/Register with mock auth service  
- **Real-time Gameplay**: Live task updates and score tracking
- **Remote Judging**: Designated TaskCaster awards points
- **Cross-Platform**: iOS, Android, and Web support

### Advanced Features ✅  
- **200+ Prebuilt Tasks**: Across 8 categories (Physical, Creative, Mental, etc.)
- **Team vs Team Mode**: Divide players into competing teams
- **Secret Missions**: 17 hidden individual tasks
- **Task Modifiers**: 18 random challenges that multiply points
- **Community Tasks**: Submit and browse user-generated tasks
- **Public Games Gallery**: Mark a game public and let others discover it and
  clone its task list into their own game ("Play these tasks")
- **Geo-Located Tasks**: 12 location-based challenge types
- **AR Tasks**: 7 augmented reality task types (UI ready)
- **AI Task Generation**: Smart task creation system
- **Episode Creator**: Build custom task sequences with timestamps

### Monetization
None — the app is free with no ads. See `docs/MONETIZATION.md` for the
deferred plan.

🛠️ Technology Stack
Frontend & App Logic: Flutter - For a single codebase across all platforms.

Backend Services: Firebase

Authentication: For secure user login (Google Sign-In, Email/Password).

Firestore: As the real-time NoSQL database for game state, tasks, scores, and video links.

Hosting: For deploying the web version of the app.

CI/CD & Deployment: Codemagic - To automate the build and release process for the iOS and Android app stores.

## ⚙️ Quick Start

### Prerequisites
- Flutter SDK installed ([Installation Guide](https://flutter.dev/docs/get-started/install))
- Chrome browser (for web testing) or any modern browser
- Git

### Running the App

```bash
# Clone the repository
git clone <your-repo-url>
cd taskmaster-app

# IMPORTANT: Add platform support (first time only)
flutter create --platforms=web,linux,windows .

# Install dependencies
flutter pub get

# Option 1: Run with mock services only (no Firebase needed)
flutter run -d chrome -t lib/main_mock.dart

# Option 2: Run with Firebase (requires Firebase setup)
flutter run -d chrome

# OR run on web server (opens in any browser)
flutter run -d web-server --web-port=8080 -t lib/main_mock.dart

# OR run on Linux desktop
flutter run -d linux -t lib/main_mock.dart
```

**Note**: If you get Firebase compilation errors, use `main_mock.dart` which runs the app with mock services only.

### What Works in Mock Mode
- ✅ Complete game flow from creation to scoring
- ✅ All 200+ tasks available
- ✅ User authentication (mock login)
- ✅ Team assignments with drag-and-drop
- ✅ Community task submission and browsing
- ✅ Task modifiers and secret missions
- ✅ All advanced features functional

### Production Setup (When Ready)
1. **Firebase Setup**: Configure Firebase project and run `flutterfire configure`
2. **Store listing**: follow `docs/STORE_LISTING.md` (privacy/terms pages are
   hosted at `/privacy/` and `/terms/`)
3. **Deploy**: `flutter build web` + `firebase deploy --only hosting`;
   Android via `scripts/make-release.sh` (see `docs/PLAY_RELEASE.md`)

## 📱 Platform Support
- **Web**: ✅ Fully functional, Firebase-configured, live (recommended)
- **Linux Desktop**: ✅ Platform files present (Firebase not configured)
- **Android**: ✅ Firebase-configured; runs on the `pixel10_api35` emulator
  (`flutter run -d emulator-5554`). Play release steps in `docs/PLAY_RELEASE.md`.
- **iOS**: ⚠️ `GoogleService-Info.plist` present but `firebase_options.dart`
  has no iOS block and the Xcode bundle id needs aligning. See `docs/MOBILE_SETUP.md`.
- **Windows / macOS**: ⚠️ Requires additional setup

This is an independent project created by a fan and is not affiliated with the official TaskCaster show or its creators.
