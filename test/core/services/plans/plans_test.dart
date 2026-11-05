import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/services/plans/plan_repository.dart';
import 'package:taskcaster_app/core/services/plans/plans.dart';
import 'package:taskcaster_app/core/services/video/video_policy.dart';

void main() {
  final now = DateTime.utc(2026, 11, 5, 12);

  group('PlanLimits mirror functions/src/plans.js + storage.rules', () {
    test('guest: 5 lifetime clips in the guest folder, 20 s', () {
      expect(PlanLimits.guest.clipCount, 5);
      expect(PlanLimits.guest.lifetime, isTrue);
      expect(PlanLimits.guest.clipSeconds, 20);
      expect(PlanLimits.guest.slots, ['0', '1', '2', '3', '4']);
    });

    test('free: 3 a day, 20 s, 32 MiB', () {
      expect(PlanLimits.free.clipCount, 3);
      expect(PlanLimits.free.lifetime, isFalse);
      expect(PlanLimits.free.clipSeconds, 20);
      expect(PlanLimits.free.maxUploadBytes, 32 * 1024 * 1024);
    });

    test('pro: 15 a day (0-9, a-e), 60 s, 96 MiB', () {
      expect(PlanLimits.pro.clipCount, 15);
      expect(PlanLimits.pro.slots.last, 'e');
      expect(PlanLimits.pro.clipSeconds, 60);
      expect(PlanLimits.pro.maxUploadBytes, 96 * 1024 * 1024);
    });

    test('products and entitlement', () {
      expect(PlanProducts.entitlement, 'pro');
      expect(PlanProducts.all,
          ['taskcaster_pro_monthly', 'taskcaster_pro_yearly']);
      expect(PlanProducts.periodOf('taskcaster_pro_yearly:yearly'), 'year');
      expect(PlanProducts.periodOf('taskcaster_pro_monthly'), 'month');
    });
  });

  group('UserPlan.fromUserDoc (same test as storage.rules isPro)', () {
    test('no doc: free when signed in, guest when anonymous', () {
      expect(UserPlan.fromUserDoc(null, isAnonymous: false).tier,
          PlanTier.free);
      expect(UserPlan.fromUserDoc(null, isAnonymous: true).tier,
          PlanTier.guest);
    });

    test('pro with a future expiry is pro; a past expiry is free', () {
      final future = UserPlan.fromUserDoc({
        'plan': 'pro',
        'planExpiresAt': now.add(const Duration(days: 3)),
        'planWillRenew': true,
        'planProductId': 'taskcaster_pro_yearly',
        'planStore': 'app_store',
      }, isAnonymous: false, now: now);
      expect(future.isPro, isTrue);
      expect(future.willRenew, isTrue);
      expect(future.productId, 'taskcaster_pro_yearly');
      expect(future.limits, PlanLimits.pro);

      final past = UserPlan.fromUserDoc({
        'plan': 'pro',
        'planExpiresAt': now.subtract(const Duration(seconds: 1)),
      }, isAnonymous: false, now: now);
      expect(past.tier, PlanTier.free);
    });

    test('pro with no expiry (an admin grant) is pro', () {
      expect(
          UserPlan.fromUserDoc({'plan': 'pro'}, isAnonymous: false, now: now)
              .isPro,
          isTrue);
    });

    test('accepts ISO strings and epoch millis for timestamps', () {
      final plan = UserPlan.fromUserDoc({
        'plan': 'pro',
        'planExpiresAt': now.add(const Duration(days: 1)).toIso8601String(),
        'planLapsedAt': now.millisecondsSinceEpoch,
      }, isAnonymous: false, now: now);
      expect(plan.isPro, isTrue);
      expect(plan.lapsedAt, isNotNull);
    });
  });

  group('MockPlanRepository', () {
    test('emits the current plan, then every change', () async {
      final repo = MockPlanRepository();
      final seen = <PlanTier>[];
      final sub = repo.watchPlan().listen((p) => seen.add(p.tier));
      await Future<void>.delayed(Duration.zero);
      repo.plan = const UserPlan(tier: PlanTier.pro);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(seen, [PlanTier.free, PlanTier.pro]);
      expect((await repo.currentPlan()).isPro, isTrue);
    });
  });

  group('VideoPolicy plan paths', () {
    test('guest clips go to the lifetime guest folder', () {
      expect(
        VideoPolicy.storagePathFor(
            userId: 'g1', when: now, slot: '4', limits: PlanLimits.guest),
        'submissions/g1/guest/4',
      );
    });

    test('free and pro clips go to today\'s UTC folder', () {
      expect(
        VideoPolicy.storagePathFor(
            userId: 'u1', when: now, slot: 'e', limits: PlanLimits.pro),
        'submissions/u1/20261105/e',
      );
    });

    test('a slot the plan does not have throws', () {
      expect(
        () => VideoPolicy.storagePathFor(
            userId: 'u1', when: now, slot: '3', limits: PlanLimits.free),
        throwsArgumentError,
      );
      expect(
        () => VideoPolicy.storagePathFor(
            userId: 'g1', when: now, slot: '5', limits: PlanLimits.guest),
        throwsArgumentError,
      );
    });
  });

  group('Copy: never promise to keep data forever (owner rule 2026-11-05)',
      () {
    test('PlanCopy says neither "forever" nor "unlimited storage"', () {
      final all = [
        ...PlanCopy.freeFeatures,
        ...PlanCopy.proFeatures,
        PlanCopy.retentionNote,
        PlanCopy.webNote,
        for (final t in PlanTier.values) ...[
          PlanCopy.limitTitle(t),
          PlanCopy.limitBody(t),
        ],
      ].join('\n').toLowerCase();
      expect(all, isNot(contains('forever')));
      expect(all, isNot(contains('unlimited storage')));
      expect(all, isNot(contains('permanent')));
    });

    test('no paywall or plan source file says "forever"', () {
      final files = [
        ...Directory('lib/features/paywall').listSync(recursive: true),
        File('lib/core/services/plans/plans.dart'),
        File('lib/features/settings/presentation/screens/settings_screen.dart'),
        File('docs/MONETIZATION.md'),
      ].whereType<File>().where((f) => f.existsSync());
      for (final f in files) {
        final text = f.readAsStringSync().toLowerCase();
        // MONETIZATION.md quotes the rule itself ("never say forever").
        final scrubbed = text
            .replaceAll('"forever"', '')
            .replaceAll('"unlimited storage"', '')
            .replaceAll('never say forever', '')
            .replaceAll("'forever'", '')
            .replaceAll('delete_forever', '');
        expect(scrubbed.contains('unlimited storage'), isFalse,
            reason: f.path);
        if (!f.path.endsWith('.md')) {
          expect(scrubbed.contains('forever'), isFalse, reason: f.path);
        }
      }
    });
  });
}
