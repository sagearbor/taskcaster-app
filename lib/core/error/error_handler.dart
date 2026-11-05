import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../config/environment.dart';

class ErrorHandler {
  static final _errorStreamController = StreamController<AppError>.broadcast();
  static Stream<AppError> get errorStream => _errorStreamController.stream;
  
  static void handleError(dynamic error, StackTrace? stackTrace, {String? context}) {
    final appError = AppError.from(error, stackTrace: stackTrace, context: context);
    
    if (AppConfig.enableVerboseLogging) {
      debugPrint('🔴 Error in ${appError.context}: ${appError.message}');
      if (stackTrace != null && AppConfig.isDevelopment) {
        debugPrint('Stack trace:\n$stackTrace');
      }
    }
    
    _errorStreamController.add(appError);
    
    // Report to crash reporting service in production
    if (AppConfig.enableCrashReporting && !appError.isUserError) {
      _reportToCrashlytics(appError, stackTrace);
    }
  }
  
  static void _reportToCrashlytics(AppError error, StackTrace? stackTrace) {
    // TODO: Implement Firebase Crashlytics reporting
    // FirebaseCrashlytics.instance.recordError(error, stackTrace);
  }
  
  static void showErrorSnackbar(BuildContext context, AppError error) {
    final message = AppConfig.isDevelopment 
        ? error.message 
        : error.userFriendlyMessage;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        // Critical errors use the theme's error colour; everything else
        // keeps the theme's (high-contrast) default snackbar surface.
        backgroundColor: error.severity == ErrorSeverity.critical
            ? Theme.of(context).colorScheme.error
            : null,
        action: error.canRetry 
            ? SnackBarAction(
                label: 'Retry',
                onPressed: error.retryCallback ?? () {},
              )
            : null,
      ),
    );
  }
}

class AppError {
  final String message;
  final String userFriendlyMessage;
  final ErrorType type;
  final ErrorSeverity severity;
  final String? context;
  final bool canRetry;
  final VoidCallback? retryCallback;
  final bool isUserError;
  final Map<String, dynamic>? metadata;
  
  AppError({
    required this.message,
    required this.userFriendlyMessage,
    required this.type,
    required this.severity,
    this.context,
    this.canRetry = false,
    this.retryCallback,
    this.isUserError = false,
    this.metadata,
  });
  
  factory AppError.from(dynamic error, {StackTrace? stackTrace, String? context}) {
    if (error is AppError) return error;
    
    // Network errors
    if (error.toString().contains('SocketException') || 
        error.toString().contains('ClientException')) {
      return AppError(
        message: error.toString(),
        userFriendlyMessage: 'Connection error. Please check your internet and try again.',
        type: ErrorType.network,
        severity: ErrorSeverity.medium,
        context: context,
        canRetry: true,
        isUserError: false,
      );
    }
    
    // Firebase errors
    if (error.toString().contains('firebase') || 
        error.toString().contains('firestore')) {
      return AppError(
        message: error.toString(),
        userFriendlyMessage: 'Service temporarily unavailable. Please try again.',
        type: ErrorType.backend,
        severity: ErrorSeverity.high,
        context: context,
        canRetry: true,
        isUserError: false,
      );
    }
    
    // Auth errors
    if (error.toString().contains('auth') || 
        error.toString().contains('permission')) {
      return AppError(
        message: error.toString(),
        userFriendlyMessage: 'Authentication required. Please sign in.',
        type: ErrorType.auth,
        severity: ErrorSeverity.medium,
        context: context,
        isUserError: true,
      );
    }
    
    // Default error
    return AppError(
      message: error.toString(),
      userFriendlyMessage: 'Something went wrong. Please try again.',
      type: ErrorType.unknown,
      severity: ErrorSeverity.low,
      context: context,
      canRetry: true,
    );
  }
}

enum ErrorType {
  network,
  auth,
  validation,
  backend,
  storage,
  permission,
  unknown,
}

enum ErrorSeverity {
  low,      // Log only
  medium,   // Show to user
  high,     // Notify user prominently
  critical, // Block UI, require action
}

// Error boundary widget
class ErrorBoundary extends StatefulWidget {
  final Widget child;
  final Widget Function(AppError error, VoidCallback reset)? errorBuilder;
  
  const ErrorBoundary({
    super.key,
    required this.child,
    this.errorBuilder,
  });
  
  @override
  State<ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<ErrorBoundary> {
  AppError? _error;
  
  void _resetError() {
    setState(() {
      _error = null;
    });
  }
  
  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return widget.errorBuilder?.call(_error!, _resetError) ?? 
        _DefaultErrorWidget(error: _error!, onReset: _resetError);
    }
    
    ErrorWidget.builder = (FlutterErrorDetails details) {
      final error = AppError.from(
        details.exception,
        stackTrace: details.stack,
        context: details.context?.toStringDeep(),
      );
      
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _error = error;
        });
      });
      
      return const SizedBox.shrink();
    };
    
    return widget.child;
  }
}

class _DefaultErrorWidget extends StatelessWidget {
  final AppError error;
  final VoidCallback onReset;
  
  const _DefaultErrorWidget({
    required this.error,
    required this.onReset,
  });
  
  @override
  Widget build(BuildContext context) {
    return Material(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Oops!',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                error.userFriendlyMessage,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              if (AppConfig.isDevelopment) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    error.message,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: onReset,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}