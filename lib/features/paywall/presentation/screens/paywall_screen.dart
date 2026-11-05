import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/config/legal_links.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/services/plans/plan_repository.dart';
import '../../../../core/services/plans/plans.dart';
import '../../../../core/services/purchases/purchases_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/widgets/account_options_section.dart';
import '../paywall_launcher.dart';

/// TaskCaster Pro: plan status, what Pro adds, and (on iOS/Android) buying
/// it. Reached ONLY from Settings > TaskCaster Pro or the limit-hit prompt;
/// see [PaywallLauncher] for the placement rules.
///
/// - A guest must first "Continue with Apple/Google" (WP-01 linking keeps
///   the uid), because the Firebase uid is the RevenueCat user id and a
///   subscription must survive a reinstall.
/// - Web has no in-app purchase: it shows the plan and "Pro is available in
///   the iOS/Android app". Pro bought on mobile still shows as Pro here, since
///   the plan lives in Firestore.
/// - The plan card follows `users/{uid}.plan` (server-written), so after a
///   purchase it flips when the webhook or refreshEntitlement lands.
class PaywallScreen extends StatefulWidget {
  static const String routeName = '/paywall';

  final PaywallEntry entry;

  /// Overrides for tests; default to the service locator / platform.
  final PlanRepository? planRepository;
  final PurchasesService? purchases;
  final bool? isWeb;
  final Future<void> Function(Uri uri)? openLink;

  const PaywallScreen({
    super.key,
    required this.entry,
    this.planRepository,
    this.purchases,
    this.isWeb,
    this.openLink,
  });

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  late final PlanRepository _plans =
      widget.planRepository ?? sl<PlanRepository>();
  late final PurchasesService _purchases =
      widget.purchases ?? sl<PurchasesService>();
  late final bool _isWeb = widget.isWeb ?? kIsWeb;
  late final Stream<UserPlan> _planStream = _plans.watchPlan();

  Future<List<PaywallPackage>>? _packages;
  String? _identifiedUid;
  bool _busy = false;

  String? get _uid {
    final state = context.read<AuthBloc>().state;
    return state is AuthAuthenticated ? state.user.id : null;
  }

  /// Ties RevenueCat to this (non-anonymous) uid, then loads the offering.
  void _ensurePackages(UserPlan plan) {
    final uid = _uid;
    if (_isWeb || !_purchases.isSupported || plan.isGuest || uid == null) {
      return;
    }
    if (_identifiedUid == uid && _packages != null) return;
    _identifiedUid = uid;
    _packages = _purchases.identify(uid).then((_) => _purchases.packages());
  }

