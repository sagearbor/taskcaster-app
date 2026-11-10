import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "This session is an automated walk, not a player."
///
/// Agents run headless browser walks against the production web app every
/// audit round. Without a guard, every walk posts color-bar test patterns to
/// the public Arena under the name "Guest", and the next real player who
/// reaches that task grades them (fun audit 2026-11-09, WP-1).
///
/// When [isOn], posts are created with `shareable: false`: the Arena queue
/// skips them (FeedRepositoryImpl.watchQueue), the rules hide them from
/// strangers reading by id, and the montage renderer leaves them out of the
/// finale (functions/src/contract.js isMontageablePost).
///
/// Turned on by either:
///   * launching the web app with `?e2e=1` (also `?e2e=true`, or inside the
///     hash route, `#/?e2e=1`). The flag is persisted in SharedPreferences
///     under [prefsKey], because the app strips launch query params from the
///     address bar (#53) and a reload must stay in e2e mode. `?e2e=0` turns
///     it off again and clears the persisted flag;
///   * building with `--dart-define=E2E=true`.
///
/// Default: off. See docs/PRODUCT_DIRECTION.md, "Testing against prod".
class E2eMode {
  E2eMode._();

  /// SharedPreferences key holding the persisted flag.
  static const String prefsKey = 'tc_e2e';

  /// The launch-URL query parameter.
  static const String queryParam = 'e2e';

  static const bool _fromDartDefine = bool.fromEnvironment('E2E');

  static bool _fromLaunch = false;
  static bool? _override;

  /// True when this session must keep its posts out of the public Arena.
  static bool get isOn => _override ?? (_fromDartDefine || _fromLaunch);

  /// What the launch URL says: true for `e2e=1|true`, false for
  /// `e2e=0|false`, null when it says nothing. Looks at the real query and at
  /// a query inside a hash route (`/#/?e2e=1`).
  static bool? flagIn(Uri uri) {
    String? raw = uri.queryParameters[queryParam];
    if (raw == null) {
      final fragment = uri.fragment;
      final q = fragment.indexOf('?');
      if (q >= 0) {
        try {
          raw = Uri.splitQueryString(fragment.substring(q + 1))[queryParam];
        } catch (_) {
          raw = null;
        }
      }
    }
    if (raw == null) return null;
    switch (raw.trim().toLowerCase()) {
      case '1':
      case 'true':
      case 'yes':
      case 'on':
      case '':
        return true;
      case '0':
      case 'false':
      case 'no':
      case 'off':
        return false;
    }
    return null;
  }

  /// Read the launch URL once at startup and the persisted flag. Best-effort:
  /// never throws, so it can be awaited before runApp.
  ///
  /// [launchUri] defaults to `Uri.base` on the web; off the web there is no
  /// launch URL, so only the persisted flag and the dart-define count.
  static Future<void> init({Uri? launchUri}) async {
    bool? fromUrl;
    try {
      final uri = launchUri ?? (kIsWeb ? Uri.base : null);
      if (uri != null) fromUrl = flagIn(uri);
    } catch (_) {
      fromUrl = null;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      if (fromUrl == true) {
        await prefs.setBool(prefsKey, true);
      } else if (fromUrl == false) {
        await prefs.remove(prefsKey);
      }
      _fromLaunch = fromUrl ?? (prefs.getBool(prefsKey) ?? false);
    } catch (_) {
      // Storage unavailable: the URL alone still decides this session.
      _fromLaunch = fromUrl ?? false;
    }
    if (_fromLaunch || _fromDartDefine) {
      debugPrint('E2eMode: on — posts are created with shareable:false');
    }
  }

  /// Tests: force [isOn] (null = back to the real flags).
  @visibleForTesting
  static void debugOverride(bool? value) => _override = value;

  /// Tests: forget everything [init] read.
  @visibleForTesting
  static void debugReset() {
    _override = null;
    _fromLaunch = false;
  }
}
