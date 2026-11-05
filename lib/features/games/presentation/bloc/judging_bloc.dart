import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/models/game.dart';
import '../../../../core/utils/friendly_errors.dart';
import '../../domain/repositories/game_repository.dart';
import 'judging_event.dart';
import 'judging_state.dart';

class JudgingBloc extends Bloc<JudgingEvent, JudgingState> {
  final GameRepository gameRepository;

  /// Judges award whole points from [minScore] to [maxScore] per submission.
  static const int minScore = 0;
  static const int maxScore = 10;

  JudgingBloc({required this.gameRepository}) : super(JudgingInitial()) {
    on<LoadSubmissions>(_onLoadSubmissions);
    on<ScoreSubmission>(_onScoreSubmission);
    on<SkipSubmission>(_onSkipSubmission);
    on<FinishJudging>(_onFinishJudging);
  }

  Future<void> _onLoadSubmissions(
    LoadSubmissions event,
    Emitter<JudgingState> emit,
  ) async {
    emit(JudgingLoading());

    try {
      // Load game and task
      final game = await gameRepository.getGameStream(event.gameId).first;

      if (game == null) {
        emit(const JudgingError(message: 'Game not found'));
        return;
      }

      if (event.taskIndex >= game.tasks.length) {
        emit(const JudgingError(message: 'Task not found'));
        return;
      }

      final task = game.tasks[event.taskIndex];

      // Build submission data from playerStatuses and players
      final submissions = <SubmissionData>[];
      for (final entry in task.playerStatuses.entries) {
        final playerId = entry.key;
        final status = entry.value;

        // Find player name
        final player = game.players.firstWhere(
          (p) => p.userId == playerId,
          orElse: () => throw Exception('Player not found: $playerId'),
        );

        submissions.add(SubmissionData(
          playerId: playerId,
          playerName: player.displayName,
          submissionUrl: status.submissionUrl,
          status: status,
        ));
      }

      emit(JudgingLoaded(
        gameId: event.gameId,
        taskIndex: event.taskIndex,
        taskTitle: task.title,
        taskDescription: task.description,
        submissions: submissions,
        currentIndex: 0,
        scores: {},
      ));
    } catch (e) {
      debugPrint('JudgingBloc.LoadSubmissions failed: $e');
      emit(JudgingError(
        message: FriendlyErrors.action(
          e,
          fallback: "Couldn't load the submissions. Please try again.",
        ),
      ));
    }
  }

  void _onScoreSubmission(
    ScoreSubmission event,
    Emitter<JudgingState> emit,
  ) {
    if (state is! JudgingLoaded) return;

    final currentState = state as JudgingLoaded;

    // Validate score range
    if (event.score < minScore || event.score > maxScore) {
      emit(JudgingError(
          message: 'Score must be between $minScore and $maxScore'));
      return;
    }

    // Update scores map
    final newScores = Map<String, int>.from(currentState.scores);
    newScores[event.playerId] = event.score;

    // Update submission data
    final updatedSubmissions = currentState.submissions.map((sub) {
      if (sub.playerId == event.playerId) {
        sub.score = event.score;
        sub.skipped = false;
      }
      return sub;
    }).toList();

    // Move to next unscored submission
    int nextIndex = currentState.currentIndex;
    for (int i = currentState.currentIndex + 1; i < updatedSubmissions.length; i++) {
      if (updatedSubmissions[i].score == null && !updatedSubmissions[i].skipped) {
        nextIndex = i;
        break;
      }
    }

    emit(currentState.copyWith(
      scores: newScores,
      submissions: updatedSubmissions,
      currentIndex: nextIndex,
    ));
  }

  void _onSkipSubmission(
    SkipSubmission event,
    Emitter<JudgingState> emit,
  ) {
    if (state is! JudgingLoaded) return;

    final currentState = state as JudgingLoaded;

    // Update submission data
    final updatedSubmissions = currentState.submissions.map((sub) {
      if (sub.playerId == event.playerId) {
        sub.skipped = true;
      }
      return sub;
    }).toList();

    // Move to next unscored submission
    int nextIndex = currentState.currentIndex;
    for (int i = currentState.currentIndex + 1; i < updatedSubmissions.length; i++) {
      if (updatedSubmissions[i].score == null && !updatedSubmissions[i].skipped) {
        nextIndex = i;
        break;
      }
    }

    emit(currentState.copyWith(
      submissions: updatedSubmissions,
      currentIndex: nextIndex,
    ));
  }

  Future<void> _onFinishJudging(
    FinishJudging event,
    Emitter<JudgingState> emit,
  ) async {
    if (state is! JudgingLoaded) return;

    final currentState = state as JudgingLoaded;

    if (!currentState.canFinish) {
      emit(const JudgingError(
          message: 'Must score at least one submission before finishing'));
      return;
    }

    emit(JudgingLoading());

    try {
      // Submit all scores to repository
      for (final entry in currentState.scores.entries) {
        final playerId = entry.key;
        final score = entry.value;

        await gameRepository.judgeSubmission(
          currentState.gameId,
          currentState.taskIndex,
          playerId,
          score,
        );
      }

      // Re-read the game now that every score has been written, and ship it
      // with the completion state. The scoreboard reveal is driven off THIS
      // snapshot rather than GameDetailBloc's, whose stream re-emits on its
      // own schedule: at this instant it may still hold the pre-judging game
      // (a reveal of all +0) or be between emissions entirely (the screen
      // used to silently pop back to the judging list).
      Game? updatedGame;
      try {
        updatedGame = await gameRepository
            .getGameStream(currentState.gameId)
            .first
            .timeout(const Duration(seconds: 5));
      } catch (e) {
        // Never fail a successful judging round over the reveal snapshot —
        // the scores are already saved. The UI falls back to whatever game
        // data it has.
        debugPrint('JudgingBloc.FinishJudging post-write re-read failed: $e');
      }

      emit(JudgingCompleted(
        gameId: currentState.gameId,
        taskIndex: currentState.taskIndex,
        game: updatedGame,
        awardedScores: Map<String, int>.unmodifiable(currentState.scores),
      ));
    } catch (e) {
      debugPrint('JudgingBloc.FinishJudging failed: $e');
      emit(JudgingError(
        message: FriendlyErrors.action(
          e,
          fallback: "Couldn't save the scores. Please try again.",
        ),
      ));
    }
  }
}