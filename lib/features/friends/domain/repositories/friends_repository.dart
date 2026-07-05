import '../../../../core/models/game.dart';
import '../models/friend.dart';

/// The friend graph: people the current user has played with. Every write is to
/// the user's OWN `users/{myUid}/friends` subcollection — there is no way (and
/// no need) to write to someone else's friend list. The reciprocal edge is
/// created independently when the other person plays the same game.
abstract class FriendsRepository {
  /// The current user's friends, newest "last played" first.
  Stream<List<Friend>> watchFriends();

  /// Upsert every OTHER player in [game] into the current user's friends,
  /// stamping [lastPlayedAt]. Idempotent — safe to call on every game load.
  /// No-op when there is no signed-in user or no co-players.
  Future<void> addFriendsFromGame(Game game);

  /// Remove [uid] from the current user's friends.
  Future<void> removeFriend(String uid);
}
