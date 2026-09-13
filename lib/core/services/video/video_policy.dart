/// Cost controls for in-app video, enforced BY DESIGN on the client and
/// mirrored in `storage.rules` (size, content type, one-shot slots per day). The owner approved Firebase
/// Storage with a hard $100 ceiling (GCP budget `taskcaster-video-ceiling-100`,
/// alerts at 50/90/100 %). Every number here is a lever for that ceiling.
/// Retention is indefinite by the owner's decision ("maybe just not deleting
/// now"): there is NO lifecycle deletion; the caps and the budget alarm are the
/// controls.
///
/// Storage layout: `submissions/{uid}/{yyyyMMdd}/{slot}` where `slot` is a
/// single digit 0..9. The Storage rules refuse overwrites and any slot outside
/// that range, so a user can never store more than [maxUploadsPerDay] clips a
/// day no matter what the client does.
class VideoPolicy {
  const VideoPolicy._();

  /// Absolute clip-length cap, seconds. A task's own timer can only shorten it.
  static const int maxClipSeconds = 30;

  /// Hard cap on one upload, bytes. Mirrored in storage.rules
  /// (`request.resource.size < 32 * 1024 * 1024`).
  static const int maxUploadBytes = 32 * 1024 * 1024;

  /// Clips a user may upload per UTC day. Mirrored by the 0..9 slot regex in
  /// storage.rules.
  static const int maxUploadsPerDay = 10;

  /// Target long-edge resolution for capture where the platform lets us ask
  /// (the OS recorder may ignore it; the byte cap is the real control).
  static const int targetLongEdgePx = 854; // 480p

  /// Days before an upload is deleted; null = never (owner's decision, see
  /// the class doc). Kept as a named lever so a lifecycle rule can be added
  /// later without hunting for the number.
  static const int? retentionDays = null;

  /// Root folder in the bucket for player clips.
  static const String storageRoot = 'submissions';

  /// The clip cap for a task: the task timer or [maxClipSeconds], whichever is
  /// shorter. A null / non-positive timer means "no timer" -> the absolute cap.
  static int clipCapSeconds(int? taskTimerSeconds) {
    if (taskTimerSeconds == null || taskTimerSeconds <= 0) {
      return maxClipSeconds;
    }
    return taskTimerSeconds < maxClipSeconds ? taskTimerSeconds : maxClipSeconds;
  }

  /// The playback end for a clip: [durationSeconds] auto-trimmed to the cap.
  /// Null when the duration is unknown (play to the end, the player will stop
  /// at [cap] itself).
  static double? trimmedEndSeconds(double? durationSeconds, int cap) {
    if (durationSeconds == null || durationSeconds.isNaN) return null;
    if (durationSeconds < 0) return 0;
    return durationSeconds < cap ? durationSeconds : cap.toDouble();
  }

  /// True when [bytes] fits under the upload cap.
  static bool fitsUploadCap(int bytes) => bytes > 0 && bytes <= maxUploadBytes;

  /// `yyyyMMdd` in UTC, the day segment of the storage path.
  static String dayKey(DateTime when) {
    final u = when.toUtc();
    String two(int n) => n < 10 ? '0$n' : '$n';
    return '${u.year}${two(u.month)}${two(u.day)}';
  }

  /// True when [slot] is a usable daily slot (0 .. maxUploadsPerDay - 1).
  static bool isValidSlot(int slot) => slot >= 0 && slot < maxUploadsPerDay;

  /// The bucket object path for a clip. Throws [ArgumentError] on a bad slot
  /// so a client bug can never silently produce a path the rules reject.
  static String storagePath({
    required String userId,
    required DateTime when,
    required int slot,
  }) {
    if (!isValidSlot(slot)) {
      throw ArgumentError.value(slot, 'slot', 'must be 0..${maxUploadsPerDay - 1}');
    }
    if (userId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'must not be empty');
    }
    return '$storageRoot/$userId/${dayKey(when)}/$slot';
  }

  /// Second-bucket a viewer tap lands in, for the `tapSeconds` histogram that
  /// drives future automatic editing. Clamped to 0..cap.
  static int tapBucket(double positionSeconds, int cap) {
    if (positionSeconds.isNaN || positionSeconds <= 0) return 0;
    final b = positionSeconds.floor();
    return b > cap ? cap : b;
  }

  /// A one-line, player-facing reason a clip was refused, or null if it is
  /// acceptable. Only size is checked here; duration is enforced by the
  /// recorder (`maxDuration`) and by playback trimming.
  static String? rejectReason({required int bytes}) {
    if (bytes <= 0) return "That clip came back empty — try again.";
    if (!fitsUploadCap(bytes)) {
      final mb = (maxUploadBytes / (1024 * 1024)).round();
      return 'That clip is too big to post (over $mb MB) — record a shorter '
          'one or lower your camera resolution.';
    }
    return null;
  }
}
