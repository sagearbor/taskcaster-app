// In-app subscriptions via RevenueCat (purchases_flutter), audit WP-11.
//
// Keys come ONLY from --dart-define at build time (public SDK keys, safe to
// ship in the binary; the orchestrator fills them in):
//   REVENUECAT_IOS_KEY      appl_...   (App Store)
//   REVENUECAT_ANDROID_KEY  goog_...   (Google Play)
// No key for the running platform (and always on web) -> the service is
// unsupported, nothing touches the RevenueCat SDK, and the paywall says Pro
// is not available in this build. See docs/MONETIZATION.md.
//
// The SERVER is the source of truth for the plan (users/{uid}.plan, written
// by the revenuecatWebhook / refreshEntitlement Cloud Functions); the client
// never writes it. After a purchase or restore we ask the server to re-sync
// so the plan card flips without waiting for the webhook.
//
// Identity: the RevenueCat app user id IS the Firebase uid, and only a
// non-anonymous account may buy (a guest first links Apple/Google, which
// keeps the uid). [PurchasesService.identify] is called on every auth change.

import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart' show PlatformException;
import 'package:purchases_flutter/purchases_flutter.dart';

import '../plans/plans.dart';

const String _iosKey = String.fromEnvironment('REVENUECAT_IOS_KEY');
const String _androidKey = String.fromEnvironment('REVENUECAT_ANDROID_KEY');

/// The RevenueCat public SDK key for the running platform, or '' if none.
/// Web has no in-app purchase (Pro bought on mobile still applies there,
/// because the plan lives in Firestore).
String revenueCatKeyForPlatform() {
  if (kIsWeb) return '';
  switch (defaultTargetPlatform) {
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return _iosKey;
    case TargetPlatform.android:
      return _androidKey;
    default:
      return '';
  }
}

/// One purchasable option on the paywall.
class PaywallPackage {
  final String id;
  final String priceString;

  /// 'month' | 'year' | '' — drives the "/month" "/year" suffix.
  final String period;

  /// Store product id (Play may append ":basePlan").
  final String productId;

  /// The SDK's Package, for [PurchasesService.purchase]. Null in fakes.
  final Object? raw;

  const PaywallPackage({
    required this.id,
    required this.priceString,
    required this.period,
    required this.productId,
    this.raw,
  });

  bool get isYearly => period == 'year';
}

/// [failed] = the outcome is unknown (network drop, store problem, payment
/// pending): the store MAY have charged, so the plan card is the truth.
/// [declined] = the store refused before charging.
enum PurchaseOutcome { purchased, cancelled, declined, failed, notConfigured }

/// The paywall talks only to this. Mock builds and tests use
/// [UnconfiguredPurchasesService] or [FakePurchasesService].
abstract class PurchasesService {
  /// True when this build can sell Pro on this platform (mobile + a key).
  bool get isSupported;

  /// Tie RevenueCat to the Firebase uid. Null (signed out) or a guest logs
  /// RevenueCat out; it never configures for an anonymous uid.
  Future<void> identify(String? uid, {bool isAnonymous = false});

  /// The current offering's packages (monthly + yearly), store-priced.
  Future<List<PaywallPackage>> packages();

  /// Buy [pkg]. [replacingProductId] is the store product the user is on
  /// now (users/{uid}.planProductId): on Google Play a monthly <-> yearly
  /// switch must name it so the old subscription is replaced, not doubled.
  Future<PurchaseOutcome> purchase(PaywallPackage pkg,
      {String? replacingProductId});

  /// Restore Purchases. True when an active `pro` entitlement was found.
  Future<bool> restore();

  /// The store's manage-subscription page, when known.
  Future<String?> managementUrl();
}

/// No IAP here (web, desktop, or a build without the key).
class UnconfiguredPurchasesService implements PurchasesService {
  const UnconfiguredPurchasesService();

