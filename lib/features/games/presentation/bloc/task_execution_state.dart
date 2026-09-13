import 'package:equatable/equatable.dart';
import '../../../../core/models/task.dart';
import '../../../../core/models/player_task_status.dart';

abstract class TaskExecutionState extends Equatable {
  const TaskExecutionState();

  @override
  List<Object?> get props => [];
}

class TaskExecutionInitial extends TaskExecutionState {}

class TaskExecutionLoading extends TaskExecutionState {}

class TaskExecutionLoaded extends TaskExecutionState {
  final Task task;
  final PlayerTaskStatus? userStatus;
  final Map<String, PlayerTaskStatus> allPlayerStatuses;
  final int taskNumber; // e.g., "Task 2 of 5"
  final int totalTasks;

  const TaskExecutionLoaded({
    required this.task,
    this.userStatus,
    required this.allPlayerStatuses,
    required this.taskNumber,
    required this.totalTasks,
  });

  bool get hasUserSubmitted => userStatus?.hasSubmitted ?? false;
  bool get canUserViewVideos => userStatus?.canViewVideos ?? false;

  int get submittedCount =>
      allPlayerStatuses.values.where((s) => s.hasSubmitted).length;
  int get totalPlayers => allPlayerStatuses.length;

  @override
  List<Object?> get props => [
        task,
        userStatus,
        allPlayerStatuses,
        taskNumber,
        totalTasks,
      ];
}

/// A clip is on its way to the bucket. The only state with a progress value —
/// photo and text submissions are inline and never reach it.
///
/// [progress] runs 0..1 and is emitted in ~5 % steps so the bar moves without
/// flooding the bloc with states.
class TaskExecutionUploading extends TaskExecutionState {
  final double progress;

  /// The task being submitted, so the screen can keep the title/twist on
  /// screen while the bar fills instead of flashing a bare spinner.
  final Task task;

  const TaskExecutionUploading({
    required this.progress,
    required this.task,
  });

  /// Whole percent, for the "Uploading… 42%" label.
  int get percent => (progress.clamp(0.0, 1.0) * 100).round();

  @override
  List<Object?> get props => [progress, task];
}

class TaskExecutionSubmitted extends TaskExecutionState {
  final String gameId;
  final int taskIndex;

  /// The Arena post this attempt created, when it was shared. Null for a
  /// submission that stayed private (or a skip).
  final String? feedPostId;

  /// True when the player went past `durationSeconds + 30 s` of grace — the
  /// red LATE badge everyone sees.
  final bool isLate;

  const TaskExecutionSubmitted({
    required this.gameId,
    required this.taskIndex,
    this.feedPostId,
    this.isLate = false,
  });

  @override
  List<Object?> get props => [gameId, taskIndex, feedPostId, isLate];
}

class TaskExecutionError extends TaskExecutionState {
  final String message;

  const TaskExecutionError({required this.message});

  @override
  List<Object> get props => [message];
}