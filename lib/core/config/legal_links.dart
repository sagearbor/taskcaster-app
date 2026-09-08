/// Public legal pages, served from the same Firebase Hosting deploy as the web
/// app (sources: `web/privacy/index.html`, `web/terms/index.html`). Both store
/// consoles require these URLs; keep them in sync with docs/STORE_LISTING.md.
class LegalLinks {
  LegalLinks._();

  static const String privacyPolicy =
      'https://taskmaster-app-3d480.web.app/privacy/';
  static const String termsOfService =
      'https://taskmaster-app-3d480.web.app/terms/';
}
