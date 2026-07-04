import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taskcaster_app/core/services/invite/pending_invite_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamController<Uri> links;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    links = StreamController<Uri>.broadcast();
  });

  tearDown(() => links.close());

  PendingInviteService buildService({
    Uri? initialLink,
    Future<String?> Function()? getInstallReferrer,
    bool isAndroid = true,
  }) {
    return PendingInviteService(
      getInitialLink: () async => initialLink,
      uriLinkStream: links.stream,
      getInstallReferrer: getInstallReferrer ?? () async => null,
      isAndroid: isAndroid,
    );
  }

  group('PendingInviteService — deep links', () {
    test('captures the cold-start initial link', () async {
      final service = buildService(
        initialLink: Uri.parse('taskcaster://join?code=ABC234'),
      );
      await service.init();

      expect(service.pendingCode, 'ABC234');
      expect(service.source, PendingInviteSource.link);
    });

    test('captures links arriving while running and notifies listeners',
        () async {
      final service = buildService();
      await service.init();
      expect(service.pendingCode, isNull);

      var notified = 0;
      service.addListener(() => notified++);

      links.add(Uri.parse('taskcaster://join?code=QRS789'));
      await Future<void>.delayed(Duration.zero);

      expect(service.pendingCode, 'QRS789');
      expect(service.source, PendingInviteSource.link);
      expect(notified, 1);
    });

    test('ignores unrelated or invalid links', () async {
      final service = buildService();
      await service.init();

      links.add(Uri.parse('https://example.com/join/?code=ABC234'));
      links.add(Uri.parse('taskcaster://join?code=nope!!'));
      await Future<void>.delayed(Duration.zero);

      expect(service.pendingCode, isNull);
      expect(service.source, isNull);
    });

    test('a newer link replaces an older pending code', () async {
      final service = buildService(
        initialLink: Uri.parse('taskcaster://join?code=ABC234'),
      );
      await service.init();

      links.add(Uri.parse('taskcaster://join?code=QRS789'));
      await Future<void>.delayed(Duration.zero);

      expect(service.pendingCode, 'QRS789');
    });

    test('init is idempotent', () async {
      final service = buildService(
        initialLink: Uri.parse('taskcaster://join?code=ABC234'),
      );
      await service.init();
      service.consume();
      await service.init(); // must not re-deliver the initial link

      expect(service.pendingCode, isNull);
    });
  });

  group('PendingInviteService — install referrer', () {
    test('sets the code from the referrer on first run', () async {
      final service = buildService(
        getInstallReferrer: () async => 'utm_source=x&invite_code=WXY567',
      );
      await service.init();

      expect(service.pendingCode, 'WXY567');
      expect(service.source, PendingInviteSource.referrer);
    });

    test('is only read once per install (persisted across services)',
        () async {
      var reads = 0;
      Future<String?> countingReferrer() async {
        reads++;
        return 'invite_code=WXY567';
      }

      final first = buildService(getInstallReferrer: countingReferrer);
      await first.init();
      expect(reads, 1);
      expect(first.pendingCode, 'WXY567');

      // Simulates the next app launch: same prefs, new service instance.
      final second = buildService(getInstallReferrer: countingReferrer);
      await second.init();
      expect(reads, 1);
      expect(second.pendingCode, isNull);
    });

    test('a throwing referrer plugin never crashes init and is not retried',
        () async {
      var reads = 0;
      Future<String?> throwingReferrer() {
        reads++;
        throw Exception('SERVICE_UNAVAILABLE');
      }

      final first = buildService(getInstallReferrer: throwingReferrer);
      await expectLater(first.init(), completes);
      expect(first.pendingCode, isNull);

      final second = buildService(getInstallReferrer: throwingReferrer);
      await second.init();
      expect(reads, 1);
    });

    test('does not overwrite a code that arrived via deep link', () async {
      final service = PendingInviteService(
        getInitialLink: () async => Uri.parse('taskcaster://join?code=ABC234'),
        uriLinkStream: links.stream,
        // init awaits the initial link before the referrer check, so the
        // link must already be pending when this runs.
        getInstallReferrer: () async => 'invite_code=WXY567',
        isAndroid: true,
      );
      await service.init();

      expect(service.pendingCode, 'ABC234');
      expect(service.source, PendingInviteSource.link);
    });

    test('is skipped entirely off-Android', () async {
      var reads = 0;
      final service = buildService(
        isAndroid: false,
        getInstallReferrer: () async {
          reads++;
          return 'invite_code=WXY567';
        },
      );
      await service.init();

      expect(reads, 0);
      expect(service.pendingCode, isNull);
    });

    test('an invalid referrer payload is ignored', () async {
      final service = buildService(
        getInstallReferrer: () async => 'organic install',
      );
      await service.init();

      expect(service.pendingCode, isNull);
    });
  });

  group('PendingInviteService.consume', () {
    test('returns the code once and clears it', () async {
      final service = buildService(
        initialLink: Uri.parse('taskcaster://join?code=ABC234'),
      );
      await service.init();

      var notified = 0;
      service.addListener(() => notified++);

      expect(service.consume(), 'ABC234');
      expect(service.pendingCode, isNull);
      expect(service.source, isNull);
      expect(notified, 1);

      expect(service.consume(), isNull);
      expect(notified, 1, reason: 'consuming nothing should not notify');
    });
  });
}
