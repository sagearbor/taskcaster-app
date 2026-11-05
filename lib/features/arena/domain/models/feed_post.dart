import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:equatable/equatable.dart';

import '../../../../core/models/submission.dart';

/// The six auto-stamps. The player never picks one — `AutoEdit.stamp` chooses
/// from how the attempt went, and the feed applies `DON'T ASK` once a post has
/// collected 3+ viewer taps.
class Stamps {
  const Stamps._();

  static const String nailedIt = 'NAILED IT';
  static const String technically = 'TECHNICALLY';
  static const String noRegrets = 'NO REGRETS';
  static const String dontAsk = "DON'T ASK";
  static const String art = 'ART';
  static const String sendHelp = 'SEND HELP';

  static const List<String> values = [
    nailedIt,
    technically,
    noRegrets,
    dontAsk,
    art,
    sendHelp,
  ];

  /// Number of viewer taps at which a post earns the `DON'T ASK` stamp.
  static const int dontAskTaps = 3;
}

/// One entry in the Arena: a player's attempt at a task, posted automatically
/// the moment they submit.
///
/// Photos live inline as base64 JPEG in [photoData] (<= 400 KB) so the app
/// needs no Firebase Storage. `grades/{graderUid}` is a subcollection of the
/// post document; [gradeCount]/[gradeSum] are the denormalized counters the
/// grade transaction keeps in step.
class FeedPost extends Equatable {
  final String id;
  final String gameId;
  final String taskId;
  final String taskTitle;

  /// The one line the grader scores against, copied from the task.
  final String? rubric;

  final String userId;
  final String displayName;

  final SubmissionMediaType mediaType;

  /// base64-encoded JPEG bytes, with NO `data:` prefix. Capped at 400 KB.
  final String? photoData;

  final String? text;

  /// The https download URL of the clip for a [SubmissionMediaType.video]
  /// post, and the pasted share link for a [SubmissionMediaType.link] post.
  /// The media type — never the field — is what tells the two apart.
  final String? videoUrl;

  /// Video posts only: the bucket object path the clip lives at —
  /// `submissions/{uid}/{yyyyMMdd}/{slot}` for a player's clip, or
  /// `house/{taskId}.mp4` for a seeded house entry. The Firestore rules check
  /// that a player's path starts with their own `submissions/<uid>/` prefix.
  final String? videoStoragePath;

  /// Video posts only: the server's 720p H.264 SDR re-encode of the clip
  /// (audit WP-08), set by the `onClipUploaded` Cloud Function once the
  /// transcode finishes. Plays on every browser and phone, unlike an iPhone
  /// HEVC/HDR original. Null while transcoding, and on posts from before
  /// WP-08 — playback then falls back to [videoUrl]. Server-owned: the
  /// Firestore rules refuse it on a client create or update, and [toMap]
  /// never writes a null one.
  final String? playbackUrl;

  /// Video posts only: a JPEG poster frame of the transcoded clip, shown
  /// while the video loads. Server-owned, like [playbackUrl].
  final String? posterUrl;

  /// Video posts only: uploaded size in bytes.
  final int? videoBytes;

  /// Video posts only: the MIME type uploaded.
  final String? videoContentType;

  /// Video posts only: clip duration in seconds, or null when unknown —
  /// playback trims at `VideoPolicy.maxClipSeconds` regardless.
  final double? videoDurationSeconds;

  /// Video posts only: seconds already burned on the TASK clock (since the
  /// player tapped Start) at the moment the recorder opened. With
  /// [timerSeconds] this is everything `CountdownBurn` needs to draw the task
  /// clock over playback, and everything a later server-side splice needs to
  /// rebuild it without OCR.
  final int? clockOffsetSeconds;

  /// The task's `durationSeconds`, copied onto the post so the countdown can
  /// be drawn from the post alone (the Arena never loads the game).
  final int? timerSeconds;

  /// Auto-generated; see `AutoEdit.caption`.
  final String? caption;

  /// Auto-chosen from [Stamps.values]; see `AutoEdit.stamp`.
  final String? stamp;

  final bool isLate;

  /// A seeded "Greg's assistant" entry, so a brand-new player always has
  /// something to grade and the Arena is never empty.
  final bool isHouse;

  final DateTime createdAt;
  final int? elapsedSeconds;

  final int gradeCount;
  final int gradeSum;

  /// Sorted to the front of everyone's queue — earned by grading three posts.
  final bool boosted;

  /// Viewer "that's funny" taps. Never required, never blocks anything; breaks
  /// fewest-grades ties and drives the `DON'T ASK` stamp.
  final int tapCount;

  /// Per-second histogram of viewer taps: `'<second>' -> taps`, where the key
  /// is `VideoPolicy.tapBucket(position, cap)`. Empty for photo/text posts and
  /// for video posts nobody has tapped yet. This is the raw signal future
  /// automatic editing (auto-trim to the funniest second) will run on — it is
  /// collected now so there is history to work with when that lands.
  final Map<String, int> tapSeconds;

