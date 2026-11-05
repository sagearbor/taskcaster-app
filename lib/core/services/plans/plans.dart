/// TaskCaster plans (audit WP-11): the client's MIRROR of the tier table, for
/// UI only (labels, which slots to try, the recorder's length cap). What is
/// enforced lives on the server: `functions/src/plans.js`, `storage.rules`
/// (clip count + size, read from the server-owned `users/{uid}.plan`), the
/// transcode (clip length) and the montage trigger (Pro host). Changing a
/// number here without changing it there only changes what the app SAYS.
///
/// Retention copy must never promise indefinite retention (owner rule
/// 2026-11-05); see [PlanCopy].
library;

/// Who the player is, plan-wise.
enum PlanTier {
  /// Anonymous Firebase Auth session: 5 clips, ever.
  guest,

  /// Signed in with Apple / Google / email, no active subscription.
  free,

  /// Active `pro` entitlement (RevenueCat -> users/{uid}.plan == 'pro').
  pro,
}

/// Store product ids and the RevenueCat entitlement. Must match the App
/// Store Connect / Play Console products and the RevenueCat project.
class PlanProducts {
  const PlanProducts._();

  static const String entitlement = 'pro';
  static const String monthly = 'taskcaster_pro_monthly';
  static const String yearly = 'taskcaster_pro_yearly';
  static const List<String> all = [monthly, yearly];

  /// Shown only when the store has not returned its localized prices yet.
  static const String monthlyFallbackPrice = r'$5';
  static const String yearlyFallbackPrice = r'$25';

  /// 'month' / 'year' from a product id (Play may append ":basePlan").
  static String periodOf(String productId) {
    final id = productId.split(':').first;
    if (id == yearly) return 'year';
    if (id == monthly) return 'month';
    return '';
  }
}

/// The per-plan clip limits.
class PlanLimits {
  final PlanTier tier;

  /// Longest clip, seconds. The recorder stops here; the server trims to it.
  final int clipSeconds;

  /// Largest upload, bytes (storage.rules freeMaxBytes / proMaxBytes).
  final int maxUploadBytes;

  /// The Storage slots this plan may write, in the order the uploader tries
  /// them. Today's folder for free/pro; the lifetime `guest` folder for a
  /// guest.
  final List<String> slots;

  /// True when [slots] is a lifetime allowance rather than a daily one.
  final bool lifetime;

  const PlanLimits._({
    required this.tier,
    required this.clipSeconds,
    required this.maxUploadBytes,
    required this.slots,
    required this.lifetime,
  });

  static const int _mib = 1024 * 1024;

  static const PlanLimits guest = PlanLimits._(
    tier: PlanTier.guest,
    clipSeconds: 20,
    maxUploadBytes: 32 * _mib,
    slots: ['0', '1', '2', '3', '4'],
    lifetime: true,
  );

  static const PlanLimits free = PlanLimits._(
    tier: PlanTier.free,
    clipSeconds: 20,
    maxUploadBytes: 32 * _mib,
    slots: ['0', '1', '2'],
    lifetime: false,
  );

  static const PlanLimits pro = PlanLimits._(
    tier: PlanTier.pro,
    clipSeconds: 60,
    maxUploadBytes: 96 * _mib,
    slots: [
      '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', //
      'a', 'b', 'c', 'd', 'e',
    ],
    lifetime: false,
  );

  static PlanLimits of(PlanTier tier) {
    switch (tier) {
      case PlanTier.guest:
        return guest;
      case PlanTier.free:
        return free;
      case PlanTier.pro:
        return pro;
    }
  }

  /// How many clips the plan allows ([lifetime] or per UTC day).
  int get clipCount => slots.length;
}

/// The signed-in player's plan, read from the server-owned fields on
/// `users/{uid}`. The client never writes any of them.
class UserPlan {
  final PlanTier tier;

  /// End of the paid period (grace included); null for none / no expiry.
  final DateTime? expiresAt;

  /// When Pro last ended (the retention clock), if it ever did.
  final DateTime? lapsedAt;

  /// 'active' | 'cancelled' | 'billing_issue' | 'paused' | 'expired' | ...
  final String? status;
  final bool willRenew;
  final bool billingIssue;
  final String? productId;
  final String? pendingProductId;

  /// 'app_store' | 'play_store' | ...
  final String? store;

  const UserPlan({
    required this.tier,
    this.expiresAt,
    this.lapsedAt,
    this.status,
    this.willRenew = false,
    this.billingIssue = false,
    this.productId,
    this.pendingProductId,
    this.store,
  });

