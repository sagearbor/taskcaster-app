import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taskcaster_app/core/theme/app_theme.dart';
import 'package:taskcaster_app/core/theme/theme_controller.dart';

void main() {
  group('AppTheme', () {
    test('exposes distinct light and dark themes with correct brightness', () {
      final light = AppTheme.lightTheme;
      final dark = AppTheme.darkTheme;

      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);
      expect(dark.colorScheme.brightness, Brightness.dark);
      // Scaffolds must differ so screens actually go dark.
      expect(light.scaffoldBackgroundColor,
          isNot(equals(dark.scaffoldBackgroundColor)));
      expect(dark.scaffoldBackgroundColor, AppTheme.darkBg);
    });

    test('dark scheme keeps brand accents and readable on-surface text', () {
      final scheme = AppTheme.darkTheme.colorScheme;
      // Primary is the lightened violet (deep violet is unreadable on dark).
      expect(scheme.primary, AppTheme.violetLight);
      expect(scheme.secondary, AppTheme.goldBright);
      expect(scheme.tertiary, AppTheme.coral);
      // On-surface text is a light color so it stays visible on dark surfaces.
      expect(scheme.onSurface, AppTheme.onDark);
      expect(scheme.surface, AppTheme.darkSurface);
    });

    test('dark theme wires the surface-bearing component themes', () {
      final dark = AppTheme.darkTheme;
      // These are the components screens inherit from — if any are missing they
      // fall back to Material defaults that clash with the dark scaffold.
      expect(dark.cardTheme.color, AppTheme.darkSurface);
      expect(dark.appBarTheme.backgroundColor, AppTheme.darkAppBar);
      expect(dark.dialogTheme.backgroundColor, AppTheme.darkSurfaceHigh);
      expect(dark.bottomSheetTheme.backgroundColor, AppTheme.darkSurfaceHigh);
      expect(dark.popupMenuTheme.color, AppTheme.darkSurfaceHigh);
      expect(dark.inputDecorationTheme.filled, isTrue);
      expect(dark.chipTheme.backgroundColor, AppTheme.darkSurfaceHigh);
      expect(dark.snackBarTheme.backgroundColor, AppTheme.darkSurfaceHigh);
    });
  });

  group('ThemeController', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      // Reset to a known baseline between tests (singleton).
      ThemeController.instance.setThemeMode(ThemeMode.system);
    });

    test('defaults to system', () {
      expect(ThemeController.instance.themeMode, ThemeMode.system);
    });

    test('setThemeMode updates, notifies, and persists to shared_preferences',
        () async {
      SharedPreferences.setMockInitialValues({});
      var notified = 0;
      void listener() => notified++;
      ThemeController.instance.addListener(listener);
      addTearDown(() => ThemeController.instance.removeListener(listener));

      await ThemeController.instance.setThemeMode(ThemeMode.dark);
      expect(ThemeController.instance.themeMode, ThemeMode.dark);
      expect(notified, greaterThan(0));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('theme_mode'), 'dark');
    });

    test('load() restores the persisted preference', () async {
      SharedPreferences.setMockInitialValues({'theme_mode': 'light'});
      await ThemeController.instance.load();
      expect(ThemeController.instance.themeMode, ThemeMode.light);
    });
  });

  testWidgets('MaterialApp exposes both themes and follows the controller mode',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await ThemeController.instance.setThemeMode(ThemeMode.dark);

    await tester.pumpWidget(
      ListenableBuilder(
        listenable: ThemeController.instance,
        builder: (context, _) => MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeController.instance.themeMode,
          home: const Scaffold(body: Text('hi')),
        ),
      ),
    );

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme!.brightness, Brightness.light);
    expect(app.darkTheme!.brightness, Brightness.dark);
    expect(app.themeMode, ThemeMode.dark);

    // The resolved Theme in the tree must be the dark one.
    final ctx = tester.element(find.text('hi'));
    expect(Theme.of(ctx).brightness, Brightness.dark);

    // Switch to light and confirm the tree rebuilds to the light theme.
    // MaterialApp animates theme changes via AnimatedTheme (~200ms), so a
    // single pump would still read the mid-animation dark theme — settle it.
    await ThemeController.instance.setThemeMode(ThemeMode.light);
    await tester.pumpAndSettle();
    final ctx2 = tester.element(find.text('hi'));
    expect(Theme.of(ctx2).brightness, Brightness.light);
  });
}
