import 'dart:async';

import '../di/service_locator.dart';
import 'notification_service.dart';

/// Defers the push-notification permission prompt until the player has
/// actually reached the home screen.
///
/// Previously `main()` awaited [NotificationService.initialize] before
/// `runApp`, so on Android the very first thing a new player saw was the OS
/// "Allow TaskCaster to send you notifications?" dialog over a blank grey
/// window — before onboarding, before any explanation. Both stores' review
/// guidelines ask for permission prompts in context; this asks once, after
/// the first home-screen frame.
class NotificationPrompt {
  NotificationPrompt._();

  static bool _requested = false;

  /// Runs [NotificationService.initialize] at most once per process.
  /// Fire-and-forget: the service swallows its own platform errors.
  static void ensureRequestedOnce() {
    if (_requested) return;
    _requested = true;
    unawaited(sl<NotificationService>().initialize());
  }

  /// Test hook: allow the next [ensureRequestedOnce] to run again.
  static void resetForTest() => _requested = false;
}
