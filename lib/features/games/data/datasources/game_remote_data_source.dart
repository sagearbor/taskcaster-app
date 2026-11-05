abstract class GameRemoteDataSource {
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
  Future<String> joinGame(String inviteCode, String userId);
}