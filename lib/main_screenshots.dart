/// Entry point used ONLY by the store-screenshot captures
/// (scripts/capture_store_screenshots.sh and
/// integration_test/capture_ios_screenshots_test.dart).
///
/// Runs the real app shell from lib/main.dart ([TaskCasterApp]: cold open ->
/// Starter Pack -> Home) on mock services — no Firebase, no network, nothing
/// written anywhere but memory — with the debug FPS overlay hard-disabled so
/// it never appears in a captured screenshot. Not referenced by any
/// build/release script: `flutter build apk`/`flutter build ios` default to
/// lib/main.dart.
///
/// ```bash
/// flutter build apk --debug -t lib/main_screenshots.dart
/// ```

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/cache/cache_manager.dart';
import 'core/config/environment.dart';
import 'core/di/service_locator.dart';
import 'core/error/error_handler.dart';
import 'core/theme/theme_controller.dart';
import 'core/utils/performance.dart' as perf;
import 'main.dart' show TaskCasterApp;

void main() async {
  await _initializeApp();

  runApp(
    const ErrorBoundary(
      child: perf.PerformanceOverlay(
        enabled: false, // never show the FPS badge in a screenshot
        child: TaskCasterApp(),
      ),
    ),
  );
}

Future<void> _initializeApp() async {
  WidgetsFlutterBinding.ensureInitialized();

  AppConfig.setEnvironment(Environment.development);

  FlutterError.onError = (details) {
    ErrorHandler.handleError(
      details.exception,
      details.stack,
      context: 'Flutter Framework',
    );
  };

  await CacheManager.instance;

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Mock services only: the captures must never touch production.
  await ServiceLocator.init(useMockServices: true);

  await ThemeController.instance.load();
}
