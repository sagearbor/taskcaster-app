import 'package:flutter/foundation.dart';

enum Environment { development, staging, production }

class AppConfig {
  static Environment _environment = Environment.development;
  
  static void setEnvironment(Environment env) {
    _environment = env;
  }
  
  static Environment get environment => _environment;
  
  static bool get isDevelopment => _environment == Environment.development;
  static bool get isStaging => _environment == Environment.staging;
  static bool get isProduction => _environment == Environment.production;
  
  // Firebase Configuration
  static String get firebaseProjectId {
    switch (_environment) {
      case Environment.development:
        return 'taskcaster-dev';
      case Environment.staging:
        return 'taskcaster-staging';
      case Environment.production:
        return 'taskcaster-prod';
    }
  }
  
  // API Endpoints
  static String get apiBaseUrl {
    switch (_environment) {
      case Environment.development:
        return 'http://localhost:5001/taskcaster-dev/us-central1';
      case Environment.staging:
        return 'https://staging-api.taskcasterapp.com';
      case Environment.production:
        return 'https://api.taskcasterapp.com';
    }
  }
  
  // Feature Flags
  static bool get enableAnalytics => isProduction;
  static bool get enableCrashReporting => !isDevelopment;
  static bool get enableDeepLinking => !isDevelopment;

  /// Real ads SDK is deliberately not wired up (no ad account/payment setup
  /// tonight — see docs/PRODUCT_DIRECTION.md §2.6/§7). The Arena's ad-slot
  /// cadence logic stays real and unit-tested; only the visible placeholder
  /// card is gated on this flag (and on [AdSlotCard.debugAlwaysShow] in
  /// tests/screenshots).
  static const bool adsEnabled = false;

  /// "Lab" modes: everything in the Play sheet beyond the three shipped rows
  /// (Challenge friends, Join with a code, Drawing Telephone) plus the AR Lab
  /// settings entry. Off in release builds so a stranger sees one game and one
  /// same-room mode, not a toy box. Turn on with
  /// `flutter run --dart-define=LAB_MODES=true`. The hidden modes' code stays
  /// intact — this only gates the entry points.
  static const bool labModes = bool.fromEnvironment('LAB_MODES');

  /// Test-only override for [labModes] (a compile-time const can't be flipped
  /// inside a test run). Leave null in app code.
  @visibleForTesting
  static bool? debugLabModesOverride;

  /// What UI should read: [debugLabModesOverride] if set, else [labModes].
  static bool get labModesEnabled => debugLabModesOverride ?? labModes;
  
  // Logging
  static bool get enableVerboseLogging => isDevelopment;
  static bool get enablePerformanceMonitoring => isProduction;
  
  // Cache Configuration
  static Duration get cacheExpiration {
    switch (_environment) {
      case Environment.development:
        return const Duration(minutes: 5);
      case Environment.staging:
        return const Duration(hours: 1);
      case Environment.production:
        return const Duration(days: 7);
    }
  }
  
  // Rate Limiting
  static int get maxApiCallsPerMinute {
    switch (_environment) {
      case Environment.development:
        return 1000; // No real limit in dev
      case Environment.staging:
        return 100;
      case Environment.production:
        return 60;
    }
  }
}

// Build-time configuration
class BuildConfig {
  static const String appName = String.fromEnvironment(
    'APP_NAME',
    defaultValue: 'TaskCaster',
  );
  
  static const bool useMockServices = bool.fromEnvironment(
    'USE_MOCK_SERVICES',
    defaultValue: true,
  );
  
  static const String sentryDsn = String.fromEnvironment(
    'SENTRY_DSN',
    defaultValue: '',
  );
}