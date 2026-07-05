import 'dart:async';

import '../../../../core/models/game.dart';
import '../../domain/models/friend.dart';
import '../../domain/repositories/friends_repository.dart';

/// In-memory friend graph for mock/offline mode and widget tests. Mirrors the
/// self-write semantics of the Firestore implementation (there is one "current
/// user" whose friends we track).
class MockFriendsRepository implements FriendsRepository {
  MockFriendsRepository({String currentUserId = 'mock_user'})
      : _currentUserId = currentUserId;

  final String _currentUserId;
  final Map<String, Friend> _friends = {};
  final StreamController<List<Friend>> _controller =
      StreamController<List<Friend>>.broadcast();

  void _emit() => _controller.add(_sorted());

  List<Friend> _sorted() {
    final list = _friends.values.toList();
    list.sort((a, b) {
      final at = a.lastPlayedAt;
      final bt = b.lastPlayedAt;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
    return list;
  }

  @override
  Stream<List<Friend>> watchFriends() async* {
    yield _sorted();
    yield* _controller.stream;
  }

  @override
  Future<void> addFriendsFromGame(Game game) async {
    final coPlayers =
        game.players.where((p) => p.userId != _currentUserId).toList();
    if (coPlayers.isEmpty) return;
    final now = DateTime.now();
    for (final player in coPlayers) {
      final existing = _friends[player.userId];
      _friends[player.userId] = Friend(
        uid: player.userId,
        displayName: player.displayName,
        avatarEmoji: existing?.avatarEmoji,
        lastPlayedAt: now,
      );
    }
    _emit();
  }

  @override
  Future<void> removeFriend(String uid) async {
    _friends.remove(uid);
    _emit();
  }

  void dispose() => _controller.close();
}
