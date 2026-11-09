import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// `history.replaceState(history.state, '', url)`: same page, new address-bar
/// URL, no reload and no extra Back entry.
void replaceBrowserUrl(String url) {
  final history = globalContext.getProperty<JSObject?>('history'.toJS);
  if (history == null) return;
  history.callMethod<JSAny?>(
    'replaceState'.toJS,
    history.getProperty<JSAny?>('state'.toJS),
    ''.toJS,
    url.toJS,
  );
}
