import '../../../../core/models/game.dart';
import '../../../../core/models/game_settings.dart';
import '../../../../core/models/submission.dart';
import '../../../../core/models/task.dart';
import '../../../../core/models/user.dart';

/// Why a join was refused, in words a player can act on.
class GameJoinException implements Exception {
  final String message;
  const GameJoinException(this.message);

  @override
  String toString() => message;
}

/// A peer grade the backend refused: almost always "you already graded that
/// one" (another device, a double tap) or "that entry's score just locked".
/// The grade queue treats it as done and moves on.
class PeerGradeRejected implements Exception {
  final Object cause;
  const PeerGradeRejected(this.cause);

  @override
  String toString() => 'PeerGradeRejected($cause)';
}

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

  /// Create a lobby game owned by [creatorId]. [judgingMode] defaults to
  /// [JudgingMode.judge] (one human judge, [judgeId]); with
  /// [JudgingMode.group] everyone grades everyone and nobody is the judge
  /// (`judgeId` is stored empty, whatever is passed).
  Future<String> createGame(String gameName, String creatorId, String judgeId,
      {JudgingMode judgingMode = JudgingMode.judge});

  /// Create [user]'s Starter Pack game: the ten hand-written solo tasks from
  /// `StarterPackData`, already in progress, crowd-judged, shared to the
  /// Arena, with [user] as the only player. Returns the new game id.
  ///
  /// Not idempotent on its own — `GamesBloc.StartStarterPack` is what reuses
  /// an existing `gameKind == 'starter'` game rather than making a second one.
  Future<String> createStarterGame(User user);

  /// [user]'s Daily Task game for the UTC day [dayKey] (`yyyyMMdd`): one
  /// task (`DailyTaskData.taskForDayKey`), already in progress, crowd-judged,
  /// shared to the Arena, with [user] as the only player. The doc id is
  /// deterministic (`daily_<uid>_<yyyyMMdd>`), so this is idempotent: a second
  /// call on the same day returns the same id and leaves the game untouched.
  Future<String> createOrGetDailyGame(User user, String dayKey);
  Future<void> updateGame(String gameId, Game game);
  Future<void> deleteGame(String gameId);
  Stream<Game?> getGameStream(String gameId);
  /// Add [userId] to the game carrying [inviteCode], atomically. A no-op
  /// for someone already in it. Throws [GameJoinException] when the game has
  /// started (Quick Play and Starter Pack games excepted) or is full.
  Future<String> joinGame(String inviteCode, String userId, String displayName);

  /// Remove [userId] from the game's player roster. Used when a non-creator
  /// leaves a game. No-op if the user is not a player.
  Future<void> leaveGame(String gameId, String userId);

  /// Move a lobby game to in-progress and seed every task's player statuses.
  /// A no-op unless the game is still in the lobby (so a double tap cannot
  /// re-seed statuses and wipe submissions).
  Future<void> startGame(String gameId);
  Future<void> addTasksToGame(String gameId, List<Task> tasks);
  Future<void> submitTaskAnswer(String gameId, String taskId, Submission submission);
  /// Score [playerId] on task [taskIndex]. Re-judging replaces the earlier
  /// score: totalScore moves by (new - old), never by +new again.
  Future<void> judgeSubmission(String gameId, int taskIndex, String playerId, int score);

  /// Atomically change ONE task of the freshest copy of the game: [mutate]
  /// receives that task as it is in the database right now and returns its
  /// replacement. Only the `tasks` field is written. This is how a player
  /// records their own start/submit/skip without erasing anyone else's.
  /// [mutate] must be pure — a contended transaction re-runs it.
  Future<void> updateTaskAtomically(
    String gameId,
    int taskIndex,
    Task Function(Task fresh) mutate,
  );

  /// Point the game at task [taskIndex]. Writes only `currentTaskIndex`, only
  /// when [callerId] is the judge or creator, and only forwards — so every
  /// viewer's scoreboard countdown firing at once is harmless.
  Future<void> advanceToTask(String gameId, int taskIndex,
      {required String callerId});

  /// Mark the game completed. Writes only `status`, only when [callerId] is
  /// the judge or creator.
  Future<void> completeGame(String gameId, {required String callerId});

  /// Record an AR task result for [playerId] and immediately self-judge it.
  ///
  /// AR mini-games (e.g. Balloon Pop) score themselves. When [playerId] is
  /// the judge or creator (solo / Quick Play), they jump straight to the
  /// `judged` state — bypassing the human judge UI. This
  /// performs the SAME scoreboard mutation as [judgeSubmission]: it stamps the
  /// player's status as judged with [score], synthesizes/stamps a matching
  /// Submission row, bumps the player's total score, advances the task to
  /// completed once all players are judged, and completes the game once all
  /// tasks are done. Anyone else may not write scores (firestore.rules), so
  /// their result is recorded as a `submitted` status carrying the AR score
  /// for the judge to confirm. [rawResult] (optional) is the raw gameplay metric (e.g.
  /// balloons popped) stored on the task for display/analytics.
  /// Group-graded games (WP-13): [graderUid] grades [targetUid]'s entry for
  /// task [taskIndex] with [score] (1..5). Writes ONE create-only grade doc;
  /// the server locks scores. Throws [PeerGradeRejected] when the grade was
  /// refused (already graded, entry already locked, not posted yet...).
  Future<void> submitPeerGrade({
    required String gameId,
    required int taskIndex,
    required String taskId,
    required String targetUid,
    required String graderUid,
    required int score,
  });

  Future<void> submitArResult(
    String gameId,
    int taskIndex,
    String playerId,
    int score, {
    int? rawResult,
  });
}