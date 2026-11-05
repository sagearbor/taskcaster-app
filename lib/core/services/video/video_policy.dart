import '../plans/plans.dart';

/// Cost controls for in-app video, mirrored on the client from `storage.rules`
/// (size, content type, one-shot slots) and the server's plan table
/// (functions/src/plans.js). The owner approved Firebase Storage with a hard
/// $100 ceiling (GCP budget `taskcaster-video-ceiling-100`, alerts at
/// 50/90/100 %). Since WP-11 the limits depend on the plan ([PlanLimits]):
/// guest 5 clips ever, free 3 a day of 20 s, Pro 15 a day of 60 s. Clips are
/// not kept forever: the server's retention sweep deletes them (free after
/// 90 days, see docs/MONETIZATION.md).
///
/// Storage layout: `submissions/{uid}/{yyyyMMdd}/{slot}` for signed-in
/// players (slot 0-2 free, 0-9 and a-e Pro) and `submissions/{uid}/guest/{0-4}`
/// for guests. The Storage rules refuse overwrites and any slot the plan does
/// not have, so a user can never store more than their plan allows no matter
/// what the client does.
class VideoPolicy {
  const VideoPolicy._();

  /// Absolute clip-length ceiling, seconds: the Pro cap. Playback trims here;
  /// recording uses the player's plan cap ([clipCapSeconds]).
  static const int maxClipSeconds = 60;

  /// The recording cap when the plan is unknown: the free cap.
  static const int defaultClipSeconds = 20;

  /// Upload cap for guest/free, bytes (storage.rules freeMaxBytes). Pro's is
  /// [PlanLimits.pro.maxUploadBytes].
  static const int maxUploadBytes = 32 * 1024 * 1024;

  /// Clips a free player may upload per UTC day (storage.rules slots 0-2).
  static const int maxUploadsPerDay = 3;

  /// Target long-edge resolution for capture where the platform lets us ask
  /// (the OS recorder may ignore it; the byte cap is the real control).
  static const int targetLongEdgePx = 854; // 480p

  /// Days before a free player's clip is deleted by the server's retention
  /// sweep (functions/src/retention.js). Keepers (in a montage or graded 4+)
  /// last a year; Pro clips last while subscribed.
  static const int retentionDays = 90;

  /// Root folder in the bucket for player clips.
  static const String storageRoot = 'submissions';

  /// The clip cap for a task: the task timer or the plan's cap
  /// ([planCapSeconds], free by default), whichever is shorter. A null /
  /// non-positive timer means "no timer" -> the plan cap. Never above
  /// [maxClipSeconds].
  static int clipCapSeconds(int? taskTimerSeconds,
      {int planCapSeconds = defaultClipSeconds}) {
    final plan = planCapSeconds > maxClipSeconds ? maxClipSeconds : planCapSeconds;
    if (taskTimerSeconds == null || taskTimerSeconds <= 0) return plan;
    return taskTimerSeconds < plan ? taskTimerSeconds : plan;
  }

  /// The playback end for a clip: [durationSeconds] auto-trimmed to the cap.
  /// Null when the duration is unknown (play to the end, the player will stop
  /// at [cap] itself).
  static double? trimmedEndSeconds(double? durationSeconds, int cap) {
    if (durationSeconds == null || durationSeconds.isNaN) return null;
    if (durationSeconds < 0) return 0;
    return durationSeconds < cap ? durationSeconds : cap.toDouble();
  }

  /// True when [bytes] fits under the upload cap ([maxBytes], free by default).
  static bool fitsUploadCap(int bytes, {int maxBytes = maxUploadBytes}) =>
      bytes > 0 && bytes <= maxBytes;

  /// `yyyyMMdd` in UTC, the day segment of the storage path.
  static String dayKey(DateTime when) {
    final u = when.toUtc();
    String two(int n) => n < 10 ? '0$n' : '$n';
    return '${u.year}${two(u.month)}${two(u.day)}';
  }

  /// True when [slot] is a usable free daily slot (0 .. maxUploadsPerDay - 1).
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

  /// The bucket object path for [slot] under [limits]: the lifetime guest
  /// folder for a guest, today's (UTC) folder otherwise. Throws
  /// [ArgumentError] for a slot the plan does not have, so a client bug can
  /// never silently produce a path the rules reject.
  static String storagePathFor({
    required String userId,
    required DateTime when,
    required String slot,
    required PlanLimits limits,
  }) {
    if (!limits.slots.contains(slot)) {
      throw ArgumentError.value(slot, 'slot', 'not a ${limits.tier.name} slot');
    }
    if (userId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'must not be empty');
    }
    final folder = limits.lifetime ? guestFolder : dayKey(when);
    return '$storageRoot/$userId/$folder/$slot';
  }

  /// The day-segment stand-in for a guest's lifetime clips.
  static const String guestFolder = 'guest';

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
  static String? rejectReason({required int bytes, int maxBytes = maxUploadBytes}) {
    if (bytes <= 0) return "That clip came back empty — try again.";
    if (!fitsUploadCap(bytes, maxBytes: maxBytes)) {
      final mb = (maxBytes / (1024 * 1024)).round();
      return 'That clip is too big to post (over $mb MB) — record a shorter '
          'one or lower your camera resolution.';
    }
    return null;
  }
}
