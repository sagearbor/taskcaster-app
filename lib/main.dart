/// Main entry point for TaskCaster
/// Run with: flutter run -d chrome

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

import 'core/theme/app_theme.dart';
import 'core/widgets/backend_unavailable_screen.dart';
import 'core/theme/theme_controller.dart';
import 'core/di/service_locator.dart';
import 'core/services/app_check/app_check_bootstrap.dart';
import 'core/services/invite/pending_invite_service.dart';
import 'core/services/purchases/purchases_service.dart';
import 'features/auth/domain/repositories/auth_repository.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';
import 'features/games/domain/repositories/game_repository.dart';
import 'features/games/presentation/bloc/games_bloc.dart';
import 'features/games/presentation/screens/task_execution_screen.dart';
import 'features/games/presentation/widgets/pending_invite_gate.dart';
import 'features/games/presentation/widgets/pending_share_gate.dart';
import 'features/home/presentation/screens/home_screen.dart';
import 'features/onboarding/presentation/screens/cold_open_screen.dart';
import 'features/onboarding/presentation/screens/onboarding_screen.dart';
import 'features/tasks/data/datasources/starter_pack_data.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await _initFirebase();
  } catch (e) {
    if (!kDebugMode) {
      // Release/profile: never fall back to mocks. A mock app looks playable
      // but saves nothing and cannot play with anyone, which would hide a
      // broken platform config (e.g. a bad GoogleService-Info.plist) behind
      // a working-looking UI. Show an honest error with Retry instead; a
      // successful retry continues the normal startup below.
      debugPrint('Firebase unavailable: $e');
      await ThemeController.instance.load();
      runApp(_BackendUnavailableApp(onRetry: () async {
        await _initFirebase();
        await _startApp(useMockServices: false);
      }));
      return;
    }
    // Debug only: if Firebase isn't configured for this platform yet (see
    // docs/MOBILE_SETUP.md), fall back to mock services so the app still
    // launches for local UI work instead of crashing on startup.
    debugPrint('Firebase unavailable — DEBUG build, starting on mocks: $e');
    await _startApp(useMockServices: true);
    return;
  }

  await _startApp(useMockServices: false);
}

Future<void> _initFirebase() async {
  // A previous attempt may have registered the default app before failing
  // later on; initialising it twice would throw duplicate-app.
  if (Firebase.apps.isNotEmpty) return;
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
}

Future<void> _startApp({required bool useMockServices}) async {
  await ServiceLocator.init(useMockServices: useMockServices);

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

  // App Check (monitor mode). A no-op unless this build was given the
  // APP_CHECK_WEB_KEY / APP_CHECK dart-defines; see AppCheckBootstrap.
  if (!useMockServices) await AppCheckBootstrap.activate();

  // WP-11: RevenueCat's app user id is the Firebase uid. Re-identify on
  // every auth change (sign-in, guest -> Apple/Google link, sign-out); a
  // no-op on web and in builds without a RevenueCat key.
  if (!useMockServices) {
    PurchasesIdentitySync(sl<PurchasesService>()).start(
      fb_auth.FirebaseAuth.instance.userChanges().map((u) =>
          u == null ? null : (uid: u.uid, isAnonymous: u.isAnonymous)),
    );
  }

  runApp(const TaskCasterApp());
}

/// Release-build startup failure shell: just the themed error screen.
class _BackendUnavailableApp extends StatelessWidget {
  final Future<void> Function() onRetry;

  const _BackendUnavailableApp({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TaskCaster',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeController.instance.themeMode,
      debugShowCheckedModeBanner: false,
      home: BackendUnavailableScreen(onRetry: onRetry),
    );
  }
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
          // An invite link (or web ?join=) with nobody signed in skips the
          // cold open: silent guest sign-in, then the join dialog (WP-07).
          home: const PendingInviteGuestSignIn(child: AuthScreen()),
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
          // PendingShareGate (WP-09) opens /t/, /c/ and /p/ share links.
          return const PendingInviteGate(
            child: PendingShareGate(child: HomeScreen()),
          );
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