  static const UserPlan guest = UserPlan(tier: PlanTier.guest);
  static const UserPlan free = UserPlan(tier: PlanTier.free);

  bool get isPro => tier == PlanTier.pro;
  bool get isGuest => tier == PlanTier.guest;
  PlanLimits get limits => PlanLimits.of(tier);

  /// Same test as functions/src/plans.js effectivePlan() and storage.rules
  /// isPro(): `plan == 'pro'` and no expiry, or an expiry in the future. An
  /// anonymous session is a guest whatever the doc says (a guest cannot buy).
  factory UserPlan.fromUserDoc(
    Map<String, dynamic>? data, {
    required bool isAnonymous,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final expiresAt = _toDate(data?['planExpiresAt']);
    final isPro = data?['plan'] == 'pro' &&
        (expiresAt == null || expiresAt.isAfter(at));
    final tier = isPro
        ? PlanTier.pro
        : (isAnonymous ? PlanTier.guest : PlanTier.free);
    return UserPlan(
      tier: tier,
      expiresAt: expiresAt,
      lapsedAt: _toDate(data?['planLapsedAt']),
      status: data?['planStatus'] as String?,
      willRenew: data?['planWillRenew'] == true,
      billingIssue: data?['planBillingIssue'] == true,
      productId: data?['planProductId'] as String?,
      pendingProductId: data?['planPendingProductId'] as String?,
      store: data?['planStore'] as String?,
    );
  }

  /// Firestore Timestamp (duck-typed, so this file needs no Firebase import),
  /// DateTime, ISO string or epoch millis.
  static DateTime? _toDate(Object? v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is String) return DateTime.tryParse(v);
    try {
      // cloud_firestore Timestamp
      return (v as dynamic).toDate() as DateTime;
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is UserPlan &&
      other.tier == tier &&
      other.expiresAt == expiresAt &&
      other.lapsedAt == lapsedAt &&
      other.status == status &&
      other.willRenew == willRenew &&
      other.billingIssue == billingIssue &&
      other.productId == productId &&
      other.pendingProductId == pendingProductId &&
      other.store == store;

  @override
  int get hashCode => Object.hash(tier, expiresAt, lapsedAt, status, willRenew,
      billingIssue, productId, pendingProductId, store);
}

/// Player-facing plan copy, in one place so a test can check none of it
/// promises indefinite retention.
class PlanCopy {
  const PlanCopy._();

  static const String proName = 'TaskCaster Pro';

  static const List<String> freeFeatures = [
    '3 clips a day, up to 20 seconds',
    'Photo and text posts any time',
    'Play and grade in any game',
    'Clips are kept for 90 days (favorites up to a year)',
  ];

  static const List<String> proFeatures = [
    '15 clips a day, up to 60 seconds',
    'Finale and moments reels for every game you host, for everyone in it',
    'Your clips are kept while you subscribe',
    'Support a tiny indie party game',
  ];

  /// The retention line under the plan card / paywall. Accurate and modest:
  /// nothing here may promise indefinite or unbounded storage.
  static const String retentionNote =
      'Free clips are deleted after 90 days (favorites after a year). Pro '
      'clips are kept while you subscribe and deleted within a year after '
      'Pro ends. Deleting your account deletes everything right away.';

  static const String webNote =
      'Pro is available in the TaskCaster iOS and Android app. If you '
      'subscribed there, sign in with the same account and Pro works here '
      'too.';

  /// What a player who just hit a limit is told.
  static String limitTitle(PlanTier tier) {
    switch (tier) {
      case PlanTier.guest:
        return 'You have used your ${PlanLimits.guest.clipCount} guest clips';
      case PlanTier.free:
        return "That's your ${PlanLimits.free.clipCount} clips for today";
      case PlanTier.pro:
        return "That's your ${PlanLimits.pro.clipCount} clips for today";
    }
  }

  static String limitBody(PlanTier tier) {
    switch (tier) {
      case PlanTier.guest:
        return 'Post this one as a photo, or sign in free for '
            '${PlanLimits.free.clipCount} clips every day.';
      case PlanTier.free:
        return 'Post this one as a photo, or go Pro for '
            '${PlanLimits.pro.clipCount} clips a day, up to '
            '${PlanLimits.pro.clipSeconds} seconds each.';
      case PlanTier.pro:
        return 'Post this one as a photo; your clips refill tomorrow '
            '(UTC midnight).';
    }
  }
}
