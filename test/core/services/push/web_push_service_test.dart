import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/services/push/push_gateway.dart';
import 'package:taskcaster_app/core/services/push/web_push_service.dart';

/// "Tell me when someone grades my clip": the client half.
///
/// The Cloud Function reads `push_subscriptions/{uid}.subs.{id}` — if this
/// service writes anywhere else, or writes a shape the function cannot parse,
/// nothing sends and nothing errors. These tests pin the contract.
void main() {
  const sub = PushSubscription(
    endpoint: 'https://fcm.googleapis.com/fcm/send/abc123',
    p256dh: 'BClientPublicKey',
    auth: 'AuthSecret',
  );

  group('WebPushService.enable', () {
    test('writes the subscription where the Cloud Function looks for it',
        () async {
      final firestore = FakeFirebaseFirestore();
      final service = WebPushService(
        gateway: FakePushGateway(subscription: sub),
        firestore: firestore,
      );

      expect(await service.enable('user-1'), PushOptInResult.enabled);

      final doc =
          await firestore.collection('push_subscriptions').doc('user-1').get();
      expect(doc.exists, isTrue);
      final subs = doc.data()!['subs'] as Map<String, dynamic>;
      expect(subs, hasLength(1));
      final stored = subs[sub.id] as Map<String, dynamic>;
      expect(stored['endpoint'], sub.endpoint);
      expect(stored['p256dh'], sub.p256dh);
      expect(stored['auth'], sub.auth);
    });

    test('the same browser re-subscribing overwrites, never accumulates',
        () async {
      final firestore = FakeFirebaseFirestore();
      final service = WebPushService(
        gateway: FakePushGateway(subscription: sub),
        firestore: firestore,
      );

      await service.enable('user-1');
      await service.enable('user-1');

      final doc =
          await firestore.collection('push_subscriptions').doc('user-1').get();
      expect((doc.data()!['subs'] as Map).length, 1);
    });

    test('a second browser adds a second subscription alongside the first',
        () async {
      final firestore = FakeFirebaseFirestore();
      const other = PushSubscription(
        endpoint: 'https://updates.push.services.mozilla.com/wpush/v2/xyz',
        p256dh: 'BOtherKey',
        auth: 'OtherSecret',
      );

      await WebPushService(
        gateway: FakePushGateway(subscription: sub),
        firestore: firestore,
      ).enable('user-1');
      await WebPushService(
        gateway: FakePushGateway(subscription: other),
        firestore: firestore,
      ).enable('user-1');

      final doc =
          await firestore.collection('push_subscriptions').doc('user-1').get();
      final subs = doc.data()!['subs'] as Map<String, dynamic>;
      expect(subs.keys, containsAll(<String>[sub.id, other.id]));
      expect(subs, hasLength(2));
    });

    test('a browser that cannot do push is reported, not written', () async {
      final firestore = FakeFirebaseFirestore();
      final service = WebPushService(
        gateway: FakePushGateway(permission: PushPermission.unsupported),
        firestore: firestore,
      );

      expect(await service.enable('user-1'), PushOptInResult.unsupported);
      final doc =
          await firestore.collection('push_subscriptions').doc('user-1').get();
      expect(doc.exists, isFalse);
    });

    test('saying no is reported as declined and stores nothing', () async {
      final firestore = FakeFirebaseFirestore();
      final gateway = FakePushGateway(); // no subscription -> the user refused
      final service = WebPushService(gateway: gateway, firestore: firestore);
      gateway.setPermission(PushPermission.denied);

      expect(await service.enable('user-1'), PushOptInResult.declined);
      expect(
        (await firestore.collection('push_subscriptions').doc('user-1').get())
            .exists,
        isFalse,
      );
    });

    test('an empty uid never writes a stray document', () async {
      final firestore = FakeFirebaseFirestore();
      final gateway = FakePushGateway(subscription: sub);
      expect(
        await WebPushService(gateway: gateway, firestore: firestore).enable(''),
        PushOptInResult.failed,
      );
      expect(gateway.subscribeCalls, 0);
    });
  });

  group('prompting', () {
    test('only offers when the browser has not been asked yet', () {
      FakeFirebaseFirestore firestore() => FakeFirebaseFirestore();
      WebPushService withPermission(PushPermission p) => WebPushService(
            gateway: FakePushGateway(permission: p),
            firestore: firestore(),
          );

      expect(withPermission(PushPermission.prompt).canPrompt, isTrue);
      expect(withPermission(PushPermission.granted).canPrompt, isFalse);
      // The browser will not re-prompt after a refusal, so neither do we.
      expect(withPermission(PushPermission.denied).canPrompt, isFalse);
      expect(withPermission(PushPermission.unsupported).canPrompt, isFalse);

      expect(withPermission(PushPermission.granted).isEnabled, isTrue);
      expect(withPermission(PushPermission.prompt).isEnabled, isFalse);
    });
  });

  group('PushSubscription', () {
    test('ids are stable per endpoint and differ between endpoints', () {
      expect(sub.id, stableIdForEndpoint(sub.endpoint));
      expect(sub.id, isNot(stableIdForEndpoint('${sub.endpoint}x')));
      // Firestore field paths treat these specially; the id must avoid them.
      expect(sub.id, matches(RegExp(r'^[0-9a-f]+$')));
    });

    test('malformed JSON from the browser parses to null, never throws', () {
      expect(PushSubscription.fromJson(const {}), isNull);
      expect(
        PushSubscription.fromJson(const {'endpoint': 'https://x', 'p256dh': 'a'}),
        isNull,
      );
      expect(
        PushSubscription.fromJson(
            const {'endpoint': '', 'p256dh': 'a', 'auth': 'b'}),
        isNull,
      );
      expect(
        PushSubscription.fromJson(
            const {'endpoint': 'https://x', 'p256dh': 'a', 'auth': 'b'}),
        isNotNull,
      );
    });
  });
}