  @override
  bool get isSupported => false;
  @override
  Future<void> identify(String? uid, {bool isAnonymous = false}) async {}
  @override
  Future<List<PaywallPackage>> packages() async => const [];
  @override
  Future<PurchaseOutcome> purchase(PaywallPackage pkg,
          {String? replacingProductId}) async =>
      PurchaseOutcome.notConfigured;
  @override
  Future<bool> restore() async => false;
  @override
  Future<String?> managementUrl() async => null;
}

/// Asks the server to re-read RevenueCat (callable `refreshEntitlement`).
typedef EntitlementRefresher = Future<void> Function();

Future<void> _callRefreshEntitlement() async {
  await FirebaseFunctions.instanceFor(region: 'us-central1')
      .httpsCallable('refreshEntitlement')
      .call<dynamic>();
}

/// The real thing, on iOS and Android.
class RevenueCatPurchasesService implements PurchasesService {
  final String apiKey;
  final EntitlementRefresher _refresh;

  RevenueCatPurchasesService(this.apiKey, {EntitlementRefresher? refresh})
      : _refresh = refresh ?? _callRefreshEntitlement;

  bool _configured = false;
  String? _uid;

  @override
  bool get isSupported => apiKey.isNotEmpty;

  @override
  Future<void> identify(String? uid, {bool isAnonymous = false}) async {
    if (!isSupported) return;
    try {
      if (uid == null || isAnonymous) {
        if (_configured && _uid != null) {
          await Purchases.logOut();
          _uid = null;
        }
        return;
      }
      if (!_configured) {
        // appUserID = Firebase uid from the very first call, so a purchase is
        // never attached to an anonymous RevenueCat id.
        await Purchases.configure(PurchasesConfiguration(apiKey)..appUserID = uid);
        _configured = true;
        _uid = uid;
        return;
      }
      if (_uid != uid) {
        await Purchases.logIn(uid);
        _uid = uid;
      }
    } catch (e) {
      // Never let billing plumbing break sign-in.
      debugPrint('RevenueCat identify failed: $e');
    }
  }

  @override
  Future<List<PaywallPackage>> packages() async {
    if (!_configured || _uid == null) return const [];
    try {
      final offerings = await Purchases.getOfferings();
      final current = offerings.current;
      if (current == null) return const [];
      return current.availablePackages.map((p) {
        final productId = p.storeProduct.identifier;
        final period = switch (p.packageType) {
          PackageType.monthly => 'month',
          PackageType.annual => 'year',
          _ => PlanProducts.periodOf(productId),
        };
        return PaywallPackage(
          id: p.identifier,
          priceString: p.storeProduct.priceString,
          period: period,
          productId: productId,
          raw: p,
        );
      }).toList();
    } catch (e) {
      debugPrint('RevenueCat getOfferings failed: $e');
      return const [];
    }
  }

