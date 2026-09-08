# Monetization (Ads + In-App Purchases)

## Current state: none (removed)

The app ships with **no ads and no in-app purchases**. The earlier placeholder
services (`ad_service_simple.dart`, `purchase_service_simple.dart`) and the
store screens were removed so a store build cannot accidentally show a fake
purchase flow; the Play "Ads" declaration is therefore **No**.
`google_mobile_ads` and `in_app_purchase` are **intentionally not** in
`pubspec.yaml`.

## Why real monetization wasn't enabled in this pass

It is deliberately deferred, not forgotten:

1. **External accounts required** — AdMob app/ad-unit IDs, and App Store
   Connect / Play Console product definitions. None exist yet.
2. **Mobile platforms required** — both SDKs are mobile-first and need the
   native config that only lands with `flutterfire configure` + store setup
   (see `docs/MOBILE_SETUP.md`).
3. **Not headless-verifiable** — purchase and ad flows can't be exercised in
   `flutter test`; shipping them unverified risks a broken paid surface, which
   is worse than a clean demo.
4. **Project ethos** — the app targets zero ongoing cost on the Firebase free
   tier; ads/IAP are a post-launch concern.

## Integration path when ready

### Ads (google_mobile_ads)
1. `flutter pub add google_mobile_ads` and create an AdMob account + ad units.
2. Add the app id to `AndroidManifest.xml` and `Info.plist`.
3. Re-introduce an `AdService` interface with a real implementation and a
   mock for tests, registered in `service_locator.dart` (the old files are in
   git history before the "remove dead monetization services" commit).
4. Build an `AdBannerWidget` on top of it.

### In-app purchases (in_app_purchase)
1. `flutter pub add in_app_purchase` and define products (`taskmaster_pro`,
   `task_pack_basic|premium|ultimate`) in both stores.
2. Implement a `PurchaseService` against the real `InAppPurchase.instance`
   (interface + mock, as above).
3. Add **server-side receipt verification** (a Cloud Function) before granting
   entitlements — never trust the client.
4. Persist entitlements (e.g. a `pro` flag on the user doc) and gate features
   (remove ads, unlock packs) on it.

There is no store UI in the tree any more; when monetization returns, build it
behind the services above and update the Play/App Store declarations in
`docs/STORE_LISTING.md`.
