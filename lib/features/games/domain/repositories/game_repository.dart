import '../../../../core/models/game.dart';
import '../../../../core/models/submission.dart';
import '../../../../core/models/task.dart';

abstract class GameRepository {
  Stream<List<Game>> getGamesStream();

  /// Games marked public — the discoverable community gallery.
  Stream<List<Game>> getPublicGamesStream();

  /// Lobby games the user with [email] has been specifically invited to, newest
  /// invited first. [email] is lowercased internally so callers needn't.
  Stream<List<Game>> getInvitedGamesStream(String email);

  /// Create a few ready-made public template games owned by [ownerId] so the
  /// gallery has real content to discover. Used to bootstrap an empty gallery.
  Future<void> seedStarterPublicGames(String ownerId, String displayName);

  /// Create a new private game owned by [creatorId] that copies [template]'s
  /// tasks (as fresh, unsubmitted tasks). Returns the new game id.
  Future<String> cloneGame(Game template, String creatorId, String displayName);

  /// Rematch: spin up a brand-new lobby game from a finished [source] game —
  /// same crew (every player carried over with scores reset to 0), same judge,
  /// same creator and the same NUMBER of tasks, but the tasks themselves are
  /// drawn freshly-shuffled from the prebuilt catalog so the rematch isn't a
  /// re-run of challenges everyone has already seen. Returns the new game id.
  Future<String> rematchGame(Game source);

  Future<String> createGame(String gameName, String creatorId, String judgeId);
  Future<void> updateGame(String gameId, Game game);
  Future<void> deleteGame(String gameId);
  Stream<Game?> getGameStream(String gameId);
  Future<String> joinGame(String inviteCode, String userId, String displayName);

  /// Remove [userId] from the game's player roster. Used when a non-creator
  /// leaves a game. No-op if the user is not a player.
  Future<void> leaveGame(String gameId, String userId);

  Future<void> startGame(String gameId);
  Future<void> addTasksToGame(String gameId, List<Task> tasks);
  Future<void> submitTaskAnswer(String gameId, String taskId, Submission submission);
  Future<void> judgeSubmission(String gameId, int taskIndex, String playerId, int score);

  /// Record an AR task result for [playerId] and immediately self-judge it.
  ///
  /// AR mini-games (e.g. Balloon Pop) score themselves, so the player jumps
  /// straight to the `judged` state — bypassing the human judge UI. This
  /// performs the SAME scoreboard mutation as [judgeSubmission]: it stamps the
  /// player's status as judged with [score], synthesizes/stamps a matching
  /// Submission row, bumps the player's total score, advances the task to
  /// completed once all players are judged, and completes the game once all
  /// tasks are done. [rawResult] (optional) is the raw gameplay metric (e.g.
  /// balloons popped) stored on the task for display/analytics.
  Future<void> submitArResult(
    String gameId,
    int taskIndex,
    String playerId,
    int score, {
    int? rawResult,
  });
}