  @override
  Future<PurchaseOutcome> purchase(PaywallPackage pkg,
      {String? replacingProductId}) async {
    final p = pkg.raw;
    if (!_configured || _uid == null || p is! Package) {
      return PurchaseOutcome.notConfigured;
    }
    final old = replacingProductId?.split(':').first;
    final change = defaultTargetPlatform == TargetPlatform.android &&
            old != null &&
            old.isNotEmpty &&
            old != pkg.productId.split(':').first
        ? StoreProductChangeInfo(old)
        : null;
    try {
      final result = await Purchases.purchase(
          PurchaseParams.package(p, productChangeInfo: change));
      await _syncServer();
      return result.customerInfo.entitlements.active
              .containsKey(PlanProducts.entitlement)
          ? PurchaseOutcome.purchased
          : PurchaseOutcome.failed;
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        return PurchaseOutcome.cancelled;
      }
      debugPrint('purchase failed: $code ${e.message}');
      return const {
        PurchasesErrorCode.purchaseNotAllowedError,
        PurchasesErrorCode.purchaseInvalidError,
        PurchasesErrorCode.productNotAvailableForPurchaseError,
        PurchasesErrorCode.ineligibleError,
        PurchasesErrorCode.insufficientPermissionsError,
      }.contains(code)
          ? PurchaseOutcome.declined
          : PurchaseOutcome.failed;
    } catch (e) {
      debugPrint('purchase error: $e');
      return PurchaseOutcome.failed;
    }
  }

  @override
  Future<bool> restore() async {
    if (!_configured || _uid == null) return false;
    final info = await Purchases.restorePurchases();
    await _syncServer();
    return info.entitlements.active.containsKey(PlanProducts.entitlement);
  }

  @override
  Future<String?> managementUrl() async {
    if (!_configured) return null;
    try {
      return (await Purchases.getCustomerInfo()).managementURL;
    } catch (_) {
      return null;
    }
  }

  /// Best effort: the webhook gets there too, a few seconds later.
  Future<void> _syncServer() async {
    try {
      await _refresh();
    } catch (e) {
      debugPrint('refreshEntitlement failed (webhook will catch up): $e');
    }
  }
}

/// The service for this build and platform.
PurchasesService createPurchasesService() {
  final key = revenueCatKeyForPlatform();
  return key.isEmpty
      ? const UnconfiguredPurchasesService()
      : RevenueCatPurchasesService(key);
}

/// Store manage-subscription page when RevenueCat has no managementURL.
String defaultManageSubscriptionUrl() {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    return 'https://apps.apple.com/account/subscriptions';
  }
  return 'https://play.google.com/store/account/subscriptions';
}

/// Test / mock-mode double: scripted packages and outcomes, every call
/// recorded.
class FakePurchasesService implements PurchasesService {
  @override
  bool isSupported;
  List<PaywallPackage> offered;
  PurchaseOutcome outcome;
  bool restoreResult;

  final List<String?> identified = [];
  final List<String> purchased = [];
  int restores = 0;

  FakePurchasesService({
    this.isSupported = true,
    this.outcome = PurchaseOutcome.purchased,
    this.restoreResult = false,
    List<PaywallPackage>? offered,
  }) : offered = offered ??
            const [
              PaywallPackage(
                id: r'$rc_monthly',
                priceString: r'$5.00',
                period: 'month',
                productId: PlanProducts.monthly,
              ),
              PaywallPackage(
                id: r'$rc_annual',
                priceString: r'$25.00',
                period: 'year',
                productId: PlanProducts.yearly,
              ),
            ];

  @override
  Future<void> identify(String? uid, {bool isAnonymous = false}) async {
    identified.add(isAnonymous ? null : uid);
  }

  @override
  Future<List<PaywallPackage>> packages() async =>
      isSupported ? offered : const [];

  @override
  Future<PurchaseOutcome> purchase(PaywallPackage pkg,
      {String? replacingProductId}) async {
    purchased.add(pkg.productId);
    return isSupported ? outcome : PurchaseOutcome.notConfigured;
  }

  @override
  Future<bool> restore() async {
    restores += 1;
    return restoreResult;
  }

  @override
  Future<String?> managementUrl() async => null;
}

/// Keeps RevenueCat's user in step with Firebase Auth: call [start] once at
/// startup with the auth stream ((uid, isAnonymous) or null when signed out).
class PurchasesIdentitySync {
  final PurchasesService service;
  StreamSubscription<({String uid, bool isAnonymous})?>? _sub;

  PurchasesIdentitySync(this.service);

  void start(Stream<({String uid, bool isAnonymous})?> authChanges) {
    if (!service.isSupported) return;
    _sub?.cancel();
    _sub = authChanges.listen(
      (user) => service.identify(user?.uid, isAnonymous: user?.isAnonymous ?? false),
      onError: (Object _) {},
    );
  }

  Future<void> dispose() async => _sub?.cancel();
}
