import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// Consistent error UI component with retry functionality
class ErrorView extends StatelessWidget {
  final String message;
  final String? details;
  final VoidCallback? onRetry;
  final IconData icon;
  final Color? iconColor;

  /// Tint the icon with the theme's warning token (e.g. offline) instead of
  /// the error colour.
  final bool warning;

  /// Marks a non-error, "muted" state (empty / not-found) so the icon falls
  /// back to the theme's neutral colour instead of the error colour.
  final bool _neutral;

  const ErrorView({
    super.key,
    required this.message,
    this.details,
    this.onRetry,
    this.icon = Icons.error_outline,
    this.iconColor,
    this.warning = false,
    bool neutral = false,
  }) : _neutral = neutral;

  /// Factory constructor for network errors
  factory ErrorView.network({
    VoidCallback? onRetry,
    String? customMessage,
  }) {
    return ErrorView(
      message: customMessage ?? 'Connection error',
      details: 'Please check your internet connection and try again.',
      icon: Icons.wifi_off,
      warning: true,
      onRetry: onRetry,
    );
  }

  /// Factory constructor for permission errors
  factory ErrorView.permission({
    required String permission,
    VoidCallback? onRetry,
  }) {
    return ErrorView(
      message: 'Permission required',
      details: 'This app needs $permission permission to continue.',
      icon: Icons.lock_outline,
      onRetry: onRetry,
    );
  }

  /// Factory constructor for empty state
  factory ErrorView.empty({
    required String entity,
    String? action,
    VoidCallback? onAction,
  }) {
    return ErrorView(
      message: 'No $entity found',
      details: action != null ? 'Tap below to $action' : null,
      icon: Icons.inbox,
      neutral: true,
      onRetry: onAction,
    );
  }

  /// Factory constructor for not found errors
  factory ErrorView.notFound({
    required String entity,
    VoidCallback? onRetry,
  }) {
    return ErrorView(
      message: '$entity not found',
      details: 'The requested $entity could not be found.',
      icon: Icons.search_off,
      neutral: true,
      onRetry: onRetry,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 80,
              color: iconColor ??
                  (warning
                      ? context.tokens.warning
                      : _neutral
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.error.withOpacity(0.6)),
            ),
            const SizedBox(height: 24),
            Text(
              message,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            if (details != null) ...[
              const SizedBox(height: 12),
              Text(
                details!,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A smaller inline error widget for form fields or sections
class InlineError extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const InlineError({
    super.key,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.error.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            color: theme.colorScheme.error,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: theme.colorScheme.error,
                fontSize: 14,
              ),
            ),
          ),
          if (onRetry != null)
            IconButton(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              iconSize: 20,
              color: theme.colorScheme.error,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
        ],
      ),
    );
  }
}