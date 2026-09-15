/// Web [PushGateway]: calls the three functions `web/push.js` puts on
/// `window`.
///
/// The Push API itself is deliberately NOT reimplemented in Dart. Keeping it
/// in plain JS means the permission prompt, the service-worker registration
/// and the VAPID key all live in one readable file that can be poked at from
/// a browser console, and Dart only has to move a JSON string.
library;

import 'dart:convert';

import 'dart:js_interop';

import 'package:flutter/foundation.dart';

import 'push_gateway.dart';

@JS('taskcasterPushSupported')
external JSBoolean? _supported();

@JS('taskcasterPushPermission')
external JSString? _permission();

@JS('taskcasterPushSubscribe')
external JSPromise<JSString?>? _subscribe();

class PlatformPushGateway implements PushGateway {
  @override
  PushPermission permission() {
    try {
      // push.js missing entirely (an old cached index.html) reads as
      // unsupported rather than throwing into the UI.
      if (_supported()?.toDart != true) return PushPermission.unsupported;
      switch (_permission()?.toDart) {
        case 'granted':
          return PushPermission.granted;
        case 'denied':
          return PushPermission.denied;
        case 'default':
          return PushPermission.prompt;
        default:
          return PushPermission.unsupported;
      }
    } catch (e) {
      debugPrint('PushGateway.permission failed: $e');
      return PushPermission.unsupported;
    }
  }

  @override
  Future<PushSubscription?> subscribe() async {
    try {
      final promise = _subscribe();
      if (promise == null) return null;
      final raw = (await promise.toDart)?.toDart;
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return PushSubscription.fromJson(decoded.cast<String, Object?>());
    } catch (e) {
      debugPrint('PushGateway.subscribe failed: $e');
      return null;
    }
  }
}
