part of 'games_bloc.dart';

abstract class GamesState extends Equatable {
  const GamesState();
  
  @override
  List<Object> get props => [];
}

class GamesInitial extends GamesState {}

class GamesLoading extends GamesState {}

class GamesLoaded extends GamesState {
  final List<Game> games;

  const GamesLoaded({required this.games});

  @override
  List<Object> get props => [games];
}

class GamesError extends GamesState {
  final String message;

  const GamesError({required this.message});

  @override
  List<Object> get props => [message];
}

class QuickPlaySuccess extends GamesState {
  final String gameId;

  const QuickPlaySuccess({required this.gameId});

  @override
  List<Object> get props => [gameId];
}

/// The Starter Pack game is ready to play.
///
/// [taskIndex] is the first task the user has NOT submitted, or the last task
/// when they have finished all ten — i.e. exactly the task to open.
class StarterPackReady extends GamesState {
  final String gameId;
  final int taskIndex;

  const StarterPackReady({required this.gameId, required this.taskIndex});

  @override
  List<Object> get props => [gameId, taskIndex];
}

/// Today's Daily Task game is ready: open its only task (index 0).
class DailyTaskReady extends GamesState {
  final String gameId;

  const DailyTaskReady({required this.gameId});

  @override
  List<Object> get props => [gameId];
}

/// A "Challenge friends" game was created and is waiting in its lobby; the
/// listener opens it with the invite dialog up.
class ChallengeFriendsReady extends GamesState {
  final String gameId;

  const ChallengeFriendsReady({required this.gameId});

  @override
  List<Object> get props => [gameId];
}
