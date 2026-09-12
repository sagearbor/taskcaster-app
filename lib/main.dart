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
import 'features/auth/domain/repositories/auth_repository.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';
import 'features/games/domain/repositories/game_repository.dart';
import 'features/games/presentation/bloc/games_bloc.dart';
import 'features/games/presentation/screens/task_execution_screen.dart';
import 'features/games/presentation/widgets/pending_invite_gate.dart';
import 'features/home/presentation/screens/home_screen.dart';
import 'features/onboarding/presentation/screens/cold_open_screen.dart';
import 'features/onboarding/presentation/screens/onboarding_screen.dart';
import 'features/tasks/data/datasources/starter_pack_data.dart';

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

  // The cold-open screen (see ColdOpenScreen / AuthScreen below) replaces the
  // old OnboardingGate -> OnboardingScreen -> LoginScreen chain for new
  // players, so there is no separate intro to show. Mark it seen so nothing
  // in the app ever falls back to showing OnboardingScreen. Fire-and-forget:
  // best-effort, like every other use of this flag.
  unawaited(OnboardingScreen.markSeen());

  // Load the persisted theme preference before first frame.
  await ThemeController.instance.load();

  // Push-notification setup (and its OS permission prompt) is deliberately
  // NOT done here: it runs once the player reaches the home screen, via
  // NotificationPrompt.ensureRequestedOnce(), so the first thing a new player
  // sees is the first task rather than a permission dialog on a blank window.

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
          home: const AuthScreen(),
        ),
      ),
    );
  }
}

/// Tap 1: a NOT-authenticated user sees the cold open (the first starter
/// task itself, see ColdOpenScreen) instead of onboarding + a login gate.
/// Tapping Start signs them in as a guest, and the moment auth completes this
/// widget opens their Starter Pack game and pushes the first task on top of
/// Home — see docs/PRODUCT_DIRECTION.md §4. A returning authenticated user
/// goes straight to Home, unchanged.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  // Set the instant Start is tapped on the cold open; consumed the moment
  // AuthAuthenticated arrives so a returning user's ordinary sign-in never
  // triggers the starter-pack launch.
  bool _launchStarterPackOnAuth = false;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthAuthenticated && _launchStarterPackOnAuth) {
          _launchStarterPackOnAuth = false;
          _openStarterPack();
        }
      },
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

        final firstTask = StarterPackData.tasks().first;
        return ColdOpenScreen(
          taskTitle: firstTask.title,
          taskDescription: firstTask.description,
          timerSeconds: firstTask.durationSeconds ?? 90,
          onStart: () {
            _launchStarterPackOnAuth = true;
            context.read<AuthBloc>().add(AnonymousSignInRequested());
          },
        );
      },
    );
  }

  /// Opens (or resumes) the user's Starter Pack game and pushes the next
  /// task on top of Home, with the timer already running (`autoStart: true`)
  /// — "Tap 1" of docs/PRODUCT_DIRECTION.md §4. Uses its own short-lived
  /// GamesBloc rather than reaching into Home's, since Home may not have
  /// finished building this GamesBloc yet.
  Future<void> _openStarterPack() async {
    final bloc = GamesBloc(
      gameRepository: sl<GameRepository>(),
      authRepository: sl<AuthRepository>(),
    )..add(const StartStarterPack());

    await for (final state in bloc.stream) {
      if (state is StarterPackReady) {
        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TaskExecutionScreen(
                gameId: state.gameId,
                taskIndex: state.taskIndex,
                autoStart: true,
              ),
            ),
          );
        }
        break;
      }
      if (state is GamesError) break;
    }
    await bloc.close();
  }
}
