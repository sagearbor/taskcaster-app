import 'dart:convert';

/// The kind of offline game a nearby host is casting.
enum NearbyGameType {
  telephone,
  unknown;

  /// Compact wire code embedded in the advertised endpoint name.
  String get code => switch (this) {
        NearbyGameType.telephone => 'tel',
        NearbyGameType.unknown => '?',
      };

  static NearbyGameType fromCode(String code) => switch (code) {
        'tel' => NearbyGameType.telephone,
        _ => NearbyGameType.unknown,
      };

  /// Human-readable name for banners.
  String get label => switch (this) {
        NearbyGameType.telephone => 'Drawing Telephone',
        NearbyGameType.unknown => 'a nearby game',
      };
}

/// Structured info a host encodes into its Google Nearby Connections
/// *advertised endpoint name*, so a passive discoverer can show a meaningful
/// banner ("🎮 Sage started Drawing Telephone — tap to join") **before** it ever
/// opens a connection.
///
/// ## Why an encoding at all
/// Nearby gives the discoverer exactly one string per advertiser — the endpoint
/// name. To carry host name + game type + a session id in that one field we use
/// a tiny tagged format:
///
/// ```
/// TCg1<US>tel<US>1a2b3c4d<US>Sage
/// ```
///
/// (`TCg1` = TaskCaster game v1, `<US>` = the ASCII unit-separator `0x1F`).
///
/// ## Length safety
/// Nearby carries the endpoint name over BLE/Wi-Fi advertisements, which are
/// short. We therefore cap the whole encoded string at [maxBytes] UTF-8 bytes
/// and truncate the *host name* (on rune boundaries, never mid-codepoint) to
/// fit. The fixed prefix/type/session fields are always preserved.
///
/// ## Backward / forward compatibility
/// [decode] gracefully accepts any string that is *not* in this format
/// (e.g. the older `"Sage's game"` label, or a future version) by treating the
/// whole thing as the host name with an unknown game type — so an old host and
/// a new discoverer still interoperate, just with a less precise label.
class NearbyCastLabel {
  const NearbyCastLabel({
    required this.hostName,
    required this.gameType,
    required this.sessionId,
    required this.isTaskCaster,
  });

  /// Display name of the hosting player.
  final String hostName;

  /// Which game is being cast.
  final NearbyGameType gameType;

  /// Short session fingerprint (≤8 chars) — lets the discoverer tell two
  /// concurrent hosts apart and de-dupe. Empty when unknown.
  final String sessionId;

  /// Whether this name actually parsed as a TaskCaster-cast game (vs. a plain
  /// fallback name we could not structurally decode).
  final bool isTaskCaster;

  static const String _prefix = 'TCg1';
  static const String _us = '\u001f'; // ASCII unit separator (0x1F)

  /// Hard cap on the encoded endpoint name, in UTF-8 bytes. Conservative so it
  /// survives Nearby's short advertisement payloads on every Android version.
  static const int maxBytes = 60;

  /// Build the advertised endpoint name for [hostName] hosting [gameType].
  /// [sessionId] is fingerprinted to its first 8 chars. The host name is
  /// truncated as needed so the result never exceeds [maxBytes] bytes.
  static String encode({
    required String hostName,
    required NearbyGameType gameType,
    String? sessionId,
  }) {
    // Strip the separator out of free-text so it can't corrupt the framing.
    final cleanHost = hostName.replaceAll(_us, ' ').trim();
    final host = cleanHost.isEmpty ? 'A player' : cleanHost;
    final sid = (sessionId ?? '').replaceAll(_us, '');
    final shortSid = sid.length > 8 ? sid.substring(0, 8) : sid;

    final fixed = '$_prefix$_us${gameType.code}$_us$shortSid$_us';
    final budget = maxBytes - utf8.encode(fixed).length;
    final safeHost = _truncateToBytes(host, budget < 1 ? 0 : budget);
    return '$fixed$safeHost';
  }

  /// Parse an advertised endpoint name. Never throws — unknown formats fall
  /// back to a plain host name.
  factory NearbyCastLabel.decode(String endpointName) {
    if (endpointName.startsWith('$_prefix$_us')) {
      final parts = endpointName.split(_us);
      final type = parts.length > 1
          ? NearbyGameType.fromCode(parts[1])
          : NearbyGameType.unknown;
      final sid = parts.length > 2 ? parts[2] : '';
      // Host name is the remainder; rejoin defensively though encode() strips US.
      final host = parts.length > 3 ? parts.sublist(3).join(_us) : '';
      return NearbyCastLabel(
        hostName: host.isEmpty ? 'A player' : host,
        gameType: type,
        sessionId: sid,
        isTaskCaster: true,
      );
    }
    // Legacy / foreign name: best-effort, show it verbatim.
    final name = endpointName.trim();
    return NearbyCastLabel(
      hostName: name.isEmpty ? 'A player' : name,
      gameType: NearbyGameType.unknown,
      sessionId: '',
      isTaskCaster: false,
    );
  }

  /// One-line banner text, e.g. "Sage started Drawing Telephone nearby".
  String get bannerText => gameType == NearbyGameType.unknown
      ? '$hostName started a game nearby'
      : '$hostName started ${gameType.label} nearby';

  /// Truncate [s] to at most [maxBytes] UTF-8 bytes without splitting a rune.
  static String _truncateToBytes(String s, int maxBytes) {
    if (maxBytes <= 0) return '';
    if (utf8.encode(s).length <= maxBytes) return s;
    final buf = StringBuffer();
    var used = 0;
    for (final rune in s.runes) {
      final ch = String.fromCharCode(rune);
      final b = utf8.encode(ch).length;
      if (used + b > maxBytes) break;
      buf.write(ch);
      used += b;
    }
    return buf.toString();
  }
}
