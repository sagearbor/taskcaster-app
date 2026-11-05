import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/services/app_check/app_check_bootstrap.dart';

void main() {
  group('AppCheckBootstrap.planFor', () {
    test('web with no site key stays off', () {
      expect(
        AppCheckBootstrap.planFor(
            isWeb: true, webSiteKey: '', mobileEnabled: true),
        AppCheckPlan.off,
      );
      expect(
        AppCheckBootstrap.planFor(
            isWeb: true, webSiteKey: '  ', mobileEnabled: false),
        AppCheckPlan.off,
      );
    });

    test('web with a site key uses reCAPTCHA Enterprise', () {
      expect(
        AppCheckBootstrap.planFor(
            isWeb: true, webSiteKey: 'site-key', mobileEnabled: false),
        AppCheckPlan.web,
      );
    });

    test('mobile is off unless APP_CHECK=true', () {
      expect(
        AppCheckBootstrap.planFor(
            isWeb: false, webSiteKey: 'site-key', mobileEnabled: false),
        AppCheckPlan.off,
      );
      expect(
        AppCheckBootstrap.planFor(
            isWeb: false, webSiteKey: '', mobileEnabled: true),
        AppCheckPlan.mobile,
      );
    });

    test('activate is a no-op in a build without the dart-defines', () async {
      // No platform channel is mocked: this would throw if it tried to
      // activate, so completing proves the default build leaves it off.
      await AppCheckBootstrap.activate();
    });
  });
}
