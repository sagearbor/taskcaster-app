// Temporary: renders the paywall for the App Store subscription review screenshot.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:taskcaster_app/core/models/user.dart';
import 'package:taskcaster_app/core/services/plans/plan_repository.dart';
import 'package:taskcaster_app/core/services/plans/plans.dart';
import 'package:taskcaster_app/core/services/purchases/purchases_service.dart';
import 'package:taskcaster_app/core/theme/app_theme.dart';
import 'package:taskcaster_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:taskcaster_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:taskcaster_app/features/paywall/presentation/paywall_launcher.dart';
import 'package:taskcaster_app/features/paywall/presentation/screens/paywall_screen.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

Future<void> _fonts() async {
  Future<void> load(String f, Future<ByteData> d) async => (FontLoader(f)..addFont(d)).load();
  await load('Fredoka', rootBundle.load('assets/fonts/Fredoka.ttf'));
  await load('PlusJakartaSans', rootBundle.load('assets/fonts/PlusJakartaSans.ttf'));
  final root = Platform.environment['FLUTTER_ROOT']!;
  final icons = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  await load('MaterialIcons', Future.value(ByteData.sublistView(icons.readAsBytesSync())));
}

void main() {
  setUpAll(_fonts);
  testWidgets('paywall shot', (tester) async {
    final repo = MockAuthRepository();
    when(() => repo.getCurrentUser()).thenAnswer((_) async =>
        User(id: 'u', displayName: 'Sam', createdAt: DateTime(2026, 1, 1)));
    final bloc = AuthBloc(authRepository: repo);
    tester.view.physicalSize = const Size(1290, 2796);
    tester.view.devicePixelRatio = 3.0;
    print('A');
    await tester.runAsync(() async {
      bloc.add(AuthCheckRequested());
      await bloc.stream.firstWhere((s) => s is AuthAuthenticated).timeout(const Duration(seconds: 10));
    });
    print('B');
    await tester.pumpWidget(BlocProvider<AuthBloc>.value(
      value: bloc,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: RepaintBoundary(
          key: const Key('shot'),
          child: PaywallScreen(
            entry: PaywallEntry.settings,
            planRepository: MockPlanRepository(initial: UserPlan.free),
            purchases: FakePurchasesService(),
            isWeb: false,
            openLink: (_) async {},
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    print('C');
    await expectLater(find.byKey(const Key('shot')), matchesGoldenFile('paywall_review.png'));
    await bloc.close();
  });
}