  Future<void> _open(Uri uri) async {
    final open = widget.openLink ??
        (Uri u) => launchUrl(u, mode: LaunchMode.externalApplication);
    try {
      await open(uri);
    } catch (_) {
      _snack('Could not open $uri');
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _buy(PaywallPackage pkg, UserPlan plan) async {
    setState(() => _busy = true);
    try {
      final outcome = await _purchases.purchase(pkg,
          replacingProductId: plan.productId);
      switch (outcome) {
        case PurchaseOutcome.purchased:
          _snack('Welcome to TaskCaster Pro!');
        case PurchaseOutcome.cancelled:
          break;
        case PurchaseOutcome.declined:
          _snack('The store declined that purchase. You were not charged.');
        case PurchaseOutcome.failed:
          _snack("We couldn't confirm that purchase. If you were charged, "
              'Pro shows up here shortly, or tap Restore purchases.');
        case PurchaseOutcome.notConfigured:
          _snack("Pro isn't available in this build.");
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    try {
      final uid = _uid;
      if (uid != null) await _purchases.identify(uid);
      final found = await _purchases.restore();
      _snack(found
          ? 'Purchases restored. Pro is back on.'
          : 'No TaskCaster Pro subscription found for this store account.');
    } catch (_) {
      _snack("Couldn't restore purchases right now. Please try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _manage() async {
    final url = await _purchases.managementUrl() ??
        defaultManageSubscriptionUrl();
    await _open(Uri.parse(url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(PlanCopy.proName)),
      body: StreamBuilder<UserPlan>(
        stream: _planStream,
        builder: (context, snapshot) {
          final plan = snapshot.data;
          if (plan == null) {
            return const Center(child: CircularProgressIndicator());
          }
          _ensurePackages(plan);
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _PlanStatusCard(plan: plan),
              const SizedBox(height: 20),
              if (!plan.isPro) ..._comparison(context),
              const SizedBox(height: 20),
              ..._actions(context, plan),
              const SizedBox(height: 24),
              Text(
                PlanCopy.retentionNote,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: () =>
                        _open(Uri.parse(LegalLinks.termsOfService)),
                    child: const Text('Terms of Service'),
                  ),
                  TextButton(
                    onPressed: () => _open(Uri.parse(LegalLinks.privacyPolicy)),
                    child: const Text('Privacy Policy'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _comparison(BuildContext context) {
    final theme = Theme.of(context);
    Widget column(String title, List<String> lines, {bool highlight = false}) {
      return Card(
        color: highlight ? AppTheme.violet.withOpacity(0.08) : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.check,
                          size: 18,
                          color: highlight ? AppTheme.violet : null),
                      const SizedBox(width: 8),
                      Expanded(child: Text(line)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return [
      column('Free', PlanCopy.freeFeatures),
      const SizedBox(height: 12),
      column('Pro', PlanCopy.proFeatures, highlight: true),
    ];
  }

  List<Widget> _actions(BuildContext context, UserPlan plan) {
    if (_isWeb) {
      return [
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(PlanCopy.webNote, key: Key('paywall.webNote')),
          ),
        ),
      ];
    }
    if (!_purchases.isSupported) {
      return [
        const Text(
          "Pro isn't available in this build yet. Everything in the free "
          'plan keeps working.',
          key: Key('paywall.unavailable'),
        ),
      ];
    }
    if (plan.isPro) {
      return [
        OutlinedButton(
          onPressed: _busy ? null : _manage,
          child: const Text('Manage subscription'),
        ),
        TextButton(
          onPressed: _busy ? null : _restore,
          child: const Text('Restore purchases'),
        ),
      ];
    }
    if (plan.isGuest) {
      final auth = context.read<AuthBloc>();
      return [
        Text(
          'First, keep your account',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        const Text(
          'Pro belongs to your account, so sign in with Apple or Google '
          'first. Your games and clips stay with you.',
        ),
        const SizedBox(height: 12),
        AppleSignInButton(
          key: const Key('paywall.continueApple'),
          onPressed: () => auth.add(AppleSignInRequested()),
        ),
        const SizedBox(height: 10),
        GoogleSignInButton(
          key: const Key('paywall.continueGoogle'),
          onPressed: () => auth.add(GoogleSignInRequested()),
        ),
      ];
    }
    return [
      FutureBuilder<List<PaywallPackage>>(
        future: _packages,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(),
              ),
            );
          }
          final packages = [...?snap.data]
            ..sort((a, b) => (b.isYearly ? 1 : 0) - (a.isYearly ? 1 : 0));
          if (packages.isEmpty) {
            return const Text(
              "Couldn't load Pro prices from the store. Check your "
              'connection and try again.',
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final pkg in packages) ...[
                FilledButton(
                  key: Key('paywall.buy.${pkg.productId}'),
                  onPressed: _busy ? null : () => _buy(pkg, plan),
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        pkg.isYearly ? AppTheme.violet : AppTheme.coral,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(56),
                  ),
                  child: Text(_label(pkg)),
                ),
                const SizedBox(height: 10),
              ],
              const Text(
                'Renews automatically until you cancel in your store '
                'account settings. Cancel any time.',
                textAlign: TextAlign.center,
              ),
            ],
          );
        },
      ),
      TextButton(
        onPressed: _busy ? null : _restore,
        child: const Text('Restore purchases'),
      ),
    ];
  }

  static String _label(PaywallPackage pkg) {
    switch (pkg.period) {
      case 'year':
        return '${pkg.priceString} / year';
      case 'month':
        return '${pkg.priceString} / month';
      default:
        return pkg.priceString;
    }
  }
}

class _PlanStatusCard extends StatelessWidget {
  final UserPlan plan;

  const _PlanStatusCard({required this.plan});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        leading: Icon(
          plan.isPro ? Icons.workspace_premium : Icons.person_outline,
          color: AppTheme.violet,
        ),
        title: Text(
          planTitle(plan),
          key: const Key('paywall.planTitle'),
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(planSubtitle(plan)),
      ),
    );
  }
}

/// "Pro" / "Free plan" / "Guest", for the plan card and Settings.
String planTitle(UserPlan plan) {
  switch (plan.tier) {
    case PlanTier.pro:
      return "You're Pro";
    case PlanTier.free:
      return 'Free plan';
    case PlanTier.guest:
      return 'Guest';
  }
}

/// One line under the plan title.
String planSubtitle(UserPlan plan) {
  final limits = plan.limits;
  final allowance = limits.lifetime
      ? '${limits.clipCount} clips as a guest'
      : '${limits.clipCount} clips a day, up to ${limits.clipSeconds} s';
  if (!plan.isPro) return allowance;
  final exp = plan.expiresAt;
  if (exp == null) return allowance;
  final date = '${exp.year}-${exp.month.toString().padLeft(2, '0')}-'
      '${exp.day.toString().padLeft(2, '0')}';
  if (plan.billingIssue) return '$allowance · payment issue, fix it by $date';
  return plan.willRenew
      ? '$allowance · renews $date'
      : '$allowance · ends $date';
}
