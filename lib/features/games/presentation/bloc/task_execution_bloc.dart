import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/utils/friendly_errors.dart';
import '../../domain/repositories/game_repository.dart';
import '../../../../core/models/player_task_status.dart';
import '../../../../core/models/submission.dart';
import '../../../../core/models/task.dart';
import '../../../../core/services/video/video_policy.dart';
import '../../../../core/services/video/video_uploader.dart';
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

  /// Puts in-app clips in the bucket. Nullable so every flow that never films
  /// anything (and every existing test) works with no uploader wired up — a
  /// null uploader simply means a clip submission is refused politely.
  final VideoUploader? videoUploader;

  final Uuid _uuid = const Uuid();

  /// Largest inline photo we will store on a post, in bytes of base64. Above
  /// this a Firestore document starts flirting with its 1 MB ceiling.
  static const int maxPhotoDataBytes = 400 * 1024;

  /// Upload progress is emitted in steps of this fraction, so a 30 MB clip
  /// produces ~20 states rather than one per chunk.
  static const double uploadProgressStep = 0.05;

  TaskExecutionBloc({
    required this.gameRepository,
    this.feedRepository,
    this.videoUploader,
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

      final clip = event.video;

      final mediaType = clip != null
          ? SubmissionMediaType.video
          : (event.photoBytes != null
              ? SubmissionMediaType.photo
              : (event.text != null
                  ? SubmissionMediaType.text
                  : SubmissionMediaType.link));

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

      // ---- In-app clip: size gate, then upload with progress ----------------
      // The clip was auto-trimmed at capture (the recorder's maxDuration), so
      // the only thing left to refuse here is size. Everything else is a cost
      // control the Storage rules enforce for us; see VideoPolicy.
      String? clipUrl;
      String? clipStoragePath;
      int? clipBytes;
      String? clipContentType;
      if (clip != null) {
        final reject = VideoPolicy.rejectReason(bytes: clip.byteCount);
        if (reject != null) {
          emit(TaskExecutionError(message: reject));
          return;
        }

        final uploader = videoUploader;
        if (uploader == null) {
          emit(const TaskExecutionError(
            message: "Clips aren't available right now — snap a photo instead.",
          ));
          return;
        }

        final capSeconds = VideoPolicy.clipCapSeconds(timerSeconds);
        emit(TaskExecutionUploading(progress: 0, task: task));

        var lastEmitted = 0.0;
        try {
          final upload = await uploader.upload(
            userId: event.userId,
            bytes: clip.bytes,
            contentType: clip.contentType,
            when: now,
            // Everything a later server-side splice needs to rebuild the task
            // clock over this clip without reading pixels.
            metadata: {
              'gameId': event.gameId,
              'taskId': task.id,
              'userId': event.userId,
              'clipCapSeconds': '$capSeconds',
              if (timerSeconds != null) 'timerSeconds': '$timerSeconds',
              if (event.clockOffsetSeconds != null)
                'clockOffsetSeconds': '${event.clockOffsetSeconds}',
              if (elapsedSeconds != null) 'elapsedSeconds': '$elapsedSeconds',
              'isLate': '$isLate',
            },
            onProgress: (fraction) {
              if (emit.isDone) return;
              if (fraction < 1 &&
                  fraction - lastEmitted < uploadProgressStep) {
                return;
              }
              lastEmitted = fraction;
              emit(TaskExecutionUploading(progress: fraction, task: task));
            },
          );
          clipUrl = upload.downloadUrl;
          clipStoragePath = upload.storagePath;
          clipBytes = upload.bytes;
          clipContentType = clip.contentType;
        } on DailyVideoLimitReached catch (e) {
          emit(TaskExecutionError(message: e.message));
          return;
        } catch (e) {
          debugPrint('TaskExecutionBloc clip upload failed: $e');
          emit(TaskExecutionError(
            message: FriendlyErrors.action(
              e,
              fallback: "Couldn't post that clip. Please try again.",
            ),
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
          clipUrl != null ||
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
          // A clip reuses videoUrl for its download URL; mediaType is what
          // tells it apart from a pasted link.
          videoUrl: clipUrl ?? event.videoUrl,
          videoStoragePath: clipStoragePath,
          videoBytes: clipBytes,
          videoContentType: clipContentType,
          // Unknown at upload time — playback trims at the cap regardless.
          videoDurationSeconds: null,
          clockOffsetSeconds: clip == null ? null : event.clockOffsetSeconds,
          timerSeconds: clip == null ? null : timerSeconds,
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
        videoUrl: clipUrl ?? event.videoUrl,
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
        videoStoragePath: clipStoragePath,
        videoBytes: clipBytes,
        videoContentType: clipContentType,
        clockOffsetSeconds: clip == null ? null : event.clockOffsetSeconds,
        timerSeconds: clip == null ? null : timerSeconds,
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