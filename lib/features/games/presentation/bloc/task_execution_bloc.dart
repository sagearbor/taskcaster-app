import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/config/e2e_mode.dart';
import '../../../../core/utils/friendly_errors.dart';
import '../../domain/repositories/game_repository.dart';
import '../../../../core/models/player_task_status.dart';
import '../../../../core/models/submission.dart';
import '../../../../core/models/task.dart';
import '../../../../core/services/plans/plan_repository.dart';
import '../../../../core/services/plans/plans.dart';
import '../../../../core/services/video/video_policy.dart';
import '../../../../core/services/video/video_uploader.dart';
import '../../../arena/domain/auto_edit.dart';
import '../../../arena/domain/models/feed_post.dart';
import '../../../arena/domain/repositories/feed_repository.dart';
import 'task_execution_event.dart';
import 'task_execution_state.dart';

/// Mark [userId] skipped on [task] and, once nobody is still working on it,
/// move the task to judging. Shared by the plain and AR skip paths; pure, so
/// it is safe inside a retried transaction.
Task skipPlayer(Task task, String userId) {
  // Treat a missing status (e.g. a player added mid-game) as a fresh,
  // not-started status instead of erroring out.
  final currentStatus = task.getPlayerStatus(userId) ??
      PlayerTaskStatus(playerId: userId, state: TaskPlayerState.not_started);
  // A submission already handed in is not thrown away by a stray skip.
  if (currentStatus.hasSubmitted) return task;

  final updatedStatuses = {
    ...task.playerStatuses,
    userId: currentStatus.copyWith(state: TaskPlayerState.skipped),
  };
  final allDone = updatedStatuses.values
      .every((s) => s.hasSubmitted || s.state == TaskPlayerState.skipped);
  final nextStatus = task.status == TaskStatus.ready_to_judge ||
          task.status == TaskStatus.completed
      ? task.status
      : (allDone
          ? TaskStatus.ready_to_judge
          : TaskStatus.waiting_for_submissions);

  return task.copyWith(playerStatuses: updatedStatuses, status: nextStatus);
}

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

  /// The player's plan (WP-11): which Storage slots to try, the clip-length
  /// cap and the upload size cap. Nullable so every existing test works
  /// without one — null means the free plan, which is also what the Storage
  /// rules assume for anyone without the server-owned Pro fields.
  final PlanRepository? planRepository;

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
    this.planRepository,
  }) : super(TaskExecutionInitial()) {
    on<LoadTask>(_onLoadTask);
    on<StartTask>(_onStartTask);
    // A second "Post it" while one is in flight is dropped (see
    // [_submitInFlight]), so a double tap can never create two submissions
    // or two Arena posts. (Done by hand rather than with bloc_concurrency's
    // droppable(): that transformer never lets bloc.close() finish under
    // flutter_test's fake clock, which hangs every widget test.)
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
          // Someone else's write mid-submit must not flip the upload bar
          // (or the inert Post it) back to the live form.
          final current = state;
          if (current is TaskExecutionUploading ||
              current is TaskExecutionSubmitting) {
            return current;
          }
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

      if (event.taskIndex >= game.tasks.length) {
        emit(const TaskExecutionError(message: 'Task not found'));
        return;
      }

      // Only this player's status changes, applied to the freshest copy of
      // the task inside a transaction.
      final startedAt = DateTime.now();
      await gameRepository.updateTaskAtomically(
        event.gameId,
        event.taskIndex,
        (fresh) {
          // Treat a missing status (e.g. a player added after the task was
          // created) as a fresh, not-started status instead of erroring out.
          final currentStatus = fresh.getPlayerStatus(event.userId) ??
              PlayerTaskStatus(
                playerId: event.userId,
                state: TaskPlayerState.not_started,
              );
          // Never move a player who already handed something in back to
          // in_progress (a second device, a stale screen).
          if (currentStatus.hasSubmitted ||
              currentStatus.state == TaskPlayerState.skipped) {
            return fresh;
          }
          return fresh.copyWith(
            playerStatuses: {
              ...fresh.playerStatuses,
              event.userId: currentStatus.copyWith(
                state: TaskPlayerState.in_progress,
                startedAt: currentStatus.startedAt ?? startedAt,
              ),
            },
          );
        },
      );
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
    final currentState = state;
    if (_submitInFlight || currentState is! TaskExecutionLoaded) return;
    _submitInFlight = true;
    try {
      await _submit(event, currentState, emit);
    } finally {
      _submitInFlight = false;
    }
  }

  /// True from the moment a SubmitTask is accepted until it has finished.
  bool _submitInFlight = false;

  Future<void> _submit(
    SubmitTask event,
    TaskExecutionLoaded currentState,
    Emitter<TaskExecutionState> emit,
  ) async {
    // Leave the Loaded state BEFORE the first await, so the Post it button
    // goes inert at once (and the guard above turns away any straggler).
    // (A clip moves on to TaskExecutionUploading once its upload starts.)
    emit(TaskExecutionSubmitting(task: currentState.task));

    try {
      // Read once for what the post needs (timer, twist, settings). The
      // submission itself is written later against a FRESH copy.
      final game = await gameRepository
          .getGameStream(event.gameId)
          .first;

      if (game == null) {
        emit(const TaskExecutionError(message: 'Game not found'));
        return;
      }
      if (event.taskIndex >= game.tasks.length) {
        emit(const TaskExecutionError(message: 'Task not found'));
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
        final plan = await planRepository?.currentPlan() ?? UserPlan.free;
        final limits = plan.limits;
        final reject = VideoPolicy.rejectReason(
          bytes: clip.byteCount,
          maxBytes: limits.maxUploadBytes,
        );
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

        final capSeconds = VideoPolicy.clipCapSeconds(
          timerSeconds,
          planCapSeconds: limits.clipSeconds,
        );
        emit(TaskExecutionUploading(progress: 0, task: task));

        var lastEmitted = 0.0;
        try {
          final upload = await uploader.upload(
            userId: event.userId,
            bytes: clip.bytes,
            contentType: clip.contentType,
            when: now,
            limits: limits,
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
          // Not an error screen: back to the task (the filmed clip is still
          // there) with the upgrade prompt on top, whose first option is
          // posting a photo instead. See TaskExecutionPlanLimitReached.
          emit(TaskExecutionPlanLimitReached(
            tier: e.tier,
            task: currentState.task,
            userStatus: currentState.userStatus,
            allPlayerStatuses: currentState.allPlayerStatuses,
            taskNumber: currentState.taskNumber,
            totalTasks: currentState.totalTasks,
          ));
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
          // WP-09: Starter Pack attempts are public by design (the share
          // page treats an absent flag the same way); say so explicitly.
          // Friend-game posts stay unset = private until the owner shares.
          // Fun audit WP-1: an automated walk (E2eMode) posts privately, so
          // its test patterns never reach the public Arena or a finale.
          shareable: E2eMode.isOn
              ? false
              : (task.id.startsWith('starter-') ? true : null),
        ));
      }

      // ---- Record it: upload done, so NOW write, against the freshest copy --
      // The upload above can take a minute. Writing the game read before it
      // would wipe everything other players (and the judge) did meanwhile,
      // so the change is re-applied to the current task in a transaction and
      // touches only this player's status and submission.
      final submissionUrl =
          event.videoUrl ?? (feedPostId != null ? 'arena:$feedPostId' : null);
      final newSubmissionId = _uuid.v4();
      await gameRepository.updateTaskAtomically(
        event.gameId,
        event.taskIndex,
        (fresh) {
          final status = fresh.getPlayerStatus(event.userId) ??
              PlayerTaskStatus(
                playerId: event.userId,
                state: TaskPlayerState.not_started,
              );
          // `arena:<postId>` marks an attempt that lives in the Arena rather
          // than behind a link.
          final updatedStatuses = {
            ...fresh.playerStatuses,
            event.userId: status.copyWith(
              state: TaskPlayerState.submitted,
              submittedAt: now,
              submissionUrl: submissionUrl,
            ),
          };

          // Keep the submissions list in step with the per-player status, so
          // the crowd-score applier can find the post id and the judge /
          // scoreboard logic (which reads submissions[]) agrees.
          final submissions = List<Submission>.from(fresh.submissions);
          final existingIndex =
              submissions.indexWhere((s) => s.userId == event.userId);
          final submission = Submission(
            id: existingIndex >= 0
                ? submissions[existingIndex].id
                : newSubmissionId,
            userId: event.userId,
            videoUrl: clipUrl ?? event.videoUrl,
            score: existingIndex >= 0 ? submissions[existingIndex].score : 0,
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
            submissions[existingIndex] = submission;
          } else {
            submissions.add(submission);
          }

          final allSubmitted =
              updatedStatuses.values.every((s) => s.hasSubmitted);
          // Never pull a task that is already being judged (or done) back.
          final nextStatus = fresh.status == TaskStatus.ready_to_judge ||
                  fresh.status == TaskStatus.completed
              ? fresh.status
              : (allSubmitted
                  ? TaskStatus.ready_to_judge
                  : TaskStatus.waiting_for_submissions);

          return fresh.copyWith(
            playerStatuses: updatedStatuses,
            submissions: submissions,
            status: nextStatus,
          );
        },
      );

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

      if (event.taskIndex >= game.tasks.length) {
        emit(const TaskExecutionError(message: 'Task not found'));
        return;
      }

      await gameRepository.updateTaskAtomically(
        event.gameId,
        event.taskIndex,
        (fresh) => skipPlayer(fresh, event.userId),
      );

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