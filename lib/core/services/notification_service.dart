import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// App-level push-notification abstraction. Keeps `firebase_messaging` behind
/// an interface so the rest of the app — and the tests — don't depend on it.
///
/// The async game model relies on nudging players ("it's your turn",
/// "deadline soon", "you've been judged"). Sending those pushes requires a
/// server/Cloud Function targeting device tokens; this client side handles
/// permission, token retrieval, and foreground message handling.
abstract class NotificationService {
  /// Request permission and wire up message handlers. Must never throw — a
  /// failure here should not block app startup.
  Future<void> initialize();

  /// The FCM registration token for this device, or null if unavailable.
  Future<String?> getToken();

  /// Persist this device's FCM token onto `users/{uid}.fcmTokens` (a map keyed
  /// by token) so a future server/Cloud Function can target the user's devices.
  /// Best-effort — must never throw. No-op when there is no token. Nothing
  /// sends push messages yet; this only prepares the token store.
  Future<void> registerToken(String uid);

  /// Whether the user has granted notification permission.
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
/// failure (e.g. web without a configured VAPID key, or a platform without
/// Firebase set up) is swallowed so it never crashes the app.
class FcmNotificationService implements NotificationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore;
  StreamSubscription<RemoteMessage>? _foregroundSub;

  FcmNotificationService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  @override
  Future<bool> requestPermission() async {
    try {
      final settings = await _messaging.requestPermission(
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
    try {
      await requestPermission();
      _foregroundSub = FirebaseMessaging.onMessage.listen((message) {
        // Foreground delivery — surfacing an in-app banner is a UI follow-up.
        final n = message.notification;
        if (n != null) {
          debugPrint('FCM foreground message: ${n.title} — ${n.body}');
        }
      });
    } catch (e) {
      debugPrint('NotificationService.initialize failed: $e');
    }
  }

  @override
  Future<String?> getToken() async {
    try {
      return await _messaging.getToken();
    } catch (e) {
      debugPrint('NotificationService.getToken failed: $e');
      return null;
    }
  }

  @override
  Future<void> registerToken(String uid) async {
    if (uid.isEmpty) return;
    try {
      final token = await getToken();
      if (token == null || token.isEmpty) return;
      // Store under a map keyed by the token so multiple devices coexist and a
      // re-registration of the same token is a harmless no-op overwrite.
      await _firestore.collection('users').doc(uid).set({
        'fcmTokens': {token: FieldValue.serverTimestamp()},
      }, SetOptions(merge: true));
    } catch (e) {
      // Best-effort: never let token registration disrupt sign-in.
      debugPrint('NotificationService.registerToken failed: $e');
    }
  }

  @override
  void dispose() {
    _foregroundSub?.cancel();
  }
}
