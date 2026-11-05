import 'package:equatable/equatable.dart';

/// Who scores a friend game's entries (WP-13).
enum JudgingMode {
  /// One human judge (the creator) scores every entry: "Taskmaster mode".
  /// Every game written before WP-13 has no `judgingMode` key and parses as
  /// this, so live games keep their judge.
  judge,

  /// Everyone grades everyone: once you post your entry for a task you grade
  /// every other player's entry 1..5, and a Cloud Function locks each score
  /// (`round(mean x 2)`) when everyone has graded or after 24 h. No player is
  /// the judge. The default for new friend games.
  group,
}

class GameSettings extends Equatable {
  final Duration? taskDeadline; // How long players have to submit each task
  final bool autoAdvanceTasks; // Auto-unlock next task when current is judged
  final bool allowSkips; // Players can skip tasks
  final int? maxPlayers; // Maximum players allowed (null = unlimited)
  // Whether the judge also does the tasks. Asymmetric modes (House Hunt: the
  // hider only judges) set this false so the judge is never seeded a per-task
  // status — otherwise allPlayersJudged waits forever on a submission the
  // judge will never make. Absent in older game docs -> true (judge plays).
  final bool judgePlays;

  /// The crowd in the Arena scores this game's submissions (task points =
  /// `round(mean grade x 2)`), instead of a human judge. The Starter Pack sets
  /// this true; absent in older game docs -> false (human judge).
  final bool crowdJudged;

  /// Submissions from this game are posted to the Arena. Friend games show a
  /// "Share to the Arena" toggle backed by this; absent in older game docs ->
  /// true, which matches the product default ("default on").
  final bool shareToArena;

  /// Who scores entries. Absent in older game docs -> [JudgingMode.judge].
  final JudgingMode judgingMode;

  const GameSettings({
    this.taskDeadline,
    this.autoAdvanceTasks = true,
    this.allowSkips = false,
    this.maxPlayers,
    this.judgePlays = true,
    this.crowdJudged = false,
    this.shareToArena = true,
    this.judgingMode = JudgingMode.judge,
  });

  /// True when the players grade each other instead of a judge (WP-13).
  bool get isGroupJudged => judgingMode == JudgingMode.group;

  // Default settings for quick play
  factory GameSettings.quickPlay() {
    return const GameSettings(
      taskDeadline: Duration(hours: 24),
      autoAdvanceTasks: true,
      allowSkips: false,
      maxPlayers: 10,
    );
  }

  // Default settings for custom games
  factory GameSettings.custom() {
    return const GameSettings(
      taskDeadline: null, // No deadline
      autoAdvanceTasks: false, // Manual advancement
      allowSkips: true,
      maxPlayers: null, // Unlimited
    );
  }

  factory GameSettings.fromMap(Map<String, dynamic> map) {
    return GameSettings(
      taskDeadline: map['taskDeadlineSeconds'] != null
          ? Duration(seconds: map['taskDeadlineSeconds'] as int)
          : null,
      autoAdvanceTasks: map['autoAdvanceTasks'] as bool? ?? true,
      allowSkips: map['allowSkips'] as bool? ?? false,
      maxPlayers: map['maxPlayers'] as int?,
      judgePlays: map['judgePlays'] as bool? ?? true,
      // Backward-compatible: older docs have neither key.
      crowdJudged: map['crowdJudged'] as bool? ?? false,
      shareToArena: map['shareToArena'] as bool? ?? true,
      // Backward-compatible: no key (or an unknown value) is a judge game.
      judgingMode: JudgingMode.values.firstWhere(
        (m) => m.name == map['judgingMode'],
        orElse: () => JudgingMode.judge,
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'taskDeadlineSeconds': taskDeadline?.inSeconds,
      'autoAdvanceTasks': autoAdvanceTasks,
      'allowSkips': allowSkips,
      'maxPlayers': maxPlayers,
      'judgePlays': judgePlays,
      'crowdJudged': crowdJudged,
      'shareToArena': shareToArena,
      'judgingMode': judgingMode.name,
    };
  }

  GameSettings copyWith({
    Duration? taskDeadline,
    bool? autoAdvanceTasks,
    bool? allowSkips,
    int? maxPlayers,
    bool? judgePlays,
    bool? crowdJudged,
    bool? shareToArena,
    JudgingMode? judgingMode,
  }) {
    return GameSettings(
      taskDeadline: taskDeadline ?? this.taskDeadline,
      autoAdvanceTasks: autoAdvanceTasks ?? this.autoAdvanceTasks,
      allowSkips: allowSkips ?? this.allowSkips,
      maxPlayers: maxPlayers ?? this.maxPlayers,
      judgePlays: judgePlays ?? this.judgePlays,
      crowdJudged: crowdJudged ?? this.crowdJudged,
      shareToArena: shareToArena ?? this.shareToArena,
      judgingMode: judgingMode ?? this.judgingMode,
    );
  }

  @override
  List<Object?> get props => [
        taskDeadline,
        autoAdvanceTasks,
        allowSkips,
        maxPlayers,
        judgePlays,
        crowdJudged,
        shareToArena,
        judgingMode,
      ];
}
