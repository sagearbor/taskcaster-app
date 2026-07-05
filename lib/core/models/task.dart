import 'package:equatable/equatable.dart';
import 'submission.dart';
import 'task_modifier.dart';
import 'player_task_status.dart';

enum TaskType { video, puzzle, ar }

enum TaskStatus {
  waiting_for_submissions,
  ready_to_judge,
  judging,
  completed,
}

class Task extends Equatable {
  final String id;
  final String title;
  final String description;
  final TaskType taskType;
  final String? puzzleAnswer;
  final List<Submission> submissions;
  final List<TaskModifier> modifiers;

  // AR task fields. Nullable so existing serialized tasks (which lack these
  // keys) deserialize cleanly to null. [arGameId] identifies the AR mini-game
  // to launch (e.g. "balloon_pop"); [arResult] is the raw gameplay result
  // (e.g. balloons popped) recorded alongside the awarded score.
  final String? arGameId;
  final int? arResult;

  /// Library category (e.g. "Quick & Silly"). Nullable so tasks serialized
  /// before this field existed (and custom/community tasks) deserialize
  /// cleanly to null. Prebuilt tasks always carry one of
  /// `PrebuiltTasksData.categories`.
  final String? category;

  // NEW: Async game fields
  final TaskStatus status;
  final DateTime? deadline; // Deadline for submissions
  final int? durationSeconds; // Time limit to DO the task (e.g., 60s countdown)
  final Map<String, PlayerTaskStatus> playerStatuses; // Track each player's status

  const Task({
    required this.id,
    required this.title,
    required this.description,
    required this.taskType,
    this.puzzleAnswer,
    required this.submissions,
    this.modifiers = const [],
    this.arGameId,
    this.arResult,
    this.category,
    this.status = TaskStatus.waiting_for_submissions,
    this.deadline,
    this.durationSeconds,
    this.playerStatuses = const {},
  });

  factory Task.fromMap(Map<String, dynamic> map) {
    return Task(
      id: map['id'] as String,
      title: map['title'] as String,
      description: map['description'] as String,
      taskType: TaskType.values.firstWhere(
        (e) => e.name == map['taskType'],
        orElse: () => TaskType.video,
      ),
      puzzleAnswer: map['puzzleAnswer'] as String?,
      arGameId: map['arGameId'] as String?,
      arResult: map['arResult'] as int?,
      category: map['category'] as String?,
      submissions: (map['submissions'] as List<dynamic>?)
          ?.map((e) => Submission.fromMap(e as Map<String, dynamic>))
          .toList() ?? [],
      modifiers: (map['modifiers'] as List<dynamic>?)
          ?.map((e) => TaskModifier.fromMap(e as Map<String, dynamic>))
          .toList() ?? [],
      status: TaskStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => TaskStatus.waiting_for_submissions,
      ),
      deadline: map['deadline'] != null
          ? DateTime.parse(map['deadline'] as String)
          : null,
      durationSeconds: map['durationSeconds'] as int?,
      playerStatuses: (map['playerStatuses'] as Map<String, dynamic>?)?.map(
            (key, value) => MapEntry(
              key,
              PlayerTaskStatus.fromMap(value as Map<String, dynamic>),
            ),
          ) ??
          {},
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'taskType': taskType.name,
      'puzzleAnswer': puzzleAnswer,
      'arGameId': arGameId,
      'arResult': arResult,
      'category': category,
      'submissions': submissions.map((e) => e.toMap()).toList(),
      'modifiers': modifiers.map((e) => e.toMap()).toList(),
      'status': status.name,
      'deadline': deadline?.toIso8601String(),
      'durationSeconds': durationSeconds,
      'playerStatuses': playerStatuses.map(
        (key, value) => MapEntry(key, value.toMap()),
      ),
    };
  }

  Task copyWith({
    String? id,
    String? title,
    String? description,
    TaskType? taskType,
    String? puzzleAnswer,
    List<Submission>? submissions,
    List<TaskModifier>? modifiers,
    String? arGameId,
    int? arResult,
    String? category,
    TaskStatus? status,
    DateTime? deadline,
    int? durationSeconds,
    Map<String, PlayerTaskStatus>? playerStatuses,
  }) {
    return Task(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      taskType: taskType ?? this.taskType,
      puzzleAnswer: puzzleAnswer ?? this.puzzleAnswer,
      submissions: submissions ?? this.submissions,
      modifiers: modifiers ?? this.modifiers,
      arGameId: arGameId ?? this.arGameId,
      arResult: arResult ?? this.arResult,
      category: category ?? this.category,
      status: status ?? this.status,
      deadline: deadline ?? this.deadline,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      playerStatuses: playerStatuses ?? this.playerStatuses,
    );
  }

  bool get isVideoTask => taskType == TaskType.video;
  bool get isPuzzleTask => taskType == TaskType.puzzle;
  bool get isArTask => taskType == TaskType.ar;

  Submission? getSubmissionByUser(String userId) {
    try {
      return submissions.firstWhere((sub) => sub.userId == userId);
    } catch (e) {
      return null;
    }
  }

  bool hasUserSubmitted(String userId) {
    return submissions.any((sub) => sub.userId == userId);
  }

  int getTotalSubmissions() => submissions.length;

  int getJudgedSubmissions() {
    return submissions.where((sub) => sub.isJudged).length;
  }

  bool get allSubmissionsJudged {
    return submissions.isNotEmpty && 
           submissions.every((sub) => sub.isJudged);
  }

  int get totalPointsMultiplier {
    return modifiers.fold(1, (total, modifier) => total * modifier.pointsMultiplier);
  }

  bool get hasActiveModifiers => modifiers.any((modifier) => modifier.isActive);

  List<TaskModifier> get activeModifiers => modifiers.where((modifier) => modifier.isActive).toList();

  // NEW: Async game computed properties
  int get totalPlayers => playerStatuses.length;

  int get submittedCount =>
      playerStatuses.values.where((status) => status.hasSubmitted).length;

  int get judgedCount =>
      playerStatuses.values.where((status) => status.isJudged).length;

  bool get allPlayersSubmitted =>
      playerStatuses.isNotEmpty &&
      playerStatuses.values.every((status) => status.hasSubmitted);

  bool get allPlayersJudged =>
      playerStatuses.isNotEmpty &&
      playerStatuses.values.every((status) => status.isJudged);

  bool get isReadyToJudge =>
      status == TaskStatus.ready_to_judge || allPlayersSubmitted;

  bool get isCompleted => status == TaskStatus.completed;

  bool get hasDeadlinePassed =>
      deadline != null && DateTime.now().isAfter(deadline!);

  // Get player status for a specific user
  PlayerTaskStatus? getPlayerStatus(String playerId) {
    return playerStatuses[playerId];
  }

  // Check if a specific player has submitted
  bool hasPlayerSubmitted(String playerId) {
    return playerStatuses[playerId]?.hasSubmitted ?? false;
  }

  // Check if a specific player can view videos (privacy feature)
  bool canPlayerViewVideos(String playerId) {
    return playerStatuses[playerId]?.canViewVideos ?? false;
  }

  @override
  List<Object?> get props => [
        id,
        title,
        description,
        taskType,
        puzzleAnswer,
        submissions,
        modifiers,
        arGameId,
        arResult,
        category,
        status,
        deadline,
        durationSeconds,
        playerStatuses,
      ];
}