  /// Uids that have already graded this post. Persisted (see [toMap]) so the
  /// queue can exclude posts the viewer graded with a single array-contains
  /// query instead of a collection-group read of every `grades` subcollection.
  /// Deliberately NOT part of [props]: it is a persistence detail, and two
  /// posts with the same counters are the same post as far as the UI cares.
  final List<String> graderIds;

  const FeedPost({
    required this.id,
    required this.gameId,
    required this.taskId,
    required this.taskTitle,
    this.rubric,
    required this.userId,
    required this.displayName,
    required this.mediaType,
    this.photoData,
    this.text,
    this.videoUrl,
    this.caption,
    this.stamp,
    this.isLate = false,
    this.isHouse = false,
    required this.createdAt,
    this.elapsedSeconds,
    this.gradeCount = 0,
    this.gradeSum = 0,
    this.boosted = false,
    this.tapCount = 0,
    this.tapSeconds = const {},
    this.videoStoragePath,
    this.playbackUrl,
    this.posterUrl,
    this.videoBytes,
    this.videoContentType,
    this.videoDurationSeconds,
    this.clockOffsetSeconds,
    this.timerSeconds,
    this.graderIds = const [],
  });

  /// Parses a stored post. Defensive by design: one bad document must never
  /// take down the Arena stream for every viewer, so every field is read by
  /// type and a field of the wrong type falls back to its default rather than
  /// throwing. `createdAt` accepts a Firestore `Timestamp` (what new posts
  /// carry — the server stamps it), a legacy ISO-8601 string, a `DateTime` or
  /// epoch milliseconds.
  factory FeedPost.fromMap(Map<String, dynamic> map) {
    return FeedPost(
      id: _string(map['id']) ?? '',
      gameId: _string(map['gameId']) ?? '',
      taskId: _string(map['taskId']) ?? '',
      taskTitle: _string(map['taskTitle']) ?? '',
      rubric: _string(map['rubric']),
      userId: _string(map['userId']) ?? '',
      displayName: _string(map['displayName']) ?? '',
      mediaType: SubmissionMediaType.values.firstWhere(
        (e) => e.name == map['mediaType'],
        orElse: () => SubmissionMediaType.link,
      ),
      photoData: _string(map['photoData']),
      text: _string(map['text']),
      videoUrl: _string(map['videoUrl']),
      caption: _string(map['caption']),
      stamp: _string(map['stamp']),
      isLate: _bool(map['isLate']),
      isHouse: _bool(map['isHouse']),
      createdAt: parseCreatedAt(map['createdAt']),
      elapsedSeconds: _int(map['elapsedSeconds']),
      gradeCount: _int(map['gradeCount']) ?? 0,
      gradeSum: _int(map['gradeSum']) ?? 0,
      boosted: _bool(map['boosted']),
      tapCount: _int(map['tapCount']) ?? 0,
      // Written by `FieldValue.increment` on dotted `tapSeconds.<n>` keys, so
      // Firestore hands it back as a nested map. Absent on every document
      // written before in-app video existed.
      tapSeconds: _tapSeconds(map['tapSeconds']),
      videoStoragePath: _string(map['videoStoragePath']),
      playbackUrl: _string(map['playbackUrl']),
      posterUrl: _string(map['posterUrl']),
      videoBytes: _int(map['videoBytes']),
      videoContentType: _string(map['videoContentType']),
      videoDurationSeconds: map['videoDurationSeconds'] is num
          ? (map['videoDurationSeconds'] as num).toDouble()
          : null,
      clockOffsetSeconds: _int(map['clockOffsetSeconds']),
      timerSeconds: _int(map['timerSeconds']),
      graderIds: map['graderIds'] is List
          ? (map['graderIds'] as List).whereType<String>().toList()
          : const [],
    );
  }

