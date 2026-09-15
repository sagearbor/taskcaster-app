import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/services/push/push_gateway.dart';
import 'package:taskcaster_app/core/services/push/web_push_service.dart';
import 'package:taskcaster_app/features/games/presentation/widgets/push_opt_in_card.dart';

/// The opt-in card is the one place the app asks for push permission, and the
/// browser only ever grants one prompt. So the rule this pins is: offer it
/// exactly when asking could still work, and stay invisible otherwise.
void main() {
  setUp(PushOptInCard.resetForTest);

  Widget host(WebPushService service) => MaterialApp(
        home: Scaffold(body: PushOptInCard(service: service)),
      );

  WebPushService serviceWith(PushPermission permission) => WebPushService(
        gateway: FakePushGateway(permission: permission),
        firestore: FakeFirebaseFirestore(),
      );

  testWidgets('offers when the browser has not been asked yet', (tester) async {
    await tester.pumpWidget(host(serviceWith(PushPermission.prompt)));
    expect(find.text('Want a ping when someone grades this?'), findsOneWidget);
    expect(find.text('Notify me'), findsOneWidget);
    expect(find.text('No thanks'), findsOneWidget);
  });

  testWidgets('renders nothing on a platform without web push', (tester) async {
    // This is the mobile case: Android and iOS get FCM device-token pushes,
    // not browser push, so the card must never appear there.
    await tester.pumpWidget(host(serviceWith(PushPermission.unsupported)));
    expect(find.byType(FilledButton), findsNothing);
    expect(find.text('Want a ping when someone grades this?'), findsNothing);
  });

  testWidgets('renders nothing once the browser has already been answered',
      (tester) async {
    for (final answered in [PushPermission.granted, PushPermission.denied]) {
      PushOptInCard.resetForTest();
      await tester.pumpWidget(host(serviceWith(answered)));
      expect(
        find.text('Want a ping when someone grades this?'),
        findsNothing,
        reason: 'must not re-ask when permission is $answered',
      );
    }
  });

  testWidgets('"No thanks" hides the card and it stays hidden on the next post',
      (tester) async {
    await tester.pumpWidget(host(serviceWith(PushPermission.prompt)));
    await tester.tap(find.text('No thanks'));
    await tester.pumpAndSettle();
    expect(find.text('Want a ping when someone grades this?'), findsNothing);

    // A fresh card — as the next task's Posted screen would build — must not
    // ask again in the same session.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(host(serviceWith(PushPermission.prompt)));
    expect(find.text('Want a ping when someone grades this?'), findsNothing);
  });
}
