import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_theme.dart';
import '../bloc/auth_bloc.dart';
import '../screens/register_screen.dart';
import 'auth_form.dart';

/// The full set of "returning / registered user" sign-in options: email +
/// password, Google, Apple, forgot-password and sign-up. Pulled out of
/// [LoginScreen] so the cold-open first-run screen can reveal the exact same
/// options behind its own "Sign in" link instead of duplicating them.
class AccountOptionsSection extends StatelessWidget {
  const AccountOptionsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AuthForm(
          title: 'Sign In',
          buttonText: 'Sign In',
          onSubmit: (email, password, displayName) {
            context.read<AuthBloc>().add(
                  SignInRequested(email: email, password: password),
                );
          },
          showDisplayNameField: false,
        ),
        const SizedBox(height: 20),
        const OrDivider(),
        const SizedBox(height: 20),
        GoogleSignInButton(
          onPressed: () {
            context.read<AuthBloc>().add(GoogleSignInRequested());
          },
        ),
        const SizedBox(height: 12),
        AppleSignInButton(
          onPressed: () {
            context.read<AuthBloc>().add(AppleSignInRequested());
          },
        ),
        TextButton(
          onPressed: () => showForgotPasswordDialog(context),
          child: const Text('Forgot password?'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BlocProvider.value(
                  value: context.read<AuthBloc>(),
                  child: const RegisterScreen(),
                ),
              ),
            );
          },
          child: const Text('Don\'t have an account? Sign up'),
        ),
      ],
    );
  }
}

/// Shared "reset password" dialog used from both [LoginScreen] and the
/// cold-open screen's revealed [AccountOptionsSection].
void showForgotPasswordDialog(BuildContext context) {
  final controller = TextEditingController();
  final authBloc = context.read<AuthBloc>();
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Reset Password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
              'Enter your account email and we\'ll send you a reset link.'),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            keyboardType: TextInputType.emailAddress,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'you@example.com',
              prefixIcon: Icon(Icons.email_outlined),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final email = controller.text.trim();
            if (email.isEmpty) return;
            authBloc.add(PasswordResetRequested(email: email));
            Navigator.of(dialogContext).pop();
          },
          child: const Text('Send'),
        ),
      ],
    ),
  );
}

/// "or" separator between the email form and the social/guest options.
class OrDivider extends StatelessWidget {
  const OrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final line = Expanded(
      child: Divider(color: AppTheme.violet.withOpacity(0.18), thickness: 1),
    );
    return Row(
      children: [
        line,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'or',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppTheme.inkSoft),
          ),
        ),
        line,
      ],
    );
  }
}

/// "Continue with Google" button — white surface, multicolor "G", per
/// Google's branding guidance.
class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const _GoogleGlyph(),
      label: const Text('Continue with Google'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.ink,
        backgroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        side: BorderSide(color: AppTheme.ink.withOpacity(0.18), width: 1.5),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    );
  }
}

/// "Continue with Apple" button — black surface, white Apple glyph, per
/// Apple's Sign in with Apple button guidelines.
class AppleSignInButton extends StatelessWidget {
  const AppleSignInButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.apple, size: 22, color: Colors.white),
      label: const Text('Continue with Apple'),
      style: ElevatedButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: Colors.black,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 16),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    );
  }
}

/// The Google "G" rendered without bundling an asset: a recognizable, branded
/// glyph drawn from text so there is no extra image dependency.
class _GoogleGlyph extends StatelessWidget {
  const _GoogleGlyph();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: const Text(
        'G',
        style: TextStyle(
          fontFamily: 'PlusJakartaSans',
          fontWeight: FontWeight.w800,
          fontSize: 16,
          color: Color(0xFF4285F4),
        ),
      ),
    );
  }
}
