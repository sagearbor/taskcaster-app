part of 'games_bloc.dart';

abstract class GamesEvent extends Equatable {
  const GamesEvent();

  @override
  List<Object> get props => [];
}

class LoadGames extends GamesEvent {}

class CreateGame extends GamesEvent {
  final String gameName;
  final String creatorId;
  final String judgeId;

  const CreateGame({
    required this.gameName,
    required this.creatorId,
    required this.judgeId,
  });

  @override
  List<Object> get props => [gameName, creatorId, judgeId];
}

class JoinGame extends GamesEvent {
  final String inviteCode;
  final String userId;
  final String displayName;

  const JoinGame({
    required this.inviteCode,
    required this.userId,
    required this.displayName,
  });

  @override
  List<Object> get props => [inviteCode, userId, displayName];
}

class DeleteGame extends GamesEvent {
  final String gameId;

  const DeleteGame({required this.gameId});

  @override
  List<Object> get props => [gameId];
}

class QuickPlayGame extends GamesEvent {
  /// When set, seed the solo game with a single AR mini-game task (e.g.
  /// [ArGameIds.balloonPop] or [ArGameIds.treasureHunt]) instead of 5 random
  /// video tasks.
  final String? arGameId;
  const QuickPlayGame({this.arGameId});

  @override
  List<Object> get props => [arGameId ?? ''];
}