/// Browser Push API access, behind an interface.
///
/// The real implementation is a thin call into `web/push.js` through
/// js_interop; everything else in the app (and every test) sees only this.
/// Conditional import picks the web one at compile time so `dart:js_interop`
/// never reaches a mobile or VM build.
library;

import 'push_gateway_stub.dart' if (dart.library.js_interop) 'push_gateway_web.dart';

/// What the browser will say about push, without asking the user anything.
enum PushPermission {
  /// This browser cannot do web push (or the page is not a secure context).
  unsupported,

  /// Never asked. This is the only state worth showing an opt-in prompt in.
  prompt,

  /// Already opted in.
  granted,

  /// Already said no. Asking again does nothing — the browser will not
  /// re-prompt, so the app must not pretend it can.
  denied,
}

/// A browser push subscription, ready to be persisted for the server to use.
class PushSubscription {
  /// The push service URL this browser listens on.
  final String endpoint;

  /// Client public key for payload encryption.
  final String p256dh;

  /// Client auth secret for payload encryption.
  final String auth;

  const PushSubscription({
    required this.endpoint,
    required this.p256dh,
    required this.auth,
  });

  /// A stable id for this subscription: the endpoint is the identity, but it
  /// is a long URL with characters Firestore map keys cannot hold, so we key
  /// by a hash of it. Same browser re-subscribing overwrites its own entry
  /// instead of accumulating duplicates.
  String get id => stableIdForEndpoint(endpoint);

  Map<String, Object?> toMap() => {
        'endpoint': endpoint,
        'p256dh': p256dh,
        'auth': auth,
      };

  /// Parses the JSON that `window.taskcasterPushSubscribe()` resolves with.
  /// Returns null for anything malformed rather than throwing — a browser
  /// handing back a surprise is a "no push this time", not a crash.
  static PushSubscription? fromJson(Map<String, Object?> json) {
    final endpoint = json['endpoint'];
    final p256dh = json['p256dh'];
    final auth = json['auth'];
    if (endpoint is! String || endpoint.isEmpty) return null;
    if (p256dh is! String || p256dh.isEmpty) return null;
    if (auth is! String || auth.isEmpty) return null;
    return PushSubscription(endpoint: endpoint, p256dh: p256dh, auth: auth);
  }
}

/// FNV-1a (32-bit) over the endpoint, hex. Short, stable, and free of the `/`
/// and `.` that Firestore field paths treat specially.
///
/// 32-bit, not 64: dart2js cannot represent the 64-bit FNV constants exactly,
/// so the wider variant compiles on the VM and fails the web build outright —
/// and web is the only platform this code runs on. 32 bits is ample for the
/// handful of browsers one person subscribes from.
String stableIdForEndpoint(String endpoint) {
  const prime = 0x01000193;
  const mask = 0xFFFFFFFF;
  var hash = 0x811c9dc5;
  for (final unit in endpoint.codeUnits) {
    hash = (hash ^ unit) & mask;
    hash = (hash * prime) & mask;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

/// The browser Push API, or a no-op on platforms that have none.
abstract class PushGateway {
  /// The platform implementation: real on web, no-op everywhere else.
  factory PushGateway() = PlatformPushGateway;

  /// What the browser says right now, without prompting.
  PushPermission permission();

  /// Prompt (if needed) and subscribe. Null when the player says no, the
  /// browser cannot, or anything at all goes wrong.
  Future<PushSubscription?> subscribe();
}

/// Test double. Returns whatever it was built with and records the calls.
class FakePushGateway implements PushGateway {
  PushPermission _permission;
  final PushSubscription? subscription;
  int subscribeCalls = 0;

  FakePushGateway({
    PushPermission permission = PushPermission.prompt,
    this.subscription,
  }) : _permission = permission;

  /// Lets a test simulate the browser's state changing after a prompt
  /// (e.g. `prompt` becoming `denied` once the user has refused).
  void setPermission(PushPermission value) => _permission = value;

  @override
  PushPermission permission() => _permission;

  @override
  Future<PushSubscription?> subscribe() async {
    subscribeCalls++;
    return subscription;
  }
}
