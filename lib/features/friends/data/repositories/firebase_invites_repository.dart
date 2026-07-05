import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../../core/models/game.dart';
import '../../../games/domain/repositories/game_repository.dart';
import '../../domain/models/invite.dart';
import '../../domain/repositories/invites_repository.dart';

/// Firestore-backed one-tap invites. Accepting joins the game through the
/// existing [GameRepository.joinGame] (invite-code) path, so no server-side
/// code is needed on the free plan.
class FirebaseInvitesRepository implements InvitesRepository {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final GameRepository _gameRepository;

  FirebaseInvitesRepository({
    required GameRepository gameRepository,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _gameRepository = gameRepository,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _invites =>
      _firestore.collection('invites');

  String? get _uid => _auth.currentUser?.uid;

  String get _inviterName {
    final user = _auth.currentUser;
    final name = user?.displayName;
    if (name != null && name.trim().isNotEmpty) return name.trim();
    final email = user?.email;
    if (email != null && email.contains('@')) return email.split('@').first;
    return 'A friend';
  }

  Invite _newInvite(Game game, {String? recipientUid, String? emailLower}) {
    final uid = _uid ?? '';
    return Invite(
      id: '', // assigned by Firestore
      gameId: game.id,
      gameName: game.gameName,
      inviteCode: game.inviteCode,
      inviterUid: uid,
      inviterName: _inviterName,
      recipientUid: recipientUid,
      recipientEmailLower: emailLower,
      status: InviteStatus.pending,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<void> sendToFriend(String friendUid, Game game) async {
    if (_uid == null) return;
    await _invites.add(_newInvite(game, recipientUid: friendUid).toMap());
  }

  @override
  Future<void> sendToEmail(String email, Game game) async {
    if (_uid == null) return;
    final lower = email.trim().toLowerCase();
    if (lower.isEmpty) return;
    await _invites.add(_newInvite(game, emailLower: lower).toMap());
  }

  @override
  Stream<List<Invite>> watchMyInvites() {
    final uid = _uid;
    if (uid == null) return Stream.value(const []);
    // Single-field equality filter (auto-indexed). Status filtering + newest-
    // first sorting happen client-side to avoid a composite index, matching the
    // pattern used elsewhere in the app.
    return _invites
        .where('recipientUid', isEqualTo: uid)
        .snapshots()
        .map((snapshot) {
      final invites = snapshot.docs
          .map((d) => Invite.fromMap(d.id, d.data()))
          .where((i) => i.status == InviteStatus.pending)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return invites;
    });
  }

  @override
  Future<String> accept(Invite invite) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('Must be signed in to accept an invite');
    }
    final displayName = (user.displayName?.trim().isNotEmpty ?? false)
        ? user.displayName!.trim()
        : (user.email?.split('@').first ?? 'Guest');

    // Join through the existing invite-code path.
    final gameId =
        await _gameRepository.joinGame(invite.inviteCode, user.uid, displayName);

    // Stamp the invite accepted (best-effort; the join already succeeded).
    if (invite.id.isNotEmpty) {
      await _invites.doc(invite.id).update({'status': InviteStatus.accepted.name});
    }
    return gameId;
  }

  @override
  Future<void> decline(Invite invite) async {
    if (invite.id.isEmpty) return;
    await _invites.doc(invite.id).update({'status': InviteStatus.declined.name});
  }

  @override
  Future<void> claimEmailInvites() async {
    final user = _auth.currentUser;
    final email = user?.email?.toLowerCase();
    if (user == null || email == null || email.isEmpty) return;

    // Single equality filter; the recipientUid == null narrowing is client-side
    // (avoids a composite index).
    final snapshot =
        await _invites.where('recipientEmailLower', isEqualTo: email).get();
    for (final doc in snapshot.docs) {
      if (doc.data()['recipientUid'] == null) {
        await doc.reference.update({'recipientUid': user.uid});
      }
    }
  }
}
