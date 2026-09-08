/// Public legal pages, served from the same Firebase Hosting deploy as the web
/// app (sources: `web/privacy/index.html`, `web/terms/index.html`,
/// `web/delete-account/index.html`). Both store consoles require these URLs;
/// keep them in sync with docs/STORE_LISTING.md.
class LegalLinks {
  LegalLinks._();

  static const String privacyPolicy =
      'https://taskmaster-app-3d480.web.app/privacy/';
  static const String termsOfService =
      'https://taskmaster-app-3d480.web.app/terms/';

  /// Describes how to delete an account and its data, including the
  /// in-app self-service flow (Settings -> Delete Account) and a way to
  /// request deletion without installing the app. Required by Play policy
  /// and App Store guideline 5.1.1(v).
  static const String accountDeletion =
      'https://taskmaster-app-3d480.web.app/delete-account/';
}
