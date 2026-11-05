import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/models/player_task_status.dart';
import '../../../../core/models/task.dart';
import '../../../../core/services/ar/ar_capability_service.dart';
import '../../domain/repositories/game_repository.dart';

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

abstract class ArTaskEvent extends Equatable {
  const ArTaskEvent();

  @override
  List<Object?> get props => [];
}

/// Probe device capability (runs on screen entry).
class ArCheckRequested extends ArTaskEvent {
  const ArCheckRequested();
}

/// Ask the OS for the camera permission, then re-evaluate.
class ArCameraRequested extends ArTaskEvent {
  const ArCameraRequested();
}

/// Begin the (placeholder) AR session — Ready -> Playing.
class ArPlayStarted extends ArTaskEvent {
  const ArPlayStarted();
}

/// Submit a final AR score. In the current scaffold this is fired by a
/// dev-only "Simulate score" button; later it is fired by the real mini-game.
class ArScoreSubmitted extends ArTaskEvent {
  final int score;
  final int? rawResult;

  const ArScoreSubmitted({required this.score, this.rawResult});

  @override
  List<Object?> get props => [score, rawResult];
}

/// Skip the AR task so an unsupported/blocked player is never stuck.
class ArSkipRequested extends ArTaskEvent {
  const ArSkipRequested();
}

// ---------------------------------------------------------------------------
// States
// ---------------------------------------------------------------------------

abstract class ArTaskState extends Equatable {
  const ArTaskState();

  @override
  List<Object?> get props => [];
}

/// Probing device capability.
class ArTaskChecking extends ArTaskState {
  const ArTaskChecking();
}

/// AR cannot run on this platform/device.
class ArTaskUnsupported extends ArTaskState {
  final ArSupport reason;

  const ArTaskUnsupported(this.reason);

  @override
  List<Object?> get props => [reason];
}

/// Camera permission is required but denied.
class ArTaskPermissionDenied extends ArTaskState {
  const ArTaskPermissionDenied();
}

/// Capability confirmed — ready to start the mini-game.
class ArTaskReady extends ArTaskState {
  const ArTaskReady();
}

/// The mini-game is in progress.
class ArTaskPlaying extends ArTaskState {
  const ArTaskPlaying();
}

/// The mini-game finished with a [score] but is not yet submitted.
class ArTaskFinished extends ArTaskState {
  final int score;
  final int? rawResult;

  const ArTaskFinished({required this.score, this.rawResult});

  @override
  List<Object?> get props => [score, rawResult];
}

/// Writing the score to the scoreboard.
class ArTaskSubmitting extends ArTaskState {
  const ArTaskSubmitting();
}

/// Score successfully written to the scoreboard (or task skipped).
class ArTaskSubmitted extends ArTaskState {
  const ArTaskSubmitted();
}

/// A recoverable error (capability probing never lands here — it maps to
/// [ArTaskUnsupported] instead).
class ArTaskError extends ArTaskState {
  final String message;

  const ArTaskError(this.message);

  @override
  List<Object?> get props => [message];
}

// ---------------------------------------------------------------------------
// Bloc
// ---------------------------------------------------------------------------

class ArTaskBloc extends Bloc<ArTaskEvent, ArTaskState> {
  final ArCapabilityService capabilityService;
  final GameRepository gameRepository;
  final String gameId;
  final int taskIndex;
  final String userId;

  ArTaskBloc({
    required this.capabilityService,
    required this.gameRepository,
    required this.gameId,
    required this.taskIndex,
    required this.userId,
  }) : super(const ArTaskChecking()) {
    on<ArCheckRequested>(_onCheck);
    on<ArCameraRequested>(_onRequestCamera);
    on<ArPlayStarted>(_onPlay);
    on<ArScoreSubmitted>(_onSubmitScore);
    on<ArSkipRequested>(_onSkip);
  }

  Future<void> _onCheck(
    ArCheckRequested event,
    Emitter<ArTaskState> emit,
  ) async {
    emit(const ArTaskChecking());
    final support = await capabilityService.check();
    emit(_mapSupport(support));
  }

  Future<void> _onRequestCamera(
    ArCameraRequested event,
    Emitter<ArTaskState> emit,
  ) async {
    emit(const ArTaskChecking());
    final granted = await capabilityService.requestCamera();
    if (!granted) {
      emit(const ArTaskPermissionDenied());
      return;
    }
    // Re-run the full check now that the permission may have changed.
    final support = await capabilityService.check();
    emit(_mapSupport(support));
  }

  void _onPlay(ArPlayStarted event, Emitter<ArTaskState> emit) {
    emit(const ArTaskPlaying());
  }

  Future<void> _onSubmitScore(
    ArScoreSubmitted event,
    Emitter<ArTaskState> emit,
  ) async {
    emit(const ArTaskSubmitting());
    try {
      await gameRepository.submitArResult(
        gameId,
        taskIndex,
        userId,
        event.score,
        rawResult: event.rawResult,
      );
      emit(const ArTaskSubmitted());
    } catch (e) {
      emit(ArTaskError(e.toString()));
    }
  }

  /// Skip the AR task. Mirrors the existing TaskExecutionBloc skip path: mark
  /// the player's status skipped and advance the task via updateGame. Honors
  /// the game's allowSkips setting.
  Future<void> _onSkip(
    ArSkipRequested event,
    Emitter<ArTaskState> emit,
  ) async {
    emit(const ArTaskSubmitting());
    try {
      final game = await gameRepository.getGameStream(gameId).first;
      if (game == null) {
        emit(const ArTaskError('Game not found'));
        return;
      }
      if (!game.settings.allowSkips) {
        emit(const ArTaskError('Skipping tasks is not allowed in this game'));
        return;
      }
      if (taskIndex >= game.tasks.length) {
        emit(const ArTaskError('Task not found'));
        return;
      }

      final task = game.tasks[taskIndex];
      final currentStatus = task.getPlayerStatus(userId) ??
          PlayerTaskStatus(playerId: userId, state: TaskPlayerState.not_started);

      final updatedStatuses = {
        ...task.playerStatuses,
        userId: currentStatus.copyWith(state: TaskPlayerState.skipped),
      };

      final allDone = updatedStatuses.values
          .every((s) => s.hasSubmitted || s.state == TaskPlayerState.skipped);

      final updatedTask = task.copyWith(
        playerStatuses: updatedStatuses,
        status: allDone
            ? TaskStatus.ready_to_judge
            : TaskStatus.waiting_for_submissions,
      );

      final updatedTasks = List<Task>.from(game.tasks);
      updatedTasks[taskIndex] = updatedTask;

      await gameRepository.updateGame(
        gameId,
        game.copyWith(tasks: updatedTasks),
      );
      emit(const ArTaskSubmitted());
    } catch (e) {
      emit(ArTaskError(e.toString()));
    }
  }

  ArTaskState _mapSupport(ArSupport support) {
    switch (support) {
      case ArSupport.supported:
        return const ArTaskReady();
      case ArSupport.cameraDenied:
        return const ArTaskPermissionDenied();
      case ArSupport.unsupportedPlatform:
      case ArSupport.needsArCoreUpdate:
      case ArSupport.unknownError:
        return ArTaskUnsupported(support);
    }
  }
}
