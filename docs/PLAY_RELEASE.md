# Google Play release (Android)

The app is configured for Google Play internal testing, mirroring the
`fitRival` setup.

## What's already set up
- **Application id:** `com.sagearbor.taskcaster.app` (permanent once published)
- **App name:** "TaskCaster Party" (`android:label`)
- **Launcher icon:** gold star on purple, generated via `flutter_launcher_icons`
  from `assets/icons/app_icon.png` (regenerate with `dart run flutter_launcher_icons`)
- **SDK levels:** `minSdk 23` (Firebase requirement), `targetSdk 35`, `compileSdk 35`, Java 17
- **Release signing:** `android/app/build.gradle` loads `android/key.properties`
  (gitignored). If it's missing, release builds fall back to debug signing.

## Upload keystore
A keystore was generated at:

```
~/taskmaster-upload-keystore.jks   (alias: taskmaster)
```

Its credentials live in **`android/key.properties`** (gitignored — never
committed). 

> ⚠️ **Back up the keystore.** Copy `~/taskmaster-upload-keystore.jks` and the
> `key.properties` values to a password manager (1Password / iCloud Keychain).
> If you lose this keystore you cannot publish updates to the same Play listing
> — Google requires the same signature for every release. (Play App Signing can
> help recover, but don't rely on it.)

To create a fresh keystore instead:

```bash
~/jdk17/Contents/Home/bin/keytool -genkeypair -v \
  -keystore ~/taskmaster-upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias taskmaster
```

Then fill `android/key.properties`:

```properties
storePassword=<your password>
keyPassword=<your password>
keyAlias=taskmaster
storeFile=/Users/<you>/taskmaster-upload-keystore.jks
```

## JDK: tell Flutter which one to use (one-time)

Flutter picks the JDK in this order: `flutter config --jdk-dir` → the JDK
bundled with Android Studio → `JAVA_HOME`. Android Studio 2026.x bundles JDK
25, which the project's Gradle 8.7 cannot run on ("incompatible with Gradle
8.7"), and `JAVA_HOME` alone does **not** override it. Point Flutter at a JDK
17 once:

```bash
brew install openjdk@17        # if not present
flutter config --jdk-dir=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
```

(`scripts/make-release.sh` checks this and refuses to build without it.)

### Moving to Flutter 3.47+ later

Verified 2026-09-07: the project builds and the full suite passes on Flutter
3.47.2 with exactly these changes — `CardTheme(` → `CardThemeData(` (2×) and
`DialogTheme(` → `DialogThemeData(` in `lib/core/theme/app_theme.dart`;
`gradle-8.7` → `gradle-8.14` in `android/gradle/wrapper/gradle-wrapper.properties`;
AGP `8.5.2` → `8.11.1` and Kotlin `1.9.10` → `2.2.20` in `android/settings.gradle`.
Gradle 8.14 still needs a JDK ≤ 24, so the `--jdk-dir` step above stays.

## Build the App Bundle

```bash
scripts/make-release.sh
# → build/app/outputs/bundle/release/app-release.aab
```

Bump the version in `pubspec.yaml` (`version: 1.0.0+1` → `1.0.1+2`, etc.) before
each new upload — Play rejects duplicate `versionCode`s.

## Upload to Internal testing
1. Play Console → your app → **Testing → Internal testing → Create new release**
2. Upload `app-release.aab`
3. Add tester emails (or an internal testing email list), save, **review**, roll out
4. Share the opt-in URL with testers; they install via the Play Store link

## Firebase on Android
Done: `android/app/google-services.json` and the Android block of
`lib/firebase_options.dart` are committed, and the debug build was verified to
initialise Firebase and reach onboarding on the `pixel10_api35` emulator
(2026-09-07). Store-listing material: `docs/STORE_LISTING.md`.
