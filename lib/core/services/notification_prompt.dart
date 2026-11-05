import 'dart:async';

import '../di/service_locator.dart';
import 'notification_service.dart';

/// Runs push-notification setup once the player has reached the home screen.
///
/// Setup no longer ASKS for anything. It used to: on Android the OS
/// "Allow TaskCaster to send you notifications?" dialog fired on the first
/// home frame, before the player had posted a clip or had any reason to want
/// a notification. The ask now lives on the Posted screen after the first
/// post (PushOptInCard), on every platform, matching web. What remains here
/// is [NotificationService.initialize]: foreground handlers, token-refresh
/// tracking, and re-registering the token of someone who already said yes.
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
