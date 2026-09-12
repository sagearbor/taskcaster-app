import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_theme.dart';
import '../bloc/auth_bloc.dart';
import '../widgets/account_options_section.dart';
import '../widgets/legal_links_footer.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.openLink});

  /// Overrides how a legal-page link is opened; defaults to url_launcher.
  /// Injectable so widget tests can assert which page a link opens without
  /// touching the platform channel.
  final Future<void> Function(Uri uri)? openLink;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Guest-first: the account options (email/Google/Apple/sign-up) stay tucked
  // away until the returning user asks for them, so the very first thing a new
  // player sees is one big "Play" button.
  bool _showSignIn = false;

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listenWhen: (prev, curr) =>
          curr is AuthError || curr is AuthPasswordResetSent,
      listener: (context, state) {
        if (state is AuthError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
        } else if (state is AuthPasswordResetSent) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Password reset email sent to ${state.email}'),
            ),
          );
        }
      },
      child: Scaffold(
        // LayoutBuilder + a min-height ConstrainedBox lets the content sit
        // vertically centered on tall viewports (it used to be top-anchored,
        // leaving the bottom half of the screen empty) while staying inside
        // a SingleChildScrollView so short screens / an open keyboard still
        // scroll instead of overflowing.
        body: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Hero header (stays anchored to the top edge; the
                      // Spacer below pushes the legal footer to the bottom
                      // instead of centering the whole column, which would
                      // float the gradient header below a blank band).
                      Container(
                        decoration: const BoxDecoration(
                          gradient: AppTheme.heroGradient,
                          borderRadius: BorderRadius.vertical(
                              bottom: Radius.circular(36)),
                        ),
                        padding: EdgeInsets.fromLTRB(24,
                            MediaQuery.of(context).padding.top + 56, 24, 44),
                        child: Column(
                          children: [
                            Container(
                              width: 88,
                              height: 88,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.14),
                                borderRadius: BorderRadius.circular(26),
                                border: Border.all(
                                    color: Colors.white.withOpacity(0.25),
                                    width: 1.5),
                              ),
                              child: const Icon(Icons.star_rounded,
                                  size: 52, color: AppTheme.goldBright),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'TaskCaster',
                              style: Theme.of(context)
                                  .textTheme
                                  .displaySmall
                                  ?.copyWith(color: Colors.white),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Compete in creative challenges with friends',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                      color: Colors.white.withOpacity(0.82)),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Primary: one big Play button → guest (anonymous) sign-in.
                              SizedBox(
                                height: 64,
                                child: FilledButton.icon(
                                  onPressed: () {
                                    context
                                        .read<AuthBloc>()
                                        .add(AnonymousSignInRequested());
                                  },
                                  icon: const Icon(Icons.play_arrow_rounded,
                                      size: 32),
                                  label: const Text(
                                    'Play',
                                    style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold),
                                  ),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppTheme.coral,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              // Explains what the big Play button actually does — it's
                              // a real (anonymous) sign-in with no prompt beforehand.
                              Text(
                                'Play as a guest — no account needed. You can sign in '
                                'later to keep your progress.',
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant),
                              ),
                              const SizedBox(height: 16),
                              // Secondary: a single link that reveals the full account
                              // options for returning / registered users.
                              TextButton(
                                onPressed: () =>
                                    setState(() => _showSignIn = !_showSignIn),
                                child: Text(
                                  _showSignIn
                                      ? 'Hide sign-in options'
                                      : 'Sign in or create account',
                                ),
                              ),
                              if (_showSignIn) ...[
                                const SizedBox(height: 8),
                                const AccountOptionsSection(),
                              ],
                              const Spacer(),
                              const SizedBox(height: 24),
                              LegalLinksFooter(openLink: widget.openLink),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

}
