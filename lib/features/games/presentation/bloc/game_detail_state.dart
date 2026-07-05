part of 'game_detail_bloc.dart';

abstract class GameDetailState extends Equatable {
  const GameDetailState();
  
  @override
  List<Object> get props => [];
}

class GameDetailInitial extends GameDetailState {}

class GameDetailLoading extends GameDetailState {}

class GameDetailLoaded extends GameDetailState {
  final Game game;
  final bool shouldNavigateToResults;
  final int? targetTaskIndex;

  const GameDetailLoaded({
    required this.game,
    this.shouldNavigateToResults = false,
    this.targetTaskIndex,
  });

  @override
  List<Object> get props => [
    game,
    shouldNavigateToResults,
    if (targetTaskIndex != null) targetTaskIndex!,
  ];
}

/// A rematch game is being created — the UI shows a loading treatment.
class GameDetailRematchInProgress extends GameDetailState {}

/// The rematch lobby exists; the UI should navigate into [gameId].
class GameDetailRematchReady extends GameDetailState {
  final String gameId;

  const GameDetailRematchReady({required this.gameId});

  @override
  List<Object> get props => [gameId];
}

class GameDetailError extends GameDetailState {
  final String message;

  const GameDetailError({required this.message});

  @override
  List<Object> get props => [message];
}