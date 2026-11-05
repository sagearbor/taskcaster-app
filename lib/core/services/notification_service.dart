import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'push/push_gateway.dart';
import 'push/push_gateway_stub.dart' show fcmTokenWhenReady;
import 'push/web_push_service.dart';

/// App-level push-notification abstraction. Keeps `firebase_messaging` behind
/// an interface so the rest of the app — and the tests — don't depend on it.
///
/// Sending is server-side: `onGradeCreated` (functions/src/push.js) sends
/// "you got graded" to every FCM token on `push_subscriptions/{uid}`. This
/// client side keeps that token store current and handles foreground
/// delivery. It never ASKS for permission: that happens on the Posted screen
/// after the player's first post (PushOptInCard), the same as on web.
abstract class NotificationService {
  /// Wire up message handlers and, if the player has ALREADY granted
  /// permission, refresh this device's token. Never prompts. Must never
  /// throw — a failure here should not block app startup.
  Future<void> initialize();

  /// The FCM registration token for this device, or null if unavailable.
  Future<String?> getToken();

  /// Persist this device's FCM token onto
  /// `push_subscriptions/{uid}.fcmTokens.{token}`, where the grade push
  /// Cloud Function reads it. Only when notification permission is already
  /// granted, and never on web (web uses VAPID subscriptions instead).
  /// Best-effort — must never throw.
  Future<void> registerToken(String uid);

  /// Prompt for notification permission; whether it is granted.
  Future<bool> requestPermission();

  void dispose();
}

/// No-op implementation for development, tests, and unsupported platforms.
class MockNotificationService implements NotificationService {
  @override
  Future<void> initialize() async {}

  @override
  Future<String?> getToken() async => 'mock-fcm-token';

  @override
  Future<void> registerToken(String uid) async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  void dispose() {}
}

/// Real Firebase Cloud Messaging implementation. Degrades gracefully: any
/// failure (a platform without Firebase set up, a simulator without APNs) is
/// swallowed so it never crashes the app.
class FcmNotificationService implements NotificationService {
  final FirebaseFirestore? _injectedFirestore;
  final String? Function() _currentUid;
  final Future<bool> Function() _isPermitted;
  final Future<String?> Function() _tokenSource;
  final bool _isWeb;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<String>? _tokenRefreshSub;
  final Set<String> _legacyCleaned = {};

  /// The seams are for tests; production uses the Firebase singletons.
  FcmNotificationService({
    FirebaseFirestore? firestore,
    String? Function()? currentUid,
    Future<bool> Function()? isPermitted,
    Future<String?> Function()? tokenSource,
    bool? isWeb,
  })  : _injectedFirestore = firestore,
        _currentUid = currentUid ?? _firebaseUid,
        _isPermitted = isPermitted ?? _fcmIsPermitted,
        _tokenSource = tokenSource ?? fcmTokenWhenReady,
        _isWeb = isWeb ?? kIsWeb;

  FirebaseFirestore get _firestore =>
      _injectedFirestore ?? FirebaseFirestore.instance;

  static String? _firebaseUid() => fb.FirebaseAuth.instance.currentUser?.uid;

  static Future<bool> _fcmIsPermitted() async {
    final s = await FirebaseMessaging.instance.getNotificationSettings();
    return s.authorizationStatus == AuthorizationStatus.authorized ||
        s.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Future<bool> requestPermission() async {
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (e) {
      debugPrint('NotificationService.requestPermission failed: $e');
      return false;
    }
  }

  @override
  Future<void> initialize() async {
    // Web push is VAPID (web/push.js); FCM on web would need a console-only
    // Web Push certificate and its getToken() would itself prompt.
    if (_isWeb) return;
    try {
      final messaging = FirebaseMessaging.instance;
      // iOS shows nothing for a push that arrives while the app is open
      // unless told to; a grade landing mid-session should still be seen.
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      _foregroundSub = FirebaseMessaging.onMessage.listen((message) {
        final n = message.notification;
        if (n != null) {
          debugPrint('FCM foreground message: ${n.title} — ${n.body}');
        }
      });
      // Tokens rotate (app restore, FCM housekeeping). Re-store the new one,
      // or grades go to a token the server will soon prune as dead.
      _tokenRefreshSub = messaging.onTokenRefresh.listen((token) {
        final uid = _currentUid();
        if (uid != null && uid.isNotEmpty) {
          unawaited(_storeToken(uid, token));
        }
      });
    } catch (e) {
      debugPrint('NotificationService.initialize failed: $e');
    }
    // Players who granted permission before tokens moved off users/{uid}
    // (or before the opt-in card existed) never see the card again, since
    // there is nothing left to ask. Register them here instead.
    try {
      final uid = _currentUid();
      if (uid != null && uid.isNotEmpty) await registerToken(uid);
    } catch (e) {
      debugPrint('NotificationService.initialize registerToken failed: $e');
    }
  }

  @override
  Future<String?> getToken() async {
    try {
      return await _tokenSource();
    } catch (e) {
      debugPrint('NotificationService.getToken failed: $e');
      return null;
    }
  }

  @override
  Future<void> registerToken(String uid) async {
    if (uid.isEmpty || _isWeb) return;
    try {
      // Not opted in: storing a token would only make the server send pushes
      // the OS then refuses to show.
      if (!await _isPermitted()) return;
      final token = await getToken();
      if (token == null || token.isEmpty) return;
      await _storeToken(uid, token);
    } catch (e) {
      // Best-effort: never let token registration disrupt sign-in.
      debugPrint('NotificationService.registerToken failed: $e');
    }
  }

  Future<void> _storeToken(String uid, String token) async {
    try {
      await _firestore
          .collection(WebPushService.collection)
          .doc(uid)
          .set(WebPushService.fieldsFor(FcmRegistration(token)),
              SetOptions(merge: true));
    } catch (e) {
      debugPrint('NotificationService._storeToken failed: $e');
      return;
    }
    // Tokens used to live on users/{uid}, which any signed-in user can read.
    // Remove the legacy copy now that the private one exists, once per
    // process. Best-effort: the field is simply absent for most people.
    if (_legacyCleaned.contains(uid)) return;
    _legacyCleaned.add(uid);
    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .update({'fcmTokens': FieldValue.delete()});
    } catch (_) {
      // No users doc, or no field: nothing to clean up.
    }
  }

  @override
  void dispose() {
    _foregroundSub?.cancel();
    _tokenRefreshSub?.cancel();
  }
}
