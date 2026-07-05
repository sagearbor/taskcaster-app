import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/services/invite/pending_invite_service.dart';
import '../../../../core/theme/app_theme.dart';

/// First-run intro that explains the core loop in a few on-brand pages.
///
/// Shown once (gated by [OnboardingGate]); the "seen" flag is persisted with
/// shared_preferences. Skippable, with a "Let's play" button on the last page.
class OnboardingScreen extends StatefulWidget {
  /// Called when the user finishes or skips the intro.
  final VoidCallback onFinish;

  const OnboardingScreen({super.key, required this.onFinish});

  static const String prefsKey = 'seen_onboarding';

  /// Whether the intro has already been shown. Best-effort: defaults to "not
  /// seen" (false) if storage is unavailable so the intro still appears.
  static Future<bool> hasBeenSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(prefsKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> markSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(prefsKey, true);
    } catch (_) {
      // Non-fatal; the user just sees the intro again next launch.
    }
  }

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _page = 0;

  // Trimmed to a single page that names the full spread of game types (not
  // just video tasks), so a new player sees the breadth at a glance and gets
  // to "play" in one tap.
  static const List<_OnboardingPage> _pages = [
    _OnboardingPage(
      icon: Icons.celebration_rounded,
      title: 'Party games for everyone',
      body: 'Film silly video-task challenges, play Drawing Telephone, buzz '
          'in on Trivia, or pop balloons in AR — solo or with friends, '
          'online or side-by-side. Jump in and play.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isLast => _page == _pages.length - 1;

  Future<void> _finish() async {
    await OnboardingScreen.markSeen();
    widget.onFinish();
  }

  void _next() {
    if (_isLast) {
      _finish();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.heroGradient),
        child: SafeArea(
          child: Column(
            children: [
              // Skip
              Align(
                alignment: Alignment.topRight,
                child: TextButton(
                  onPressed: _finish,
                  child: Text(
                    'Skip',
                    style: TextStyle(color: Colors.white.withOpacity(0.85)),
                  ),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _pages.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (context, i) => _buildPage(context, _pages[i]),
                ),
              ),
              _buildDots(),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _next,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.goldBright,
                      foregroundColor: AppTheme.violetDeep,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: Text(_isLast ? "Let's play" : 'Next'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPage(BuildContext context, _OnboardingPage page) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 132,
            height: 132,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(36),
              border: Border.all(
                  color: Colors.white.withOpacity(0.22), width: 1.5),
            ),
            child: Icon(page.icon, size: 72, color: AppTheme.goldBright),
          ),
          const SizedBox(height: 40),
          Text(
            page.title,
            style: Theme.of(context)
                .textTheme
                .displaySmall
                ?.copyWith(color: Colors.white),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            page.body,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.white.withOpacity(0.85),
                  height: 1.5,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_pages.length, (i) {
        final active = i == _page;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active ? AppTheme.goldBright : Colors.white.withOpacity(0.4),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}

class _OnboardingPage {
  final IconData icon;
  final String title;
  final String body;

  const _OnboardingPage({
    required this.icon,
    required this.title,
    required this.body,
  });
}

/// Decides whether to show [OnboardingScreen] on launch or fall through to
/// [child] (the normal auth flow). Wired into both app entry points.
class OnboardingGate extends StatefulWidget {
  final Widget child;

  const OnboardingGate({super.key, required this.child});

  @override
  State<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<OnboardingGate> {
  bool? _seen;

  @override
  void initState() {
    super.initState();
    // A friend's invite is already waiting (deep link / install referrer) —
    // skip the intro entirely and get straight to joining it. Best-effort:
    // guarded so a missing service in tests can never crash the gate.
    if (_hasPendingInvite()) {
      _seen = true;
      return;
    }
    OnboardingScreen.hasBeenSeen().then((seen) {
      if (mounted) setState(() => _seen = seen);
    });
  }

  bool _hasPendingInvite() {
    try {
      return sl<PendingInviteService>().pendingCode != null;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Still resolving the flag — keep it on-brand (no flash of white).
    if (_seen == null) {
      return const Scaffold(
        backgroundColor: AppTheme.violet,
        body: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    if (_seen == false) {
      return OnboardingScreen(
        onFinish: () => setState(() => _seen = true),
      );
    }

    return widget.child;
  }
}
