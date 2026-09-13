import 'package:equatable/equatable.dart';

/// How far along the server-side montage render is.
///
/// `unknown` is the parse fallback so a status this build has never heard of
/// (a newer server) is treated as "not ready" rather than crashing the feed.
enum MontageStatus { pending, ready, failed, unknown }

/// The automatic edit of a whole task: every entry's last two seconds spliced
/// into one "finale" clip, plus an optional "moments" cut built from where
/// viewers tapped.
///
/// Rendered entirely server-side (another agent owns that); the app only ever
/// READS `montages/{gameId}_{taskId}`. Nothing in the client writes here, and
/// nothing blocks on it: a task with no montage, or one still rendering,
/// simply shows no finale card.
class Montage extends Equatable {
  final String gameId;
  final String taskId;

  /// The spliced finale. Null until [status] is [MontageStatus.ready].
  final String? finaleUrl;

  /// The tap-driven "best moments" cut, when the server made one.
  final String? momentsUrl;

  /// The `feed_posts` ids that went into the render, in order.
  final List<String> sourcePostIds;

  final DateTime? updatedAt;
  final MontageStatus status;

  const Montage({
    required this.gameId,
    required this.taskId,
    this.finaleUrl,
    this.momentsUrl,
    this.sourcePostIds = const [],
    this.updatedAt,
    this.status = MontageStatus.pending,
  });

  /// The document id the server writes under.
  static String idFor(String gameId, String taskId) => '${gameId}_$taskId';

  /// True when there is something worth showing a viewer.
  bool get isReady =>
      status == MontageStatus.ready &&
      finaleUrl != null &&
      finaleUrl!.isNotEmpty;

  factory Montage.fromMap(Map<String, dynamic> map) {
    return Montage(
      gameId: map['gameId'] as String? ?? '',
      taskId: map['taskId'] as String? ?? '',
      finaleUrl: map['finaleUrl'] as String?,
      momentsUrl: map['momentsUrl'] as String?,
      sourcePostIds: (map['sourcePostIds'] as List<dynamic>?)
              ?.map((e) => '$e')
              .toList() ??
          const [],
      updatedAt: _parseDate(map['updatedAt']),
      status: MontageStatus.values.firstWhere(
        (s) => s.name == map['status'],
        orElse: () => MontageStatus.unknown,
      ),
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value is String) return DateTime.tryParse(value);
    // The server may write a Firestore Timestamp; `toDate()` is duck-typed
    // here so this model stays free of a cloud_firestore import.
    if (value != null) {
      try {
        final dynamic dynamicValue = value;
        final result = dynamicValue.toDate();
        if (result is DateTime) return result;
      } catch (_) {
        // Not a Timestamp — leave it null rather than guessing.
      }
    }
    return null;
  }

  Map<String, dynamic> toMap() {
    return {
      'gameId': gameId,
      'taskId': taskId,
      'finaleUrl': finaleUrl,
      'momentsUrl': momentsUrl,
      'sourcePostIds': sourcePostIds,
      'updatedAt': updatedAt?.toIso8601String(),
      'status': status.name,
    };
  }

  @override
  List<Object?> get props => [
        gameId,
        taskId,
        finaleUrl,
        momentsUrl,
        sourcePostIds,
        updatedAt,
        status,
      ];
}
