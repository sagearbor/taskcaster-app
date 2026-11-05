import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:taskcaster_app/core/models/user.dart';
import 'package:taskcaster_app/core/services/plans/plan_repository.dart';
import 'package:taskcaster_app/core/services/plans/plans.dart';
import 'package:taskcaster_app/core/services/purchases/purchases_service.dart';
import 'package:taskcaster_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:taskcaster_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:taskcaster_app/features/paywall/presentation/paywall_launcher.dart';
import 'package:taskcaster_app/features/paywall/presentation/screens/paywall_screen.dart';
import 'package:taskcaster_app/features/paywall/presentation/widgets/upgrade_prompt.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late AuthBloc authBloc;
  late MockAuthRepository authRepository;

  setUp(() {
    authRepository = MockAuthRepository();
    when(() => authRepository.getCurrentUser()).thenAnswer((_) async => User(
          id: 'uid-123',
          displayName: 'Sam',
          createdAt: DateTime(2026, 1, 1),
        ));
    authBloc = AuthBloc(authRepository: authRepository);
  });

  tearDown(() => authBloc.close());

  Future<void> pumpPaywall(
    WidgetTester tester, {
    required UserPlan plan,
    required PurchasesService purchases,
    bool isWeb = false,
  }) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      authBloc.add(AuthCheckRequested());
      await authBloc.stream.firstWhere((s) => s is AuthAuthenticated);
    });
    await tester.pumpWidget(BlocProvider<AuthBloc>.value(
      value: authBloc,
      child: MaterialApp(
        home: PaywallScreen(
          entry: PaywallEntry.settings,
          planRepository: MockPlanRepository(initial: plan),
          purchases: purchases,
          isWeb: isWeb,
          openLink: (_) async {},
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('free player on mobile: yearly + monthly, buying calls the store',
      (tester) async {
    final purchases = FakePurchasesService();
    await pumpPaywall(tester, plan: UserPlan.free, purchases: purchases);

    expect(find.text('Free plan'), findsOneWidget);
    expect(find.text(r'$25.00 / year'), findsOneWidget);
    expect(find.text(r'$5.00 / month'), findsOneWidget);
    expect(find.text('Restore purchases'), findsOneWidget);
    expect(find.text(PlanCopy.retentionNote), findsOneWidget);
    // RevenueCat is tied to the Firebase uid before anything is sold.
    expect(purchases.identified, ['uid-123']);

    await tester.tap(find.byKey(const Key('paywall.buy.taskcaster_pro_yearly')));
    await tester.pump();
    expect(purchases.purchased, ['taskcaster_pro_yearly']);
    expect(find.text('Welcome to TaskCaster Pro!'), findsOneWidget);
  });

  testWidgets('guest: must Continue with Apple/Google first, no buy buttons',
      (tester) async {
    final purchases = FakePurchasesService();
    await pumpPaywall(tester, plan: UserPlan.guest, purchases: purchases);

    expect(find.text('Guest'), findsOneWidget);
    expect(find.byKey(const Key('paywall.continueApple')), findsOneWidget);
    expect(find.byKey(const Key('paywall.continueGoogle')), findsOneWidget);
    expect(find.textContaining('/ year'), findsNothing);
    expect(purchases.identified, isEmpty,
        reason: 'never tie RevenueCat to an anonymous uid');
  });

  testWidgets('web: no IAP, "available in the iOS/Android app"',
      (tester) async {
    final purchases = FakePurchasesService();
    await pumpPaywall(tester,
        plan: UserPlan.free, purchases: purchases, isWeb: true);

    expect(find.byKey(const Key('paywall.webNote')), findsOneWidget);
    expect(find.text(PlanCopy.webNote), findsOneWidget);
    expect(find.textContaining('/ month'), findsNothing);
    expect(find.text('Restore purchases'), findsNothing);
    expect(purchases.identified, isEmpty);
  });

  testWidgets('web still honors Pro bought on mobile (plan is in Firestore)',
      (tester) async {
    await pumpPaywall(
      tester,
      plan: UserPlan(
        tier: PlanTier.pro,
        expiresAt: DateTime(2027, 1, 2),
        willRenew: true,
      ),
      purchases: const UnconfiguredPurchasesService(),
      isWeb: true,
    );
    expect(find.text("You're Pro"), findsOneWidget);
    expect(find.textContaining('renews 2027-01-02'), findsOneWidget);
  });

  testWidgets('Pro on mobile: Manage subscription + Restore, no buy',
      (tester) async {
    await pumpPaywall(
      tester,
      plan: const UserPlan(tier: PlanTier.pro, willRenew: true),
      purchases: FakePurchasesService(),
    );
    expect(find.text("You're Pro"), findsOneWidget);
    expect(find.text('Manage subscription'), findsOneWidget);
    expect(find.textContaining('/ year'), findsNothing);
  });

  testWidgets('a build without a RevenueCat key says Pro is unavailable',
      (tester) async {
    await pumpPaywall(tester,
        plan: UserPlan.free, purchases: const UnconfiguredPurchasesService());
    expect(find.byKey(const Key('paywall.unavailable')), findsOneWidget);
  });

  testWidgets('the plan card flips to Pro when the server plan changes',
      (tester) async {
    final plans = MockPlanRepository();
    await tester.runAsync(() async {
      authBloc.add(AuthCheckRequested());
      await authBloc.stream.firstWhere((s) => s is AuthAuthenticated);
    });
    await tester.pumpWidget(BlocProvider<AuthBloc>.value(
      value: authBloc,
      child: MaterialApp(
        home: PaywallScreen(
          entry: PaywallEntry.settings,
          planRepository: plans,
          purchases: FakePurchasesService(),
          isWeb: false,
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('Free plan'), findsOneWidget);
    plans.plan = const UserPlan(tier: PlanTier.pro);
    await tester.pump();
    await tester.pump();
    expect(find.text("You're Pro"), findsOneWidget);
  });

  group('UpgradePrompt', () {
    Future<void> pumpPrompt(WidgetTester tester, Widget prompt) =>
        tester.pumpWidget(MaterialApp(home: Scaffold(body: prompt)));

    testWidgets(
        'guest with 5 clips used: Post as photo + Sign in free + Go Pro',
        (tester) async {
      var photo = 0;
      await pumpPrompt(
        tester,
        UpgradePrompt(
          tier: PlanTier.guest,
          onPostAsPhoto: () => photo++,
          onSignInFree: () {},
          onGoPro: () {},
        ),
      );
      expect(find.text(PlanCopy.limitTitle(PlanTier.guest)), findsOneWidget);
      expect(find.text('Post it as a photo instead'), findsOneWidget);
      expect(find.text('Sign in free (3 clips a day)'), findsOneWidget);
      expect(find.text('Go Pro'), findsOneWidget);
      await tester.tap(find.text('Post it as a photo instead'));
      expect(photo, 1);
    });

    testWidgets('DefaultPaywallLauncher: a free player gets no Sign in option',
        (tester) async {
      await tester.pumpWidget(BlocProvider<AuthBloc>.value(
        value: authBloc,
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => const DefaultPaywallLauncher().showLimitPrompt(
                context,
                tier: PlanTier.free,
                onPostAsPhoto: () {},
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Post it as a photo instead'), findsOneWidget);
      expect(find.textContaining('Sign in free'), findsNothing);
      expect(find.text('Go Pro'), findsOneWidget);
    });
  });
}
