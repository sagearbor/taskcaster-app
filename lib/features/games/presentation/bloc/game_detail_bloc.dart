import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/models/game.dart';
import '../../../../core/models/submission.dart';
import '../../../../core/utils/friendly_errors.dart';
import '../../../arena/domain/crowd_score_applier.dart';
import '../../../friends/domain/repositories/friends_repository.dart';
import '../../domain/repositories/game_repository.dart';
import '../../../../core/models/player_task_status.dart';

part 'game_detail_event.dart';
part 'game_detail_state.dart';

class GameDetailBloc extends Bloc<GameDetailEvent, GameDetailState> {
  final GameRepository gameRepository;

  /// Optional friend graph. When present, co-players of a game the user is
  /// actually playing are silently upserted into their friends. Nullable so
  /// existing bloc tests can construct without it.
  final FriendsRepository? friendsRepository;

  /// Carries settled crowd grades into the scoreboard when the owner of a
  /// crowd-judged game opens it. Nullable so existing bloc tests construct
  /// unchanged; [currentUserId] gates it to the game's own owner, since only
  /// they are allowed to write its scores.
  final CrowdScoreApplier? crowdScoreApplier;
  final String? currentUserId;

  String? _currentGameId;

  /// Which tasks were last seen waiting on a crowd score. applyPending only
  /// re-runs when that set changes, so the write it performs (which re-emits
  /// the game stream) can't drive a loop.
  String? _lastCrowdSignature;
  bool _crowdApplyInFlight = false;

  /// The last co-player roster we synced to the friend graph (sorted uids
  /// joined), so identical snapshots don't trigger redundant writes.
  String? _lastFriendSyncSignature;

  String? get gameId => _currentGameId;

  GameDetailBloc({
    required this.gameRepository,
    this.friendsRepository,
    this.crowdScoreApplier,
    this.currentUserId,
  }) : super(GameDetailInitial()) {
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
    _lastCrowdSignature = null;
    emit(GameDetailLoading());

    // emit.forEach keeps the emitter valid for the whole life of the stream,
    // instead of .listen() emitting after the handler returns (which throws
    // "emit was called after an event handler completed normally").
    await emit.forEach<Game?>(
      gameRepository.getGameStream(event.gameId),
      onData: (game) {
        if (game != null) {
          _maybeSyncFriends(game);
          _maybeApplyCrowdScores(game);
          return GameDetailLoaded(game: game);
        }
        return const GameDetailError(message: 'Game not found');
      },
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

  /// Silently upsert co-players into the friend graph once the crew is actually
  /// playing together (in-progress or completed, 2+ players). Runs on game
  /// load and completion (both flow through the game stream). Deduped by roster
  /// so identical snapshots don't re-write. Fire-and-forget; never blocks the
  /// UI or surfaces errors.
  void _maybeSyncFriends(Game game) {
    final repo = friendsRepository;
    if (repo == null) return;
    final playing =
        game.status == GameStatus.inProgress || game.status == GameStatus.completed;
    if (!playing || game.players.length < 2) return;

    final signature = (game.playerIds.toList()..sort()).join(',');
    if (signature == _lastFriendSyncSignature) return;
    _lastFriendSyncSignature = signature;

    // ignore: discarded_futures
    repo.addFriendsFromGame(game).catchError((Object e) {
      debugPrint('GameDetailBloc friend sync failed: $e');
    });
  }

  /// Pull in any crowd scores that have settled since last time.
  ///
  /// Only for the owner of a crowd-judged game, only when at least one task is
  /// actually waiting (submitted, not judged, with an Arena post), and only
  /// once per distinct set of waiting tasks. Best-effort throughout: a failure
  /// here must never stop the game screen from rendering.
  void _maybeApplyCrowdScores(Game game) {
    final applier = crowdScoreApplier;
    final viewer = currentUserId;
    if (applier == null || viewer == null) return;
    if (!game.settings.crowdJudged || game.creatorId != viewer) return;
    if (_crowdApplyInFlight) return;

    final pending = <String>[];
    for (var i = 0; i < game.tasks.length; i++) {
      final task = game.tasks[i];
      final status = task.getPlayerStatus(game.creatorId);
      if (status == null || status.state != TaskPlayerState.submitted) continue;
      final hasPost = task.submissions
          .any((s) => s.userId == game.creatorId && s.feedPostId != null);
      if (hasPost) pending.add('$i');
    }
    if (pending.isEmpty) {
      _lastCrowdSignature = '';
      return;
    }

    final signature = pending.join(',');
    if (signature == _lastCrowdSignature) return;
    _lastCrowdSignature = signature;
    _crowdApplyInFlight = true;

    try {
      // ignore: discarded_futures
      applier.applyPending(game).catchError((Object e) {
        debugPrint('GameDetailBloc crowd score apply failed: $e');
        return 0;
      }).whenComplete(() {
        _crowdApplyInFlight = false;
      });
    } catch (e) {
      // A synchronous throw is just as survivable as a rejected future.
      debugPrint('GameDetailBloc crowd score apply failed: $e');
      _crowdApplyInFlight = false;
    }
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