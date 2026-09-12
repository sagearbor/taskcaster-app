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
  final String? videoUrl;

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
    this.graderIds = const [],
  });

  factory FeedPost.fromMap(Map<String, dynamic> map) {
    return FeedPost(
      id: map['id'] as String? ?? '',
      gameId: map['gameId'] as String? ?? '',
      taskId: map['taskId'] as String? ?? '',
      taskTitle: map['taskTitle'] as String? ?? '',
      rubric: map['rubric'] as String?,
      userId: map['userId'] as String? ?? '',
      displayName: map['displayName'] as String? ?? '',
      mediaType: SubmissionMediaType.values.firstWhere(
        (e) => e.name == map['mediaType'],
        orElse: () => SubmissionMediaType.link,
      ),
      photoData: map['photoData'] as String?,
      text: map['text'] as String?,
      videoUrl: map['videoUrl'] as String?,
      caption: map['caption'] as String?,
      stamp: map['stamp'] as String?,
      isLate: map['isLate'] as bool? ?? false,
      isHouse: map['isHouse'] as bool? ?? false,
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'] as String)
          : DateTime.fromMillisecondsSinceEpoch(0),
      elapsedSeconds: map['elapsedSeconds'] as int?,
      gradeCount: map['gradeCount'] as int? ?? 0,
      gradeSum: map['gradeSum'] as int? ?? 0,
      boosted: map['boosted'] as bool? ?? false,
      tapCount: map['tapCount'] as int? ?? 0,
      graderIds: (map['graderIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
    );
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
      graderIds: graderIds ?? this.graderIds,
    );
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
      ];
}