  /// The epoch, for a post whose `createdAt` is missing or unreadable — it
  /// sorts last by recency instead of breaking the list. A post written with
  /// `FieldValue.serverTimestamp()` also reads as null for the instant before
  /// the server confirms it.
  static final DateTime unknownCreatedAt =
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  /// `createdAt` in any shape the collection has ever held it.
  static DateTime parseCreatedAt(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value) ?? unknownCreatedAt;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return unknownCreatedAt;
  }

  static String? _string(Object? v) => v is String ? v : null;

  static bool _bool(Object? v) => v is bool ? v : false;

  static int? _int(Object? v) => v is num ? v.toInt() : null;

  static Map<String, int> _tapSeconds(Object? v) {
    if (v is! Map) return const {};
    return {
      for (final e in v.entries)
        if (e.value is num) '${e.key}': (e.value as num).toInt(),
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'gameId': gameId,
      'taskId': taskId,
      'taskTitle': taskTitle,
      'rubric': rubric,
      'userId': userId,
      'displayName': displayName,
      'mediaType': mediaType.name,
      'photoData': photoData,
      'text': text,
      'videoUrl': videoUrl,
      'caption': caption,
      'stamp': stamp,
      'isLate': isLate,
      'isHouse': isHouse,
      'createdAt': createdAt.toIso8601String(),
      'elapsedSeconds': elapsedSeconds,
      'gradeCount': gradeCount,
      'gradeSum': gradeSum,
      'boosted': boosted,
      'tapCount': tapCount,
      'tapSeconds': tapSeconds,
      'videoStoragePath': videoStoragePath,
      // Server-owned (WP-08): only ever round-tripped, never created by the
      // app — the create rule denies the keys outright, even as null.
      if (playbackUrl != null) 'playbackUrl': playbackUrl,
      if (posterUrl != null) 'posterUrl': posterUrl,
      'videoBytes': videoBytes,
      'videoContentType': videoContentType,
      'videoDurationSeconds': videoDurationSeconds,
      'clockOffsetSeconds': clockOffsetSeconds,
      'timerSeconds': timerSeconds,
      'graderIds': graderIds,
    };
  }

  FeedPost copyWith({
    String? id,
    String? gameId,
    String? taskId,
    String? taskTitle,
    String? rubric,
    String? userId,
    String? displayName,
    SubmissionMediaType? mediaType,
    String? photoData,
    String? text,
    String? videoUrl,
    String? caption,
    String? stamp,
    bool? isLate,
    bool? isHouse,
    DateTime? createdAt,
    int? elapsedSeconds,
    int? gradeCount,
    int? gradeSum,
    bool? boosted,
    int? tapCount,
    Map<String, int>? tapSeconds,
    String? videoStoragePath,
    String? playbackUrl,
    String? posterUrl,
    int? videoBytes,
    String? videoContentType,
    double? videoDurationSeconds,
    int? clockOffsetSeconds,
    int? timerSeconds,
    List<String>? graderIds,
  }) {
    return FeedPost(
      id: id ?? this.id,
      gameId: gameId ?? this.gameId,
      taskId: taskId ?? this.taskId,
      taskTitle: taskTitle ?? this.taskTitle,
      rubric: rubric ?? this.rubric,
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      mediaType: mediaType ?? this.mediaType,
      photoData: photoData ?? this.photoData,
      text: text ?? this.text,
      videoUrl: videoUrl ?? this.videoUrl,
      caption: caption ?? this.caption,
      stamp: stamp ?? this.stamp,
      isLate: isLate ?? this.isLate,
      isHouse: isHouse ?? this.isHouse,
      createdAt: createdAt ?? this.createdAt,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      gradeCount: gradeCount ?? this.gradeCount,
      gradeSum: gradeSum ?? this.gradeSum,
      boosted: boosted ?? this.boosted,
      tapCount: tapCount ?? this.tapCount,
      tapSeconds: tapSeconds ?? this.tapSeconds,
      videoStoragePath: videoStoragePath ?? this.videoStoragePath,
      playbackUrl: playbackUrl ?? this.playbackUrl,
      posterUrl: posterUrl ?? this.posterUrl,
      videoBytes: videoBytes ?? this.videoBytes,
      videoContentType: videoContentType ?? this.videoContentType,
      videoDurationSeconds: videoDurationSeconds ?? this.videoDurationSeconds,
      clockOffsetSeconds: clockOffsetSeconds ?? this.clockOffsetSeconds,
      timerSeconds: timerSeconds ?? this.timerSeconds,
      graderIds: graderIds ?? this.graderIds,
    );
  }

  /// What a video post actually plays: the server's H.264 transcode once it
  /// exists, the uploaded original until then (and on posts from before
  /// WP-08).
  String? get playableVideoUrl {
    final transcoded = playbackUrl;
    if (transcoded != null && transcoded.isNotEmpty) return transcoded;
    return videoUrl;
  }

  /// Mean crowd grade (1..5), or null while nobody has graded it.
  double? get meanGrade => gradeCount == 0 ? null : gradeSum / gradeCount;

  /// The task points this post is worth: `round(mean x 2)` clamped to 0..10.
  /// Null while nobody has graded it.
  int? get crowdPoints {
    final mean = meanGrade;
    if (mean == null) return null;
    return (mean * 2).round().clamp(0, 10);
  }

  /// The stamp actually shown: 3+ viewer taps overrides whatever the timing
  /// earned with `DON'T ASK`.
  String? get displayStamp =>
      tapCount >= Stamps.dontAskTaps ? Stamps.dontAsk : stamp;

  @override
  List<Object?> get props => [
        id,
        gameId,
        taskId,
        taskTitle,
        rubric,
        userId,
        displayName,
        mediaType,
        photoData,
        text,
        videoUrl,
        caption,
        stamp,
        isLate,
        isHouse,
        createdAt,
        elapsedSeconds,
        gradeCount,
        gradeSum,
        boosted,
        tapCount,
        tapSeconds,
        videoStoragePath,
        playbackUrl,
        posterUrl,
        videoBytes,
        videoContentType,
        videoDurationSeconds,
        clockOffsetSeconds,
        timerSeconds,
      ];
}
