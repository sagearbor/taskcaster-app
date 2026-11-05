import 'package:flutter/material.dart';

import '../../../core/services/plans/plans.dart';
import 'screens/paywall_screen.dart';
import 'widgets/upgrade_prompt.dart';

/// Where a paywall presentation came from. These are the ONLY places it may
/// appear (WP-11 placement rules). It never appears on cold open, invite /
/// join, the first task, grading or Watch together.
enum PaywallEntry {
  /// Settings > TaskCaster Pro.
  settings,

  /// The player hit a plan limit (clips), from the upgrade prompt.
  clipLimit,
}

/// The single way any screen shows the paywall or the upgrade prompt, so the
/// placement rules can be tested by swapping in [RecordingPaywallLauncher]
/// and walking the flows where it must never show.
abstract class PaywallLauncher {
  /// Push the full TaskCaster Pro screen.
  Future<void> openPaywall(BuildContext context, {required PaywallEntry entry});

  /// The limit-hit sheet: always a free way out first ([onPostAsPhoto]),
  /// then "Sign in free" for a guest and "Go Pro".
  Future<void> showLimitPrompt(
    BuildContext context, {
    required PlanTier tier,
    VoidCallback? onPostAsPhoto,
  });
}

class DefaultPaywallLauncher implements PaywallLauncher {
  const DefaultPaywallLauncher();

  @override
  Future<void> openPaywall(BuildContext context,
      {required PaywallEntry entry}) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PaywallScreen(entry: entry),
        settings: const RouteSettings(name: PaywallScreen.routeName),
      ),
    );
  }

  @override
  Future<void> showLimitPrompt(
    BuildContext context, {
    required PlanTier tier,
    VoidCallback? onPostAsPhoto,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => UpgradePrompt(
        tier: tier,
        onPostAsPhoto: onPostAsPhoto == null
            ? null
            : () {
                Navigator.of(sheetContext).pop();
                onPostAsPhoto();
              },
        onSignInFree: tier == PlanTier.guest
            ? () {
                Navigator.of(sheetContext).pop();
                showGuestSignInSheet(context);
              }
            : null,
        onGoPro: tier == PlanTier.pro
            ? null
            : () {
                Navigator.of(sheetContext).pop();
                openPaywall(context, entry: PaywallEntry.clipLimit);
              },
      ),
    );
  }
}

/// Test double: records every presentation instead of showing anything.
class RecordingPaywallLauncher implements PaywallLauncher {
  final List<String> presentations = [];

  @override
  Future<void> openPaywall(BuildContext context,
      {required PaywallEntry entry}) async {
    presentations.add('paywall:${entry.name}');
  }

  @override
  Future<void> showLimitPrompt(
    BuildContext context, {
    required PlanTier tier,
    VoidCallback? onPostAsPhoto,
  }) async {
    presentations.add('limit:${tier.name}');
  }
}
