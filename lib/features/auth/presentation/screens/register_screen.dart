import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_theme.dart';
import '../bloc/auth_bloc.dart';
import '../widgets/auth_form.dart';
import '../widgets/legal_links_footer.dart';

class RegisterScreen extends StatelessWidget {
  const RegisterScreen({super.key, this.openLink});

  /// Overrides how a legal-page link is opened; defaults to url_launcher.
  /// Injectable so widget tests can assert which page a link opens without
  /// touching the platform channel.
  final Future<void> Function(Uri uri)? openLink;

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthAuthenticated) {
          // Sign-up succeeded — close this pushed route so the AuthWrapper
          // underneath shows the home screen. Without this the new account is
          // created but the register screen stays on top ("nothing happens").
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
                Text(
                  'Join the Party!',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: AppTheme.violet,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Create an account to start playing',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 36),
                AuthForm(
                  title: 'Create Account',
                  buttonText: 'Sign Up',
                  onSubmit: (email, password, displayName) {
                    context.read<AuthBloc>().add(
                          SignUpRequested(
                            email: email,
                            password: password,
                            displayName: displayName ?? 'Player',
                          ),
                        );
                  },
                  showDisplayNameField: true,
                ),
                const SizedBox(height: 20),
                LegalConsentText(openLink: openLink),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
