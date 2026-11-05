import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/services/plans/plans.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/widgets/account_options_section.dart';

/// The sheet a player sees when a clip did not fit their plan (WP-11).
///
/// The free way out always comes first and is the primary button: post the
/// attempt as a photo, which every plan can do. Only then "Sign in free"
/// (a guest) and "Go Pro". Nothing here blocks the free loop.
class UpgradePrompt extends StatelessWidget {
  final PlanTier tier;
  final VoidCallback? onPostAsPhoto;
  final VoidCallback? onSignInFree;
  final VoidCallback? onGoPro;

  const UpgradePrompt({
    super.key,
    required this.tier,
    this.onPostAsPhoto,
    this.onSignInFree,
    this.onGoPro,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              PlanCopy.limitTitle(tier),
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(PlanCopy.limitBody(tier), style: theme.textTheme.bodyMedium),
            const SizedBox(height: 20),
            if (onPostAsPhoto != null) ...[
              FilledButton.icon(
                key: const Key('upgradePrompt.postAsPhoto'),
                onPressed: onPostAsPhoto,
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Post it as a photo instead'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.coral,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (onSignInFree != null) ...[
              OutlinedButton(
                key: const Key('upgradePrompt.signInFree'),
                onPressed: onSignInFree,
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48)),
                child: Text(
                    'Sign in free (${PlanLimits.free.clipCount} clips a day)'),
              ),
              const SizedBox(height: 10),
            ],
            if (onGoPro != null) ...[
              OutlinedButton(
                key: const Key('upgradePrompt.goPro'),
                onPressed: onGoPro,
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48)),
                child: const Text('Go Pro'),
              ),
              const SizedBox(height: 4),
            ],
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Not now'),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Sign in free" for a guest: link Apple or Google to the guest account
/// (WP-01 linking keeps the uid, so their games and clips stay theirs).
Future<void> showGuestSignInSheet(BuildContext context) {
  final authBloc = context.read<AuthBloc>();
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Keep your account',
              style: Theme.of(sheetContext)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
                'Your games, clips and scores stay with you. Free, no card.'),
            const SizedBox(height: 16),
            AppleSignInButton(onPressed: () {
              Navigator.of(sheetContext).pop();
              authBloc.add(AppleSignInRequested());
            }),
            const SizedBox(height: 10),
            GoogleSignInButton(onPressed: () {
              Navigator.of(sheetContext).pop();
              authBloc.add(GoogleSignInRequested());
            }),
          ],
        ),
      ),
    ),
  );
}
