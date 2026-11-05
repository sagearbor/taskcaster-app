/// Non-web [PushGateway]: Firebase Cloud Messaging on iOS and Android.
///
/// The browser half (`push_gateway_web.dart`) speaks VAPID web push. Here the
/// "subscription" is an FCM registration token, which the Cloud Function
/// (`functions/src/push.js#sendToFcmTokens`) delivers to through APNs on iOS
/// and directly on Android.
///
/// Everything touching `FirebaseMessaging` is lazy and wrapped: a VM test, a
/// desktop build, or a run without Firebase initialised must read as
/// [PushPermission.unsupported], never throw into the UI.
library;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'push_gateway.dart';

/// Maps the plugin's permission state onto the app's.
///
/// `provisional` (iOS quiet delivery) counts as granted: notifications do
/// arrive, in Notification Centre, and asking again would not show a dialog.
PushPermission pushPermissionFor(AuthorizationStatus status) {
  switch (status) {
    case AuthorizationStatus.authorized:
    case AuthorizationStatus.provisional:
      return PushPermission.granted;
    case AuthorizationStatus.denied:
      return PushPermission.denied;
    case AuthorizationStatus.notDetermined:
      return PushPermission.prompt;
  }
}

class PlatformPushGateway implements PushGateway {
  final Future<AuthorizationStatus> Function() _readStatus;
  final Future<AuthorizationStatus> Function() _requestPermission;
  final Future<String?> Function() _getToken;

  /// Unknown until the first [refresh]. Unsupported is the safe default: the
  /// opt-in card stays hidden rather than asking someone who already said yes.
  PushPermission _cached = PushPermission.unsupported;

  /// The three seams are for tests; production uses FirebaseMessaging.
  PlatformPushGateway({
    Future<AuthorizationStatus> Function()? readStatus,
    Future<AuthorizationStatus> Function()? requestPermission,
    Future<String?> Function()? getToken,
  })  : _readStatus = readStatus ?? _fcmReadStatus,
        _requestPermission = requestPermission ?? _fcmRequestPermission,
        _getToken = getToken ?? fcmTokenWhenReady;

  @override
  PushPermission permission() => _cached;

  @override
  Future<void> refresh() async {
    if (!_platformSupportsFcm) return;
    try {
      _cached = pushPermissionFor(await _readStatus());
    } catch (e) {
      debugPrint('PushGateway.refresh failed: $e');
      _cached = PushPermission.unsupported;
    }
  }

  @override
  Future<PushTarget?> subscribe() async {
    if (!_platformSupportsFcm) return null;
    try {
      _cached = pushPermissionFor(await _requestPermission());
      if (_cached != PushPermission.granted) return null;
      final token = await _getToken();
      if (token == null || token.isEmpty) return null;
      return FcmRegistration(token);
    } catch (e) {
      debugPrint('PushGateway.subscribe failed: $e');
      return null;
    }
  }
}

/// iOS and Android only. Desktop builds have no FCM and must never be offered
/// the opt-in. (Overridable in tests via `debugDefaultTargetPlatformOverride`.)
bool get _platformSupportsFcm =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

Future<AuthorizationStatus> _fcmReadStatus() async =>
    (await FirebaseMessaging.instance.getNotificationSettings())
        .authorizationStatus;

Future<AuthorizationStatus> _fcmRequestPermission() async =>
    (await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    ))
        .authorizationStatus;

/// The FCM token, waiting out iOS's APNs handshake first.
///
/// On iOS `getToken()` throws `apns-token-not-set` until APNs has handed the
/// app its device token, which happens asynchronously AFTER the permission
/// dialog is accepted. Poll for it briefly instead of failing the opt-in the
/// player just said yes to. Shared with `FcmNotificationService`.
Future<String?> fcmTokenWhenReady() async {
  final messaging = FirebaseMessaging.instance;
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    String? apns;
    for (var i = 0; i < 20 && apns == null; i++) {
      apns = await messaging.getAPNSToken();
      if (apns == null) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
    // No APNs token after ~5 s: a simulator, or a build signed without the
    // aps-environment entitlement. Nothing could be delivered anyway.
    if (apns == null) return null;
  }
  return messaging.getToken();
}
