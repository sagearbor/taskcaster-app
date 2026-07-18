import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taskcaster_app/core/di/service_locator.dart';
import 'package:taskcaster_app/core/theme/app_theme.dart';
import 'package:taskcaster_app/core/theme/theme_controller.dart';
import 'package:taskcaster_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:taskcaster_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:taskcaster_app/features/home/presentation/screens/home_screen.dart';
import 'package:taskcaster_app/features/settings/presentation/screens/settings_screen.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ThemeController.instance.setThemeMode(ThemeMode.system);
    await sl.reset();
    await ServiceLocator.init(useMockServices: true);
  });

  // Pumps [child] inside a MaterialApp forced to the dark theme, so we can
  // assert screens inherit the dark tokens (not Material defaults).
  Future<void> pumpDark(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await tester.pumpWidget(
        BlocProvider<AuthBloc>(
          create: (_) => AuthBloc(authRepository: sl<AuthRepository>()),
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: ThemeMode.dark,
            home: child,
          ),
        ),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('settings screen renders in dark mode with dark tokens',
      (tester) async {
    await pumpDark(tester, const SettingsScreen());

    // Section headers are rendered upper-cased by _sectionHeader.
    expect(find.text('APPEARANCE'), findsOneWidget);
    expect(find.text('System default'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);

    // The screen inherited the dark theme rather than falling back to a light
    // scaffold (which would render dark text invisibly).
    final ctx = tester.element(find.text('APPEARANCE'));
    expect(Theme.of(ctx).brightness, Brightness.dark);
    expect(Theme.of(ctx).scaffoldBackgroundColor, AppTheme.darkBg);

    // Body text uses the light on-surface token, so it's readable on dark.
    expect(Theme.of(ctx).colorScheme.onSurface, AppTheme.onDark);
  });

  testWidgets('tapping a theme tile switches the controller mode',
      (tester) async {
    await pumpDark(tester, const SettingsScreen());

    await tester.tap(find.text('Light'));
    await tester.pump();
    expect(ThemeController.instance.themeMode, ThemeMode.light);

    await tester.tap(find.text('Dark'));
    await tester.pump();
    expect(ThemeController.instance.themeMode, ThemeMode.dark);

    // Persisted across a fresh read.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('theme_mode'), 'dark');
  });

  testWidgets('home screen renders in dark mode without a light scaffold',
      (tester) async {
    await pumpDark(tester, const HomeScreen());

    // Home content is present and the tree is genuinely dark.
    expect(find.text('Play'), findsWidgets);
    final ctx = tester.element(find.text('Play').first);
    expect(Theme.of(ctx).brightness, Brightness.dark);
    expect(Theme.of(ctx).scaffoldBackgroundColor, AppTheme.darkBg);
  });

  testWidgets('the Play sheet opens over the dark theme', (tester) async {
    await pumpDark(tester, const HomeScreen());

    await tester.tap(find.text('Play').first);
    await tester.pumpAndSettle();

    // Sheet destinations render; the modal inherited the dark bottom-sheet token.
    expect(find.text('Quick Play'), findsOneWidget);
    expect(find.text('Drawing Telephone'), findsOneWidget);
    final ctx = tester.element(find.text('Quick Play'));
    expect(Theme.of(ctx).brightness, Brightness.dark);
    expect(Theme.of(ctx).bottomSheetTheme.backgroundColor,
        AppTheme.darkSurfaceHigh);
  });
}
