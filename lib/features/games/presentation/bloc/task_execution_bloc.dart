import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/utils/friendly_errors.dart';
import '../../domain/repositories/game_repository.dart';
import '../../../../core/models/player_task_status.dart';
import '../../../../core/models/submission.dart';
import '../../../../core/models/task.dart';
import '../../../arena/domain/auto_edit.dart';
import '../../../arena/domain/models/feed_post.dart';
import '../../../arena/domain/repositories/feed_repository.dart';
import 'task_execution_event.dart';
import 'task_execution_state.dart';

class TaskExecutionBloc extends Bloc<TaskExecutionEvent, TaskExecutionState> {
  final GameRepository gameRepository;

  /// The Arena. Nullable so the plain "paste a link" flow (and every existing
  /// test) works with no Arena wired up at all — a null repository simply
  /// means nothing is ever posted.
  final FeedRepository? feedRepository;

  final Uuid _uuid = const Uuid();

  /// Largest inline photo we will store on a post, in bytes of base64. Above
  /// this a Firestore document starts flirting with its 1 MB ceiling.
  static const int maxPhotoDataBytes = 400 * 1024;

  TaskExecutionBloc({
    required this.gameRepository,
    this.feedRepository,
  }) : super(TaskExecutionInitial()) {
    on<LoadTask>(_onLoadTask);
    on<StartTask>(_onStartTask);
    on<SubmitTask>(_onSubmitTask);
    on<SkipTask>(_onSkipTask);
  }

  Future<void> _onLoadTask(
    LoadTask event,
    Emitter<TaskExecutionState> emit,
  ) async {
    try {
      emit(TaskExecutionLoading());

      // Listen to game stream to get real-time updates
      await emit.forEach(
        gameRepository.getGameStream(event.gameId),
        onData: (game) {
          if (game == null) {
            return TaskExecutionError(message: 'Game not found');
          }

          if (event.taskIndex >= game.tasks.length) {
            return TaskExecutionError(message: 'Task not found');
          }

          final task = game.tasks[event.taskIndex];
          final userStatus = task.getPlayerStatus(event.userId);
          final allPlayerStatuses = task.playerStatuses;

          return TaskExecutionLoaded(
            task: task,
            userStatus: userStatus,
            allPlayerStatuses: allPlayerStatuses,
            taskNumber: event.taskIndex + 1,
            totalTasks: game.tasks.length,
          );
        },
        onError: (error, stackTrace) {
          debugPrint('TaskExecutionBloc.LoadTask stream error: $error');
          return TaskExecutionError(
            message: FriendlyErrors.action(
              error,
              fallback: "Couldn't load the task. Please try again.",
            ),
          );
        },
      );
    } catch (e) {
      debugPrint('TaskExecutionBloc.LoadTask failed: $e');
      emit(TaskExecutionError(
        message: FriendlyErrors.action(
          e,
          fallback: "Couldn't load the task. Please try again.",
        ),
      ));
    }
  }

  Future<void> _onStartTask(
    StartTask event,
    Emitter<TaskExecutionState> emit,
  ) async {
    try {
      final currentState = state;
      if (currentState is! TaskExecutionLoaded) return;

      // Get current game
      final game = await gameRepository
          .getGameStream(event.gameId)
          .first;

      if (game == null) {
        emit(const TaskExecutionError(message: 'Game not found'));
        return;
      }

      final task = game.tasks[event.taskIndex];
      // Treat a missing status (e.g. a player added after the task was created)
      // as a fresh, not-started status instead of erroring out.
      final currentStatus = task.getPlayerStatus(event.userId) ??
          PlayerTaskStatus(
            playerId: event.userId,
            state: TaskPlayerState.not_started,
          );

      // Update player status to in_progress
      final updatedStatus = currentStatus.copyWith(
        state: TaskPlayerState.in_progress,
        startedAt: DateTime.now(),
      );

      final updatedTask = task.copyWith(
        playerStatuses: {
          ...task.playerStatuses,
          event.userId: updatedStatus,
        },
      );

      final updatedTasks = List<Task>.from(game.tasks);
      updatedTasks[event.taskIndex] = updatedTask;

      final updatedGame = game.copyWith(tasks: updatedTasks);

      await gameRepository.updateGame(event.gameId, updatedGame);
    } catch (e) {
      debugPrint('TaskExecutionBloc.StartTask failed: $e');
      emit(TaskExecutionError(
        message: FriendlyErrors.action(
          e,
          fallback: "Couldn't start the task. Please try again.",
        ),
      ));
    }
  }

