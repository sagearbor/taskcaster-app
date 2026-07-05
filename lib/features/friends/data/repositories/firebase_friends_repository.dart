import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../../core/models/game.dart';
import '../../domain/models/friend.dart';
import '../../domain/repositories/friends_repository.dart';

/// Firestore-backed friend graph. Friends live in the current user's own
/// `users/{myUid}/friends` subcollection (self-write only), keyed by the
/// friend's uid.
class FirebaseFriendsRepository implements FriendsRepository {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  FirebaseFriendsRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>>? _friendsCol() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    return _firestore.collection('users').doc(uid).collection('friends');
  }

  @override
  Stream<List<Friend>> watchFriends() {
    final col = _friendsCol();
    if (col == null) return Stream.value(const []);
    return col.snapshots().map((snapshot) {
      final friends =
          snapshot.docs.map((d) => Friend.fromMap(d.id, d.data())).toList();
      // Newest "last played" first; friends without a timestamp sink to the end.
      friends.sort((a, b) {
        final at = a.lastPlayedAt;
        final bt = b.lastPlayedAt;
        if (at == null && bt == null) return 0;
        if (at == null) return 1;
        if (bt == null) return -1;
        return bt.compareTo(at);
      });
      return friends;
    });
  }

  @override
  Future<void> addFriendsFromGame(Game game) async {
    final uid = _auth.currentUser?.uid;
    final col = _friendsCol();
    if (uid == null || col == null) return;

    // Everyone on the roster except me.
    final coPlayers = game.players.where((p) => p.userId != uid).toList();
    if (coPlayers.isEmpty) return;

    final now = DateTime.now().toIso8601String();
    final batch = _firestore.batch();
    for (final player in coPlayers) {
      batch.set(
        col.doc(player.userId),
        {
          'displayName': player.displayName,
          'lastPlayedAt': now,
        },
        // Merge so we never clobber an avatarEmoji already stored for them.
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  @override
  Future<void> removeFriend(String uid) async {
    final col = _friendsCol();
    if (col == null) return;
    await col.doc(uid).delete();
  }
}
