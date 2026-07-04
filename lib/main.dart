/// Main entry point for TaskCaster
/// Run with: flutter run -d chrome

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'core/di/service_locator.dart';
import 'core/services/invite/pending_invite_service.dart';
import 'core/services/notification_service.dart';
import 'features/auth/domain/repositories/auth_repository.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';
import 'features/auth/presentation/screens/login_screen.dart';
import 'features/games/presentation/widgets/pending_invite_gate.dart';
import 'features/home/presentation/screens/home_screen.dart';
import 'features/onboarding/presentation/screens/onboarding_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Try to bring up Firebase. If it isn't configured for this platform yet
  // (e.g. Android before `flutterfire configure`, see docs/MOBILE_SETUP.md),
  // fall back to mock services so the app still launches and is fully playable
  // instead of crashing on startup.
  var useMock = false;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase unavailable — starting in offline/demo mode: $e');
    useMock = true;
  }

  await ServiceLocator.init(useMockServices: useMock);

  // Start capturing friend-invite deep links / install referrer immediately
  // (fire-and-forget: never blocks or crashes startup — the service swallows
  // platform errors internally).
  unawaited(sl<PendingInviteService>().init());

  // Load the persisted theme preference before first frame.
  await ThemeController.instance.load();

  // Initialize push notifications (best-effort; never blocks startup). Only
  // meaningful with real services.
  if (!useMock) {
    try {
      await sl<NotificationService>().initialize();
    } catch (_) {
      // Messaging is optional; ignore failures (e.g. web without VAPID setup).
    }
  }

  runApp(const TaskCasterApp());
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
          home: const OnboardingGate(child: AuthScreen()),
        ),
      ),
    );
  }
}

class AuthScreen extends StatelessWidget {
  const AuthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        if (state is AuthLoading) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (state is AuthAuthenticated) {
          // PendingInviteGate pops the "join your friend's game?" dialog when
          // an invite code arrived via deep link or install referrer. Mounted
          // only when authenticated so joinGame always has a real user.
          return const PendingInviteGate(child: HomeScreen());
        }

        // Default to login screen
        return const LoginScreen();
      },
    );
  }
}