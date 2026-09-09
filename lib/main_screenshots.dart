/// Entry point used ONLY by scripts/capture_store_screenshots.sh to render
/// clean store-listing screenshots.
///
/// Identical to lib/main_mock.dart (mock services, no Firebase required)
/// except the debug FPS/performance overlay is hard-disabled so it never
/// appears in a captured screenshot. Not referenced by any build/release
/// script — `flutter build apk`/`flutter build ios` default to lib/main.dart.
///
/// ```bash
/// flutter build apk --debug -t lib/main_screenshots.dart
/// ```

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'core/di/service_locator.dart';
import 'core/config/environment.dart';
import 'core/error/error_handler.dart';
import 'core/cache/cache_manager.dart';
import 'core/utils/performance.dart' as perf;
import 'features/auth/domain/repositories/auth_repository.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';
import 'features/auth/presentation/screens/auth_wrapper.dart';
import 'features/onboarding/presentation/screens/onboarding_screen.dart';

void main() async {
  await _initializeApp();

  runApp(
    ErrorBoundary(
      child: perf.PerformanceOverlay(
        enabled: false, // never show the FPS badge in a screenshot
        child: const TaskCasterApp(),
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

  await ServiceLocator.init(useMockServices: true);

  await ThemeController.instance.load();
}

class TaskCasterApp extends StatelessWidget {
  const TaskCasterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => AuthBloc(
        authRepository: sl<AuthRepository>(),
      )..add(AuthCheckRequested()),
      child: ListenableBuilder(
        listenable: ThemeController.instance,
        builder: (context, _) => MaterialApp(
          title: 'TaskCaster',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeController.instance.themeMode,
          debugShowCheckedModeBanner: false,
          home: const OnboardingGate(child: AuthWrapper()),
        ),
      ),
    );
  }
}
