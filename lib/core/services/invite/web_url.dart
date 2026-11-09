/// Replaces the browser's current URL without reloading or adding a history
/// entry (`history.replaceState`). A no-op off the web.
library;

export 'web_url_stub.dart' if (dart.library.js_interop) 'web_url_web.dart';
