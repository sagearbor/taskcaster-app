import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_theme.dart';
import '../bloc/auth_bloc.dart';
import '../widgets/account_options_section.dart'
    show AppleSignInButton, GoogleSignInButton, OrDivider;
import '../widgets/auth_form.dart';

/// Guest-upgrade flow: converts the current anonymous account into a permanent
/// account WITHOUT losing the uid (so game history is kept). Email/password
/// links via upgradeGuestAccount; Google/Apple link the provider credential
/// to the guest (see FirebaseAuthDataSource._linkOrSignIn).
class CreateAccountScreen extends StatelessWidget {
  const CreateAccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listenWhen: (prev, curr) =>
          curr is AuthAuthenticated || curr is AuthError,
      listener: (context, state) {
        if (state is AuthAuthenticated) {
          // Upgrade succeeded — close this route; the screens beneath rebuild
          // with the now-permanent account.
          // A notice means the Google/Apple identity already had an account
          // and the session moved to it, so "progress is saved" would be a
          // lie; say what actually happened instead.
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.notice ??
                  'Account created — your progress is saved!'),
            ),
          );
          Navigator.of(context).pop();
        } else if (state is AuthError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Create Account')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Icon(Icons.workspace_premium_rounded,
                    size: 56, color: AppTheme.gold),
                const SizedBox(height: 12),
                Text(
                  'Save Your Progress',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: AppTheme.violet,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Create an account to keep your games, scores and avatar '
                  'across devices. Your current games stay with you.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                AuthForm(
                  title: 'Create Account',
                  buttonText: 'Create Account',
                  onSubmit: (email, password, displayName) {
                    context.read<AuthBloc>().add(
                          UpgradeGuestRequested(
                            email: email,
                            password: password,
                            displayName: displayName ?? 'Player',
                          ),
                        );
                  },
                  showDisplayNameField: true,
                ),
                const SizedBox(height: 20),
                const OrDivider(),
                const SizedBox(height: 20),
                GoogleSignInButton(
                  onPressed: () =>
                      context.read<AuthBloc>().add(GoogleSignInRequested()),
                ),
                const SizedBox(height: 12),
                AppleSignInButton(
                  onPressed: () =>
                      context.read<AuthBloc>().add(AppleSignInRequested()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
