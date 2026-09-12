import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/widgets/account_options_section.dart';
import '../../../auth/presentation/widgets/legal_links_footer.dart';
import '../../../games/presentation/widgets/task_reveal_card.dart';

/// Tap 1. Replaces onboarding + login for a not-yet-authenticated player:
/// one dark screen, the wordmark, and the first starter task itself — no
/// feature list, no separate login gate (see docs/PRODUCT_DIRECTION.md §4).
///
/// Pure/presentational: the task content and the Start action are passed in
/// by the caller (lib/main.dart), which is what wires the real
/// `StarterPackData.tasks().first` and the `AnonymousSignInRequested` +
/// `StartStarterPack` flow. That keeps this screen trivially testable without
/// a bloc.
class ColdOpenScreen extends StatefulWidget {
  final String taskTitle;
  final String taskDescription;
  final int timerSeconds;
  final VoidCallback onStart;

  /// Overrides how a legal-page link is opened; defaults to url_launcher.
  final Future<void> Function(Uri uri)? openLink;

  const ColdOpenScreen({
    super.key,
    required this.taskTitle,
    required this.taskDescription,
    required this.timerSeconds,
    required this.onStart,
    this.openLink,
  });

  @override
  State<ColdOpenScreen> createState() => _ColdOpenScreenState();
}

class _ColdOpenScreenState extends State<ColdOpenScreen> {
  bool _showSignIn = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.violetDeep,
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(gradient: AppTheme.heroGradient),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: ConstrainedBox(
                  constraints:
                      BoxConstraints(minHeight: constraints.maxHeight - 40),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Wordmark(),
                        const SizedBox(height: 28),
                        Text(
                          'Your first task, should you accept it…',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                color: Colors.white.withOpacity(0.9),
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: 18),
                        Theme(
                          // The reveal card is designed for a light surface;
                          // give it one here rather than adapting its colours
                          // for a dark backdrop everywhere else in the app.
                          data: Theme.of(context).copyWith(
                            cardColor: Colors.white,
                            textTheme:
                                Theme.of(context).textTheme.apply(
                                      bodyColor: AppTheme.ink,
                                      displayColor: AppTheme.ink,
                                    ),
                          ),
                          child: TaskRevealCard(
                            title: widget.taskTitle,
                            description: widget.taskDescription,
                            timerSeconds: widget.timerSeconds,
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          height: 60,
                          child: FilledButton(
                            onPressed: widget.onStart,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.coral,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: Text(
                              'Start — ${widget.timerSeconds} s',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Post yours to unlock everyone else\'s. '
                          'No account needed.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.white.withOpacity(0.78),
                              ),
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: () =>
                              setState(() => _showSignIn = !_showSignIn),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white.withOpacity(0.85),
                          ),
                          child: Text(
                            _showSignIn ? 'Hide sign in' : 'Sign in',
                          ),
                        ),
                        if (_showSignIn) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const AccountOptionsSection(),
                          ),
                        ],
                        const Spacer(),
                        const SizedBox(height: 20),
                        Theme(
                          data: Theme.of(context).copyWith(
                            textTheme: Theme.of(context).textTheme.apply(
                                  bodyColor: Colors.white.withOpacity(0.75),
                                  displayColor: Colors.white,
                                ),
                          ),
                          child: LegalLinksFooter(openLink: widget.openLink),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.14),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.25), width: 1.5),
          ),
          child: const Icon(Icons.star_rounded, size: 32, color: AppTheme.goldBright),
        ),
        const SizedBox(height: 10),
        Text(
          'TASKCASTER',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                letterSpacing: 3,
              ),
        ),
      ],
    );
  }
}
