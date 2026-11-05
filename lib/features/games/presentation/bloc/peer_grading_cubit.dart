import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/models/game.dart';
import '../../../../core/models/submission.dart';
import '../../../../core/models/task.dart';
import '../../domain/peer_grading.dart';
import '../../domain/repositories/game_repository.dart';

/// Entries this device graded in this app session, by game and task, so the
/// game screen's hero stops offering "Grade 1 entry" the moment you grade it
/// rather than when the server echoes [Task.peerGraders] a second later.
class RecentPeerGrades {
  RecentPeerGrades._();

  static final Map<String, Set<String>> _byTask = {};

  static String _key(String gameId, String taskId) => '$gameId/$taskId';

  static void add(String gameId, String taskId, String targetUid) =>
      _byTask.putIfAbsent(_key(gameId, taskId), () => {}).add(targetUid);

  static Set<String> targets(String gameId, String taskId) =>
      Set.unmodifiable(_byTask[_key(gameId, taskId)] ?? const <String>{});

  @visibleForTesting
  static void clear() => _byTask.clear();
}

sealed class PeerGradingState extends Equatable {
  const PeerGradingState();

  @override
  List<Object?> get props => [];
}

class PeerGradingLoading extends PeerGradingState {
  const PeerGradingLoading();
}

/// The game or task is gone (deleted, or the index no longer exists).
class PeerGradingUnavailable extends PeerGradingState {
  const PeerGradingUnavailable();
}

class PeerGradingReady extends PeerGradingState {
  final Game game;
  final Task task;

  /// Entries still to grade, in roster order; the first one is on screen.
  final List<Submission> queue;

  /// How many this player has graded on this task (server + this session).
  final int gradedCount;

  /// A grade is being written; the grade bar ignores taps meanwhile.
  final bool submitting;

  /// A one-shot error line (network trouble), or null.
  final String? error;

  const PeerGradingReady({
    required this.game,
    required this.task,
    required this.queue,
    required this.gradedCount,
    this.submitting = false,
    this.error,
  });

  Submission? get current => queue.isEmpty ? null : queue.first;
  bool get isDone => queue.isEmpty;

  @override
  List<Object?> get props => [game, task, queue, gradedCount, submitting, error];
}

/// The in-game grade queue for one task of a group-graded game (WP-13): every
/// other player's posted entry you have not graded yet, one at a time.
class PeerGradingCubit extends Cubit<PeerGradingState> {
  final GameRepository gameRepository;
  final String gameId;
  final int taskIndex;
  final String currentUserId;

  StreamSubscription<Game?>? _sub;
  Game? _game;
  bool _submitting = false;
  String? _error;

  PeerGradingCubit({
    required this.gameRepository,
    required this.gameId,
    required this.taskIndex,
    required this.currentUserId,
  }) : super(const PeerGradingLoading()) {
    _sub = gameRepository.getGameStream(gameId).listen(
      (game) {
        _game = game;
        _emitReady();
      },
      onError: (Object e) {
        debugPrint('PeerGradingCubit stream failed: $e');
        if (_game == null) emit(const PeerGradingUnavailable());
      },
    );
  }

  Set<String> get _localTargets {
    final task = _task;
    return task == null
        ? const {}
        : RecentPeerGrades.targets(gameId, task.id);
  }

  Task? get _task {
    final game = _game;
    if (game == null || taskIndex < 0 || taskIndex >= game.tasks.length) {
      return null;
    }
    return game.tasks[taskIndex];
  }

  void _emitReady() {
    if (isClosed) return;
    final game = _game;
    final task = _task;
    if (game == null || task == null) {
      emit(const PeerGradingUnavailable());
      return;
    }
    final local = _localTargets;
    final queue = PeerGrading.queue(game, taskIndex, currentUserId,
        alsoGraded: local);
    final graded = {
      for (final e in task.peerGraders.entries)
        if (e.value.contains(currentUserId)) e.key,
      ...local,
    };
    emit(PeerGradingReady(
      game: game,
      task: task,
      queue: queue,
      gradedCount: graded.length,
      submitting: _submitting,
      error: _error,
    ));
  }

  /// Grade [targetUid]'s entry with [score] (1..5).
  Future<void> grade(String targetUid, int score) async {
    final task = _task;
    if (task == null || _submitting) return;
    _submitting = true;
    _error = null;
    _emitReady();
    try {
      await gameRepository.submitPeerGrade(
        gameId: gameId,
        taskIndex: taskIndex,
        taskId: task.id,
        targetUid: targetUid,
        graderUid: currentUserId,
        score: score,
      );
      RecentPeerGrades.add(gameId, task.id, targetUid);
    } on PeerGradeRejected catch (e) {
      // Already graded (another device, a double tap) or the score just
      // locked: either way there is nothing left to do for this entry.
      debugPrint('PeerGradingCubit: grade refused, skipping entry: $e');
      RecentPeerGrades.add(gameId, task.id, targetUid);
    } catch (e) {
      debugPrint('PeerGradingCubit: grade failed: $e');
      _error = "Couldn't save that grade. Check your connection and try again.";
    } finally {
      _submitting = false;
      _emitReady();
    }
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}
