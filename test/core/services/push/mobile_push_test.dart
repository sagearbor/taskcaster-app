import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/services/notification_service.dart';
import 'package:taskcaster_app/core/services/push/push_gateway.dart';
import 'package:taskcaster_app/core/services/push/push_gateway_stub.dart'
    as mobile;
import 'package:taskcaster_app/core/services/push/web_push_service.dart';

/// "You got graded" on iOS/Android: the client half.
///
/// The Cloud Function (functions/src/push.js) reads FCM tokens from
/// `push_subscriptions/{uid}.fcmTokens.{token}`. Anything written elsewhere —
/// notably the old, world-readable `users/{uid}.fcmTokens` — is never sent to.
void main() {
  group('mobile PushGateway (FCM)', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('maps every FCM authorization state', () {
      expect(mobile.pushPermissionFor(AuthorizationStatus.notDetermined),
          PushPermission.prompt);
      expect(mobile.pushPermissionFor(AuthorizationStatus.authorized),
          PushPermission.granted);
      expect(mobile.pushPermissionFor(AuthorizationStatus.provisional),
          PushPermission.granted);
      expect(mobile.pushPermissionFor(AuthorizationStatus.denied),
          PushPermission.denied);
    });

    test('says nothing until the platform has answered', () async {
      final gateway = mobile.PlatformPushGateway(
        readStatus: () async => AuthorizationStatus.notDetermined,
      );
      expect(gateway.permission(), PushPermission.unsupported);
      await gateway.refresh();
      expect(gateway.permission(), PushPermission.prompt);
    });

    test('a refresh that throws (no Firebase) reads as unsupported', () async {
      final gateway = mobile.PlatformPushGateway(
        readStatus: () async => throw StateError('no Firebase app'),
      );
      await gateway.refresh();
      expect(gateway.permission(), PushPermission.unsupported);
    });

    test('accepting the prompt yields the FCM token', () async {
      final gateway = mobile.PlatformPushGateway(
        requestPermission: () async => AuthorizationStatus.authorized,
        getToken: () async => 'fcm-token-1',
      );
      final target = await gateway.subscribe();
      expect(target, isA<FcmRegistration>());
      expect((target! as FcmRegistration).token, 'fcm-token-1');
      expect(gateway.permission(), PushPermission.granted);
    });

    test('refusing yields nothing and remembers the refusal', () async {
      var asked = false;
      final gateway = mobile.PlatformPushGateway(
        requestPermission: () async => AuthorizationStatus.denied,
        getToken: () async {
          asked = true;
          return 'never';
        },
      );
      expect(await gateway.subscribe(), isNull);
      expect(gateway.permission(), PushPermission.denied);
      expect(asked, isFalse, reason: 'no token without permission');
    });

    test('desktop is never offered push', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final gateway = mobile.PlatformPushGateway(
        readStatus: () async => AuthorizationStatus.notDetermined,
      );
      await gateway.refresh();
      expect(gateway.permission(), PushPermission.unsupported);
      expect(await gateway.subscribe(), isNull);
    });
  });

  group('WebPushService with an FCM token', () {
    test('stores it under fcmTokens, beside any browser subscriptions',
        () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('push_subscriptions').doc('u1').set({
        'subs': {
          'abc': {'endpoint': 'https://x', 'p256dh': 'p', 'auth': 'a'},
        },
      });
      final service = WebPushService(
        gateway: FakePushGateway(subscription: const FcmRegistration('tok:1')),
        firestore: firestore,
      );
      expect(await service.enable('u1'), PushOptInResult.enabled);

      final data =
          (await firestore.collection('push_subscriptions').doc('u1').get())
              .data()!;
      expect((data['fcmTokens'] as Map).keys, ['tok:1']);
      expect((data['subs'] as Map).keys, ['abc'],
          reason: 'a phone opting in must not wipe the browser');
    });
  });

  group('FcmNotificationService.registerToken', () {
    FcmNotificationService service(
      FakeFirebaseFirestore firestore, {
      bool permitted = true,
      bool isWeb = false,
    }) =>
        FcmNotificationService(
          firestore: firestore,
          currentUid: () => 'u1',
          isPermitted: () async => permitted,
          tokenSource: () async => 'tok:dev',
          isWeb: isWeb,
        );

    test('writes the token to push_subscriptions, not users', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('users').doc('u1').set({
        'displayName': 'Sam',
        'fcmTokens': {'tok:old': 1},
      });

      await service(firestore).registerToken('u1');

      final subs =
          (await firestore.collection('push_subscriptions').doc('u1').get())
              .data()!;
      expect((subs['fcmTokens'] as Map).keys, ['tok:dev']);
      final user = (await firestore.collection('users').doc('u1').get()).data()!;
      expect(user.containsKey('fcmTokens'), isFalse,
          reason: 'the world-readable legacy copy is removed');
      expect(user['displayName'], 'Sam');
    });

    test('stores nothing for a player who has not opted in', () async {
      final firestore = FakeFirebaseFirestore();
      await service(firestore, permitted: false).registerToken('u1');
      expect(
        (await firestore.collection('push_subscriptions').doc('u1').get())
            .exists,
        isFalse,
      );
    });

    test('does nothing on web (VAPID handles web)', () async {
      final firestore = FakeFirebaseFirestore();
      await service(firestore, isWeb: true).registerToken('u1');
      expect(
        (await firestore.collection('push_subscriptions').doc('u1').get())
            .exists,
        isFalse,
      );
    });

    test('never creates a users doc while cleaning up', () async {
      final firestore = FakeFirebaseFirestore();
      await service(firestore).registerToken('u1');
      final DocumentSnapshot user =
          await firestore.collection('users').doc('u1').get();
      expect(user.exists, isFalse);
    });
  });
}