  Future<void> _onSubmitTask(
    SubmitTask event,
    Emitter<TaskExecutionState> emit,
  ) async {
    try {
      final currentState = state;
      if (currentState is! TaskExecutionLoaded) return;

      // Get current game
      final game = await gameRepository
          .getGameStream(event.gameId)
          .first;

      if (game == null) {
        emit(const TaskExecutionError(message: 'Game not found'));
        return;
      }

      final task = game.tasks[event.taskIndex];
      // Treat a missing status (e.g. a player added mid-game) as a fresh,
      // not-started status instead of erroring out.
      final currentStatus = task.getPlayerStatus(event.userId) ??
          PlayerTaskStatus(
            playerId: event.userId,
            state: TaskPlayerState.not_started,
          );

      // ---- Auto-edit: everything the post shows is computed, never typed ----
      final now = DateTime.now();
      final startedAt = currentStatus.startedAt;
      final timerSeconds = task.durationSeconds;
      final elapsedSeconds =
          startedAt == null ? null : now.difference(startedAt).inSeconds;
      final isLate = elapsedSeconds != null &&
          timerSeconds != null &&
          elapsedSeconds > timerSeconds + AutoEdit.graceSeconds;

      final mediaType = event.photoBytes != null
          ? SubmissionMediaType.photo
          : (event.text != null
              ? SubmissionMediaType.text
              : SubmissionMediaType.link);

      String? photoData;
      if (event.photoBytes != null) {
        photoData = base64Encode(event.photoBytes!);
        if (photoData.length > maxPhotoDataBytes) {
          emit(const TaskExecutionError(
            message: "That photo is too big to post — try a smaller one.",
          ));
          return;
        }
      }

      final stamp = AutoEdit.stamp(
        mediaType: mediaType,
        elapsedSeconds: elapsedSeconds,
        timerSeconds: timerSeconds,
        isLate: isLate,
      );
      final caption = AutoEdit.caption(
        twist: task.twist,
        elapsedSeconds: elapsedSeconds,
        timerSeconds: timerSeconds,
        isLate: isLate,
      );

      // ---- Post to the Arena FIRST, so the submission can carry its id ----
      String? feedPostId;
      final feed = feedRepository;
      final hasArenaContent = photoData != null ||
          (event.text != null && event.text!.isNotEmpty) ||
          (event.videoUrl != null && event.videoUrl!.isNotEmpty);
      if (feed != null &&
          event.shareToArena &&
          game.settings.shareToArena &&
          hasArenaContent) {
        feedPostId = await feed.createPost(FeedPost(
          id: '',
          gameId: event.gameId,
          taskId: task.id,
          taskTitle: task.title,
          rubric: task.rubric,
          userId: event.userId,
          displayName: event.displayName,
          mediaType: mediaType,
          photoData: photoData,
          text: event.text,
          videoUrl: event.videoUrl,
          caption: caption.isEmpty ? null : caption,
          stamp: stamp,
          isLate: isLate,
          createdAt: now,
          elapsedSeconds: elapsedSeconds,
        ));
      }

      // Update player status to submitted. `arena:<postId>` is the marker for
      // an attempt that lives in the Arena rather than behind a link.
      final updatedStatus = currentStatus.copyWith(
        state: TaskPlayerState.submitted,
        submittedAt: now,
        submissionUrl: event.videoUrl ??
            (feedPostId != null ? 'arena:$feedPostId' : null),
      );

      final updatedPlayerStatuses = {
        ...task.playerStatuses,
        event.userId: updatedStatus,
      };

      // Keep the submissions list in step with the per-player status, so the
      // crowd-score applier can find the post id and the judge/scoreboard
      // logic (which reads submissions[]) agrees with the statuses.
      final updatedSubmissions = List<Submission>.from(task.submissions);
      final existingIndex =
          updatedSubmissions.indexWhere((s) => s.userId == event.userId);
      final submission = Submission(
        id: existingIndex >= 0 ? updatedSubmissions[existingIndex].id : _uuid.v4(),
        userId: event.userId,
        videoUrl: event.videoUrl,
        score: existingIndex >= 0 ? updatedSubmissions[existingIndex].score : 0,
        isJudged: false,
        submittedAt: now,
        mediaType: mediaType,
        text: event.text,
        caption: caption.isEmpty ? null : caption,
        stamp: stamp,
        isLate: isLate,
        elapsedSeconds: elapsedSeconds,
        feedPostId: feedPostId,
      );
      if (existingIndex >= 0) {
        updatedSubmissions[existingIndex] = submission;
      } else {
        updatedSubmissions.add(submission);
      }

      // Check if all players submitted
      final allSubmitted =
          updatedPlayerStatuses.values.every((s) => s.hasSubmitted);

      final updatedTask = task.copyWith(
        playerStatuses: updatedPlayerStatuses,
        submissions: updatedSubmissions,
        status: allSubmitted
            ? TaskStatus.ready_to_judge
            : TaskStatus.waiting_for_submissions,
      );

      final updatedTasks = List<Task>.from(game.tasks);
      updatedTasks[event.taskIndex] = updatedTask;

      final updatedGame = game.copyWith(tasks: updatedTasks);

      await gameRepository.updateGame(event.gameId, updatedGame);

      emit(TaskExecutionSubmitted(
        gameId: event.gameId,
        taskIndex: event.taskIndex,
        feedPostId: feedPostId,
        isLate: isLate,
      ));
    } catch (e) {
      debugPrint('TaskExecutionBloc.SubmitTask failed: $e');
      emit(TaskExecutionError(
        message: FriendlyErrors.action(
          e,
          fallback: "Couldn't submit your attempt. Please try again.",
        ),
      ));
    }
  }

