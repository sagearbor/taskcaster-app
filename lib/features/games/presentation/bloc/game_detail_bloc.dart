import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/models/game.dart';
import '../../../../core/models/submission.dart';
import '../../../../core/utils/friendly_errors.dart';
import '../../domain/repositories/game_repository.dart';

part 'game_detail_event.dart';
part 'game_detail_state.dart';

class GameDetailBloc extends Bloc<GameDetailEvent, GameDetailState> {
  final GameRepository gameRepository;
  String? _currentGameId;

  String? get gameId => _currentGameId;

  GameDetailBloc({required this.gameRepository}) : super(GameDetailInitial()) {
    on<LoadGameDetail>(_onLoadGameDetail);
    on<StartGame>(_onStartGame);
    on<SubmitTaskAnswer>(_onSubmitTaskAnswer);
    on<JudgeSubmission>(_onJudgeSubmission);
    on<RematchGame>(_onRematchGame);
    on<ViewTaskResultsEvent>(_onViewTaskResults);
    on<CompleteGameEvent>(_onCompleteGame);
    on<AdvanceToNextTaskEvent>(_onAdvanceToNextTask);
  }

  Future<void> _onLoadGameDetail(
      LoadGameDetail event, Emitter<GameDetailState> emit) async {
    _currentGameId = event.gameId;
    emit(GameDetailLoading());

    // emit.forEach keeps the emitter valid for the whole life of the stream,
    // instead of .listen() emitting after the handler returns (which throws
    // "emit was called after an event handler completed normally").
    await emit.forEach<Game?>(
      gameRepository.getGameStream(event.gameId),
      onData: (game) => game != null
          ? GameDetailLoaded(game: game)
          : const GameDetailError(message: 'Game not found'),
      onError: (error, _) {
        debugPrint('GameDetailBloc.LoadGameDetail stream error: $error');
        return GameDetailError(
          message: FriendlyErrors.action(
            error,
            fallback: "Couldn't load the game. Please try again.",
          ),
        );
      },
    );
  }

  Future<void> _onStartGame(StartGame event, Emitter<GameDetailState> emit) async {
    try {
      await gameRepository.startGame(event.gameId);
    } catch (e) {
      debugPrint('GameDetailBloc.StartGame failed: $e');
      emit(GameDetailError(
        message: FriendlyErrors.action(
          e,
          fallback: "Couldn't start the game. Please try again.",
        ),
      ));
    }
  }

  Future<void> _onSubmitTaskAnswer(SubmitTaskAnswer event, Emitter<GameDetailState> emit) async {
    try {
      await gameRepository.submitTaskAnswer(
        event.gameId,
        event.taskId,
        event.submission,
      );
    } catch (e) {
      debugPrint('GameDetailBloc.SubmitTaskAnswer failed: $e');
      emit(GameDetailError(
        message: FriendlyErrors.action(
          e,
          fallback: "Couldn't submit your answer. Please try again.",
        ),
      ));
    }
  }

  Future<void> _onJudgeSubmission(JudgeSubmission event, Emitter<GameDetailState> emit) async {
    try {
      await gameRepository.judgeSubmission(
        event.gameId,
        event.taskIndex,
        event.playerId,
        event.score,
      );
    } catch (e) {
      debugPrint('GameDetailBloc.JudgeSubmission failed: $e');
      emit(GameDetailError(
        message: FriendlyErrors.action(
          e,
          fallback: "Couldn't save that score. Please try again.",
        ),
      ));
    }
  }

  Future<void> _onRematchGame(
      RematchGame event, Emitter<GameDetailState> emit) async {
    // Ignore double-taps while a rematch is already being created.
    if (state is GameDetailRematchInProgress) return;
    emit(GameDetailRematchInProgress());
    try {
      final newGameId = await gameRepository.rematchGame(event.game);
      emit(GameDetailRematchReady(gameId: newGameId));
    } catch (e) {
      emit(GameDetailError(message: e.toString()));
    }
  }

  Future<void> _onViewTaskResults(ViewTaskResultsEvent event, Emitter<GameDetailState> emit) async {
    // Navigation to task results screen will be handled in the UI layer
    // This event serves as a trigger for navigation
    if (state is GameDetailLoaded) {
      final currentState = state as GameDetailLoaded;
      emit(GameDetailLoaded(
        game: currentState.game,
        shouldNavigateToResults: true,
        targetTaskIndex: event.taskIndex,
      ));
    }
  }

  Future<void> _onCompleteGame(CompleteGameEvent event, Emitter<GameDetailState> emit) async {
    try {
      // Update game status to completed by getting game from current state
      if (state is GameDetailLoaded) {
        final currentState = state as GameDetailLoaded;
        final updatedGame = currentState.game.copyWith(status: GameStatus.completed);
        await gameRepository.updateGame(event.gameId, updatedGame);
      }
    } catch (e) {
      debugPrint('GameDetailBloc.CompleteGame failed: $e');
      emit(GameDetailError(
        message: FriendlyErrors.action(
          e,
          fallback: "Couldn't complete the game. Please try again.",
        ),
      ));
    }
  }

  Future<void> _onAdvanceToNextTask(AdvanceToNextTaskEvent event, Emitter<GameDetailState> emit) async {
    try {
      // Update currentTaskIndex by getting game from current state
      if (state is GameDetailLoaded) {
        final currentState = state as GameDetailLoaded;
        final updatedGame = currentState.game.copyWith(currentTaskIndex: event.nextTaskIndex);
        await gameRepository.updateGame(event.gameId, updatedGame);
      }
    } catch (e) {
      debugPrint('GameDetailBloc.AdvanceToNextTask failed: $e');
      emit(GameDetailError(
        message: FriendlyErrors.action(
          e,
          fallback: "Couldn't move to the next task. Please try again.",
        ),
      ));
    }
  }
}