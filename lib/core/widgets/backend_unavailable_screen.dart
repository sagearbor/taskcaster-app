import 'package:flutter/material.dart';

/// Shown by a release build when Firebase could not be initialised at startup.
///
/// Debug builds fall back to mock services instead (see main.dart). A release
/// build must not: on mocks the app looks playable but saves nothing and
/// cannot play with anyone, which hides a broken platform config from both the
/// player and us. So the player gets an honest error and a Retry button.
class BackendUnavailableScreen extends StatefulWidget {
  /// Tries to bring the backend up again. Returns normally on success (the
  /// caller then replaces this screen with the real app) and throws on
  /// failure, in which case this screen stays up and offers Retry again.
  final Future<void> Function() onRetry;

  const BackendUnavailableScreen({super.key, required this.onRetry});

  @override
  State<BackendUnavailableScreen> createState() =>
      _BackendUnavailableScreenState();
}

class _BackendUnavailableScreenState extends State<BackendUnavailableScreen> {
  bool _retrying = false;
  bool _failedAgain = false;

  Future<void> _retry() async {
    setState(() {
      _retrying = true;
      _failedAgain = false;
    });
    try {
      await widget.onRetry();
    } catch (e) {
      debugPrint('Backend still unavailable: $e');
      if (mounted) setState(() => _failedAgain = true);
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_off,
                  size: 64,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 16),
                Text(
                  "Can't reach TaskCaster",
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  _failedAgain
                      ? 'Still no luck. Check your connection and try again.'
                      : 'Check your connection and try again.',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  key: const ValueKey('backend-unavailable-retry'),
                  onPressed: _retrying ? null : _retry,
                  icon: _retrying
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