  Future<void> _onSkipTask(
    SkipTask event,
    Emitter<TaskExecutionState> emit,
  ) async {
    try {
      final currentState = state;
      if (currentState is! TaskExecutionLoaded) return;

      // Get current game
      final game = await gameRepository
          .getGameStream(event.gameId)
          .first;

      if (game == null) {
        emit(const TaskExecutionError(message: 'Game not found'));
        return;
      }

      // Check if game settings allow skips
      if (!game.settings.allowSkips) {
        emit(const TaskExecutionError(
            message: 'Skipping tasks is not allowed in this game'));
        return;
      }

      final task = game.tasks[event.taskIndex];
      // Treat a missing status (e.g. a player added mid-game) as a fresh,
      // not-started status instead of erroring out.
      final currentStatus = task.getPlayerStatus(event.userId) ??
          PlayerTaskStatus(
            playerId: event.userId,
            state: TaskPlayerState.not_started,
          );

      // Update player status to skipped
      final updatedStatus = currentStatus.copyWith(
        state: TaskPlayerState.skipped,
      );

      final updatedPlayerStatuses = {
        ...task.playerStatuses,
        event.userId: updatedStatus,
      };

      // Check if all players submitted or skipped
      final allDone = updatedPlayerStatuses.values
          .every((s) => s.hasSubmitted || s.state == TaskPlayerState.skipped);

      final updatedTask = task.copyWith(
        playerStatuses: updatedPlayerStatuses,
        status:
            allDone ? TaskStatus.ready_to_judge : TaskStatus.waiting_for_submissions,
      );

      final updatedTasks = List<Task>.from(game.tasks);
      updatedTasks[event.taskIndex] = updatedTask;

      final updatedGame = game.copyWith(tasks: updatedTasks);

      await gameRepository.updateGame(event.gameId, updatedGame);

      emit(TaskExecutionSubmitted(
        gameId: event.gameId,
        taskIndex: event.taskIndex,
      ));
    } catch (e) {
      debugPrint('TaskExecutionBloc.SkipTask failed: $e');
      emit(TaskExecutionError(
        message: FriendlyErrors.action(
          e,
          fallback: "Couldn't skip the task. Please try again.",
        ),
      ));
    }
  }
}