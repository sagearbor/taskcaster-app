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

/// Open (or create) the current user's Starter Pack game — "Your First Ten".
///
/// Idempotent: a user only ever has one starter game. Emits
/// [StarterPackReady] with the game id and the task they should be on.
///
/// [taskId] (WP-09 share links) opens THAT task instead of the next
/// unsubmitted one, when the starter game has it (an older starter game may
/// carry pre-v2 ids; it then falls back to the usual next task).
class StartStarterPack extends GamesEvent {
  final String? taskId;

  const StartStarterPack({this.taskId});

  @override
  List<Object> get props => [taskId ?? ''];
}

/// "Challenge friends": create a friend game (lobby, creator judges) seeded
/// with a 5-task pack, then emit [ChallengeFriendsReady] so the home screen
/// can land the creator on the share-invite step.
class ChallengeFriends extends GamesEvent {
  const ChallengeFriends();
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