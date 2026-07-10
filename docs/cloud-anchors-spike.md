# Cloud Anchors Spike — AR Lab

A time-boxed feasibility spike to see whether **ARCore Cloud Anchors** work
between two phones using the vendored `ar_flutter_plugin_2`. This is a
**diagnostic tool, not a game feature**. It lives entirely under
`lib/features/ar_lab/` and touches no game flow, Firestore, or repositories.

Open it from **Settings → Experimental → "AR Lab (experimental)"**.

---

## What the spike does

The AR Lab has two modes plus a verbose, timestamped status log:

- **Host** — tap a detected plane to drop a gem, then host it. On success it
  shows the **cloud anchor ID** with a Copy button and a **QR code**, plus the
  time-to-host in ms.
- **Resolve** — paste/type a cloud anchor ID (or scan phone A's QR with the
  normal camera app to read it), then resolve. On success it renders the gem at
  the shared anchor and shows the time-to-resolve.

Every plugin call, callback, and error is written to the status log so failures
are legible during a two-phone test.

---

## One-time manual setup (required before hosting can succeed)

Cloud anchor **hosting** needs the ARCore Cloud Anchor API enabled in the
project **and** an Android API key present in the app manifest. Until both are
done, hosting fails with an authorization error and the AR Lab surfaces an
in-screen explanation (by design — it never fakes success).

> The GCP project is **`taskmaster-app-3d480`** (the same project as Firebase).

### 1. Enable the ARCore API in Google Cloud

1. Go to the Google Cloud Console: <https://console.cloud.google.com>
2. Make sure the project selector at the top shows **`taskmaster-app-3d480`**.
3. Open **APIs & Services → Library** (or go straight to
   <https://console.cloud.google.com/apis/library/arcorecloudanchor.googleapis.com>).
4. Search for **"ARCore API"** (service id `arcorecloudanchor.googleapis.com`).
5. Click **Enable**.

### 2. Create an Android API key

1. In the console, open **APIs & Services → Credentials**
   (<https://console.cloud.google.com/apis/credentials>), project
   `taskmaster-app-3d480`.
2. Click **Create credentials → API key**. Copy the key.
3. (Recommended) Click the new key → **Edit** and restrict it:
   - **Application restrictions → Android apps** → add the app's package name
     and debug/release SHA-1 fingerprints.
     Get the debug SHA-1 with:
     ```bash
     keytool -keystore ~/.android/debug.keystore -list -v \
       -alias androiddebugkey -storepass android -keypass android
     ```
   - **API restrictions → Restrict key** → allow only **ARCore API**.
   - Note: an API key gives a **24-hour** anchor lifetime (fine for a spike).
     Longer TTLs (up to 365 days) require OAuth/keyless auth, which is out of
     scope here.

### 3. Add the API key to the Android manifest

Open `android/app/src/main/AndroidManifest.xml`. There is a **commented-out**
`<meta-data>` block just after the `com.google.ar.core` tag. Uncomment it and
paste your key:

```xml
<meta-data
    android:name="com.google.android.ar.API_KEY"
    android:value="PASTE_ANDROID_API_KEY_HERE" />
```

> Do **not** commit a real key. Keep the tag commented out in git; add the key
> locally (or via a build-time secret) when running the spike.

Then rebuild the app (a manifest change requires a full reinstall, not hot
reload):

```bash
flutter run -d <android-device-id>
```

### iOS note

This spike is validated on **Android** only. iOS Cloud Anchors additionally need
a `cloudAnchorKey.json` service-account key bundled in the Runner target (see
`third_party/ar_flutter_plugin_2/cloudAnchorSetup.md`). Not required for the
Android two-phone test.

---

## How to run the two-phone test

You need **two physical ARCore-capable Android phones**, both with the API key
in the manifest, on a build from step 3.

**Phone A (Host):**
1. Open **Settings → AR Lab**, stay on the **Host** tab.
2. Point at a **feature-rich, well-lit** surface (textured desk, rug, book
   covers — avoid blank walls/floors and glare).
3. Move the phone slowly around the spot for **~10 seconds** so ARCore builds a
   dense feature map. Watch the log for `onPlaneDetected` and feature points.
4. **Tap a detected plane** — a gem drops (`addAnchor ok`, `addNode ok`).
5. Tap **Host anchor to cloud**. On success the log shows
   `onAnchorUploaded — cloud anchor id: …` and the ID + QR appear.

**Phone B (Resolve):**
1. Read the ID from phone A — **scan the QR** with the normal camera app, or
   copy it across.
2. Open **Settings → AR Lab → Resolve** tab, paste the ID.
3. Stand near where phone A was and look at the **same physical spot from a
   similar viewpoint**.
4. Tap **Resolve anchor**. On success the gem appears anchored to the real-world
   spot and the log shows the time-to-resolve.

### Success bar

Run the host→resolve cycle **10 times**. The spike passes if **≥ 8/10** resolves
succeed (and typically within a few seconds each). Note the time-to-host and
time-to-resolve from the log/result cards.

### If hosting keeps failing

- `insufficient visual data` → scan the area longer / find more texture / better
  light before tapping the plane.
- An **authorization / `NOT_AUTHORIZED` / `ERROR_`** message → the ARCore API is
  not enabled or the API key is missing/invalid in the manifest. Redo steps 1–3.
  The AR Lab shows a red "Cloud Anchor API may not be configured" card in this
  case.

---

## Plugin callback flow (for reference)

**Host:** `initGoogleCloudAnchorMode()` (at view creation) → tap plane →
`addAnchor(ARPlaneAnchor)` → `addNode(gem, planeAnchor:)` →
`uploadAnchor(anchor)` (the `Future<bool>` completes only when hosting finishes)
→ plugin fires `onAnchorUploaded(anchor)` with `anchor.cloudanchorid` set.

**Resolve:** `downloadAnchor(id)` → plugin resolves and adds the node, then fires
`onAnchorDownloaded(serialized)` which must **return** an `ARAnchor` (built by
hand — the serialized map only has `{type, cloudanchorid}`, no transformation).
The AR Lab then re-parents a gem to that anchor to draw it.

**TTL:** `ARPlaneAnchor.ttl` defaults to 1 day, but the vendored `host()` call
does not forward a TTL — with API-key auth the lifetime is ARCore's default
(~24h).

Errors from either flow arrive on `ARSessionManager.onError` and are logged
verbatim.
