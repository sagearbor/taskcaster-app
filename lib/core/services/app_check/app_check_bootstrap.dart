import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

/// Which App Check providers this build should turn on.
enum AppCheckPlan {
  /// Not configured for this build: App Check stays off (today's behaviour).
  off,

  /// Web: reCAPTCHA Enterprise with the site key from `APP_CHECK_WEB_KEY`.
  web,

  /// Android Play Integrity / iOS DeviceCheck.
  mobile,
}

/// Firebase App Check, rolled out in MONITOR mode first (audit WP-04).
///
/// App Check attaches an attestation token to every Firestore, Storage and
/// Functions request so the backend can tell the real app from a script
/// holding an anonymous-auth uid. Nothing is refused until the owner flips
/// each product to "Enforce" in the Firebase console, so turning it on in the
/// app is safe on its own: the console shows verified vs. unverified traffic
/// and enforcement waits until that looks clean.
///
/// It is OFF unless the build opts in, because each provider needs a one-time
/// console registration first (see docs/FIREBASE_SETUP.md "App Check"):
///
///   flutter build web --dart-define=APP_CHECK_WEB_KEY=<reCAPTCHA Enterprise site key>
///   flutter build ipa|appbundle --dart-define=APP_CHECK=true
///
/// iOS uses DeviceCheck, which needs no entitlement. App Attest is stronger
/// but adds an entitlement and a provisioning-profile change; it is a
/// follow-up once DeviceCheck traffic looks right.
class AppCheckBootstrap {
  const AppCheckBootstrap._();

  static const String _webSiteKey = String.fromEnvironment('APP_CHECK_WEB_KEY');
  static const bool _mobileEnabled = bool.fromEnvironment('APP_CHECK');

  /// Pure decision, so it is testable without a platform channel.
  static AppCheckPlan planFor({
    required bool isWeb,
    required String webSiteKey,
    required bool mobileEnabled,
  }) {
    if (isWeb) {
      return webSiteKey.trim().isEmpty ? AppCheckPlan.off : AppCheckPlan.web;
    }
    return mobileEnabled ? AppCheckPlan.mobile : AppCheckPlan.off;
  }

  /// Turns App Check on when this build opted in. Never throws: a failure to
  /// attest must not stop the app from starting (and in monitor mode the
  /// backend accepts unattested requests anyway).
  static Future<void> activate() async {
    final plan = planFor(
      isWeb: kIsWeb,
      webSiteKey: _webSiteKey,
      mobileEnabled: _mobileEnabled,
    );
    if (plan == AppCheckPlan.off) return;
    try {
      await FirebaseAppCheck.instance.activate(
        webProvider: plan == AppCheckPlan.web
            ? ReCaptchaEnterpriseProvider(_webSiteKey)
            : null,
        androidProvider: AndroidProvider.playIntegrity,
        appleProvider: AppleProvider.deviceCheck,
      );
    } catch (e) {
      debugPrint('App Check activation failed (continuing without it): $e');
    }
  }
}
