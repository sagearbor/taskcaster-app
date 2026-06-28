# Social Login Setup (Google & Apple)

This app implements **real** Google and Apple sign-in via Firebase Auth. The
Dart code paths are complete and tested. Some providers require one-time
configuration in external consoles (Firebase / Google Cloud / Apple Developer)
before they will succeed on a real device. Those steps are listed here — they
are external dependencies, **not** stubs in the code.

Firebase project: `taskmaster-app-3d480`
Android package / applicationId: `com.sagearbor.taskcaster.app`

---

## 1. Google Sign-In (Android) — needs SHA-1/SHA-256 in Firebase

**Code status:** Complete. `FirebaseAuthDataSource.signInWithGoogle()` runs the
native account picker (`google_sign_in`), exchanges the Google `idToken` for a
Firebase credential via `GoogleAuthProvider`, and signs in. The
`com.google.gms.google-services` Gradle plugin is already applied, and
`android/app/google-services.json` already contains a **web OAuth client
(`client_type: 3`)**, which the plugin exposes as `default_web_client_id` — this
is what makes `idToken` non-null on Android. No `serverClientId` needs to be
passed in code.

**What is missing (manual, required for it to work on a device):**
The current `google-services.json` has **no Android OAuth client with a
certificate hash** (`client_type: 1`). Google blocks the sign-in until your
app's signing-certificate fingerprints are registered.

Do this:

1. Get the SHA-1 and SHA-256 of every keystore that signs the app:
   - **Debug:**
     ```bash
     keytool -list -v -alias androiddebugkey \
       -keystore ~/.android/debug.keystore -storepass android -keypass android
     ```
   - **Release / upload key:** run `keytool -list -v` against your release
     keystore.
   - **Google Play App Signing** (if enrolled): copy the SHA-1 **and** SHA-256
     from Play Console → your app → **Test and release → App integrity → App
     signing key certificate**. This one is essential — without it Google
     Sign-In fails on installs delivered by Play.
2. Firebase Console → Project settings → **Your apps → Android app
   (`com.sagearbor.taskcaster.app`) → Add fingerprint**. Add each SHA-1 and
   SHA-256 from step 1.
3. **Download the regenerated `google-services.json`** and replace
   `android/app/google-services.json` with it. (After step 2 it will contain a
   new `client_type: 1` entry.)
4. Firebase Console → **Authentication → Sign-in method → Google → Enable**, set
   a support email, Save.

After that, Google sign-in works on Android with no further code changes.

---

## 2. Apple Sign-In (Android, web OAuth flow) — needs Apple + Firebase config

**Code status:** Complete. `FirebaseAuthDataSource.signInWithApple()` generates
a nonce, hashes it with SHA-256, drives Apple's web OAuth flow via
`sign_in_with_apple`'s `WebAuthenticationOptions`, and exchanges the Apple
`identityToken` for a Firebase credential via `OAuthProvider('apple.com')`.

On Android there is **no native Apple SDK** — sign-in goes through Apple's web
page, so a **Services ID** and a **redirect URI** are required. The code uses
these constants (in `firebase_auth_data_source.dart`); they must match what you
configure:

| Constant | Value |
| --- | --- |
| `_appleServiceId` | `com.sagearbor.taskcaster.signin` |
| `_appleRedirectUri` | `https://taskmaster-app-3d480.firebaseapp.com/__/auth/handler` |

**What is missing (manual, required):** You need an Apple Developer Program
membership ($99/yr). Then:

### In the Apple Developer console (developer.apple.com → Certificates,
Identifiers & Profiles):

1. **App ID** — ensure an App ID exists for the app and has **Sign In with
   Apple** capability enabled.
2. **Services ID** → create a new Services ID with identifier
   **`com.sagearbor.taskcaster.signin`** (must equal `_appleServiceId`). Enable
   **Sign In with Apple** on it and click **Configure**:
   - **Primary App ID:** select the App ID from step 1.
   - **Domains:** `taskmaster-app-3d480.firebaseapp.com`
   - **Return URLs:** `https://taskmaster-app-3d480.firebaseapp.com/__/auth/handler`
     (must equal `_appleRedirectUri`).
3. **Key** → create a new Key with **Sign In with Apple** enabled, download the
   `.p8` file, and note the **Key ID** and your **Team ID**.

### In the Firebase console (Authentication → Sign-in method → Apple → Enable):

- **Services ID:** `com.sagearbor.taskcaster.signin`
- **Apple Team ID:** your Team ID
- **Key ID:** the Key ID from above
- **Private key:** paste the contents of the `.p8` file
- Save.

After both consoles are configured, Apple sign-in works on Android via the web
flow. If you later add iOS, the same code also supports the native iOS flow
(add the `Sign in with Apple` capability in Xcode).

> If you change either the Services ID or the redirect URI, update the matching
> constant in `firebase_auth_data_source.dart`.

---

## 3. Quick verification checklist

- [ ] Firebase Auth: Google provider **Enabled**
- [ ] Firebase Auth: Apple provider **Enabled** (with Team ID / Key ID / key)
- [ ] SHA-1 **and** SHA-256 (debug, release, and Play App Signing) added to the
      Firebase Android app
- [ ] `android/app/google-services.json` re-downloaded after adding fingerprints
- [ ] Apple Services ID `com.sagearbor.taskcaster.signin` created with the
      Firebase return URL
- [ ] Apple `.p8` key created and pasted into Firebase

Until the Google fingerprints are added, Google sign-in returns a
`PlatformException` (code 10 / `ApiException: 10`). Until the Apple console +
Firebase Apple provider are configured, Apple sign-in fails at the redirect.
Both surface to the user as an `AuthError` SnackBar on the login screen — no
silent failures.
