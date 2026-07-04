import 'dart:async';

import 'package:android_play_install_referrer/android_play_install_referrer.dart';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'invite_link_parser.dart';

/// Where a pending invite code came from.
enum PendingInviteSource {
  /// A taskcaster://join (or https .../join/) deep link — app was installed.
  link,

  /// The Play Install Referrer — code carried through a fresh Play install.
  referrer,
}

/// Holds an invite code that arrived out-of-band (deep link or Play Install
/// Referrer) until the UI is ready to offer "join your friend's game".
///
/// Lifecycle: registered as a singleton in the service locator; [init] is
/// fired (not awaited) from main() so a cold-start link/referrer is captured
/// before the home screen mounts. The join popup listens to this notifier and
/// [consume]s the code when it shows the dialog.
///
/// All platform access is behind injectable seams so the pure flow is
/// unit-testable; defaults use the real plugins.
class PendingInviteService extends ChangeNotifier {
  PendingInviteService({
    Future<Uri?> Function()? getInitialLink,
    Stream<Uri>? uriLinkStream,
    Future<String?> Function()? getInstallReferrer,
    bool? isAndroid,
  })  : _getInitialLink = getInitialLink,
        _uriLinkStream = uriLinkStream,
        _getInstallReferrer = getInstallReferrer ?? _playInstallReferrer,
        _isAndroid = isAndroid ??
            (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  /// shared_preferences flag: the install referrer has been read (or the read
  /// was attempted) on this install — never read it again.
  static const String referrerCheckedPrefsKey =
      'pending_invite_referrer_checked';

  final Future<Uri?> Function()? _getInitialLink;
  final Stream<Uri>? _uriLinkStream;
  final Future<String?> Function() _getInstallReferrer;
  final bool _isAndroid;

  StreamSubscription<Uri>? _linkSubscription;
  bool _initialized = false;

  String? _pendingCode;
  PendingInviteSource? _source;

  /// The invite code waiting to be offered to the user, if any.
  String? get pendingCode => _pendingCode;

  /// How [pendingCode] arrived. Null when there is no pending code.
  PendingInviteSource? get source => _source;

  static Future<String?> _playInstallReferrer() async =>
      (await AndroidPlayInstallReferrer.installReferrer).installReferrer;

  /// Starts listening for deep links and (once per install, Android only)
  /// reads the Play Install Referrer. Safe to call on any platform — every
  /// platform call is wrapped so a missing plugin/emulator quirk can never
  /// crash startup.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Deep links: the link that launched the app (cold start) + links that
    // arrive while it is running.
    try {
      AppLinks? appLinks;
      final stream = _uriLinkStream ?? (appLinks = AppLinks()).uriLinkStream;
      _linkSubscription = stream.listen(_offerUri, onError: (Object _) {});
      final getInitial =
          _getInitialLink ?? (appLinks ?? AppLinks()).getInitialLink;
      final initial = await getInitial();
      if (initial != null) _offerUri(initial);
    } catch (e) {
      debugPrint('PendingInviteService: deep link setup failed: $e');
    }

    await _checkInstallReferrerOnce();
  }

  void _offerUri(Uri uri) {
    final code = InviteLinks.codeFromUri(uri);
    if (code == null) return;
    // A fresh explicit link always wins over anything already pending.
    _pendingCode = code;
    _source = PendingInviteSource.link;
    notifyListeners();
  }

  Future<void> _checkInstallReferrerOnce() async {
    if (!_isAndroid) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(referrerCheckedPrefsKey) ?? false) return;
      // Mark before reading so a plugin that throws every time (emulator,
      // sideload, missing Play services) is only attempted once.
      await prefs.setBool(referrerCheckedPrefsKey, true);

      final code = InviteLinks.codeFromReferrer(await _getInstallReferrer());
      // A direct deep link (more specific, more recent) is never overwritten.
      if (code == null || _pendingCode != null) return;
      _pendingCode = code;
      _source = PendingInviteSource.referrer;
      notifyListeners();
    } catch (e) {
      // Expected on emulators/sideloads — referrer is best-effort only.
      debugPrint('PendingInviteService: install referrer unavailable: $e');
    }
  }

  /// Returns the pending code (or null) and clears it, so the invite is only
  /// offered once.
  String? consume() {
    final code = _pendingCode;
    if (code == null) return null;
    _pendingCode = null;
    _source = null;
    notifyListeners();
    return code;
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }
}
