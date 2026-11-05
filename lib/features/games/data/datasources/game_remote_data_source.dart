/// Builds the fields to write for one atomic game update.
///
/// Receives the FRESHEST copy of the game document (with its `id`), read
/// inside the transaction. Returns only the top-level fields to change, or
/// null (or an empty map) to write nothing. May throw to abort the update.
///
/// Must be pure: a contended transaction re-runs it with newer data.
typedef GameMutation = Map<String, dynamic>? Function(
    Map<String, dynamic> current);

abstract class GameRemoteDataSource {
  /// The signed-in user's games (those whose `playerIds` contains them),
  /// newest first.
  Stream<List<Map<String, dynamic>>> getGamesStream();
  Stream<List<Map<String, dynamic>>> getPublicGamesStream();

  /// Games whose `invitedEmails` array contains [email] (already lowercased by
  /// the caller). Implementations only need to apply the array-contains filter;
  /// the repository narrows to lobby games and sorts newest-first.
  Stream<List<Map<String, dynamic>>> getInvitedGamesStream(String email);

  Future<String> createGame(Map<String, dynamic> gameData);
  Future<void> updateGame(String gameId, Map<String, dynamic> updates);
  Future<void> deleteGame(String gameId);
  Stream<Map<String, dynamic>?> getGameStream(String gameId);

  /// The id of the game carrying [inviteCode], or null when none does.
  Future<String?> findGameIdByInviteCode(String inviteCode);

  /// Read-modify-write [gameId] atomically: re-read the document, hand it to
  /// [mutate], and `update` only the fields it returns. Concurrent writers
  /// never erase each other's changes. Throws if the game does not exist.
  Future<void> transactGame(String gameId, GameMutation mutate);

  /// Create `games/{gameId}/peer_grades/{gradeId}` (WP-13) with [data] plus a
  /// server-timestamp `createdAt`. Create-only: firestore.rules refuse a
  /// second grade with the same id (and any grade that is not the caller's
  /// own to give) with permission-denied.
  Future<void> createPeerGrade(
      String gameId, String gradeId, Map<String, dynamic> data);
}
