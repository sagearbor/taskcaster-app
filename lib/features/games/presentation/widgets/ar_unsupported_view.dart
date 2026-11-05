import 'package:flutter/material.dart';

import '../../../../core/services/ar/ar_capability_service.dart';

/// Friendly fallback shown when an AR task cannot run on this device. It always
/// offers a primary "Skip this task" action so a player is never stuck, plus a
/// context-specific secondary action:
///   * [ArSupport.cameraDenied]       -> "Open Settings" (deep-link to grant)
///   * [ArSupport.needsArCoreUpdate]  -> "Update AR" prompt
///
/// Pure presentational widget: all behaviour is delegated to callbacks so it is
/// trivial to test and reuses the host screen's existing skip path.
class ArUnsupportedView extends StatelessWidget {
  final ArSupport reason;

  /// Skip the task (reuses the existing SkipTask flow on the host screen).
  final VoidCallback onSkip;

  /// Open OS app settings — used for [ArSupport.cameraDenied].
  final VoidCallback? onOpenSettings;

  /// Prompt to install/update Google Play Services for AR (ARCore).
  final VoidCallback? onUpdateArCore;

  const ArUnsupportedView({
    super.key,
    required this.reason,
    required this.onSkip,
    this.onOpenSettings,
    this.onUpdateArCore,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_icon, size: 56, color: theme.colorScheme.primary),
                const SizedBox(height: 16),
                Text(
                  _title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  _message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
                // Secondary, reason-specific recovery action.
                if (_secondaryLabel != null) ...[
                  OutlinedButton.icon(
                    onPressed: _onSecondary,
                    icon: Icon(_secondaryIcon),
                    label: Text(_secondaryLabel!),
                  ),
                  const SizedBox(height: 12),
                ],
                // Primary action: never leave the player stuck.
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onSkip,
                    icon: const Icon(Icons.skip_next),
                    label: const Text('Skip this task'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData get _icon {
    switch (reason) {
      case ArSupport.cameraDenied:
        return Icons.no_photography;
      case ArSupport.needsArCoreUpdate:
        return Icons.system_update;
      case ArSupport.unsupportedPlatform:
        return Icons.view_in_ar_outlined;
      case ArSupport.unknownError:
        return Icons.error_outline;
      case ArSupport.supported:
        return Icons.view_in_ar;
    }
  }

  String get _title {
    switch (reason) {
      case ArSupport.cameraDenied:
        return 'Camera access needed';
      case ArSupport.needsArCoreUpdate:
        return 'AR needs an update';
      case ArSupport.unsupportedPlatform:
        return 'AR not available here';
      case ArSupport.unknownError:
        return 'Something went wrong';
      case ArSupport.supported:
        return 'Ready for AR';
    }
  }

  String get _message {
    switch (reason) {
      case ArSupport.cameraDenied:
        return 'This AR task uses your camera. Grant camera access in Settings '
            'to play, or skip this task to keep going.';
      case ArSupport.needsArCoreUpdate:
        return 'Google Play Services for AR is missing or out of date on this '
            'device. Update it to play, or skip this task.';
      case ArSupport.unsupportedPlatform:
        return 'This device or platform cannot run AR tasks. No worries — you '
            'can skip this one and keep playing.';
      case ArSupport.unknownError:
        return 'We could not start AR on this device. You can skip this task '
            'and keep playing.';
      case ArSupport.supported:
        return 'Your device is ready for AR.';
    }
  }

  String? get _secondaryLabel {
    switch (reason) {
      case ArSupport.cameraDenied:
        return onOpenSettings != null ? 'Open Settings' : null;
      case ArSupport.needsArCoreUpdate:
        return onUpdateArCore != null ? 'Update AR' : null;
      case ArSupport.unsupportedPlatform:
      case ArSupport.unknownError:
      case ArSupport.supported:
        return null;
    }
  }

  IconData get _secondaryIcon {
    switch (reason) {
      case ArSupport.cameraDenied:
        return Icons.settings;
      case ArSupport.needsArCoreUpdate:
        return Icons.system_update;
      case ArSupport.unsupportedPlatform:
      case ArSupport.unknownError:
      case ArSupport.supported:
        return Icons.info_outline;
    }
  }

  void _onSecondary() {
    switch (reason) {
      case ArSupport.cameraDenied:
        onOpenSettings?.call();
        break;
      case ArSupport.needsArCoreUpdate:
        onUpdateArCore?.call();
        break;
      case ArSupport.unsupportedPlatform:
      case ArSupport.unknownError:
      case ArSupport.supported:
        break;
    }
  }
}
