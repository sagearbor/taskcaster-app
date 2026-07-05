import 'dart:async';

import '../../../../core/models/game.dart';
import '../../../games/domain/repositories/game_repository.dart';
import '../../domain/models/invite.dart';
import '../../domain/repositories/invites_repository.dart';

/// In-memory invites for mock/offline mode and widget tests. Accepting joins
/// through the injected [GameRepository], exactly like the Firestore impl.
class MockInvitesRepository implements InvitesRepository {
  MockInvitesRepository({
    required GameRepository gameRepository,
    String currentUserId = 'mock_user',
    String currentUserName = 'Mock User',
    String? currentUserEmail,
  })  : _gameRepository = gameRepository,
        _uid = currentUserId,
        _name = currentUserName,
        _email = currentUserEmail?.toLowerCase();

  final GameRepository _gameRepository;
  final String _uid;
  final String _name;
  final String? _email;

  int _seq = 0;
  final List<Invite> _invites = [];
  final StreamController<List<Invite>> _controller =
      StreamController<List<Invite>>.broadcast();

  List<Invite> _myPending() {
    final list = _invites
        .where((i) => i.recipientUid == _uid && i.status == InviteStatus.pending)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  void _emit() => _controller.add(_myPending());

  Invite _make(Game game, {String? recipientUid, String? emailLower}) {
    return Invite(
      id: 'invite_${_seq++}',
      gameId: game.id,
      gameName: game.gameName,
      inviteCode: game.inviteCode,
      inviterUid: _uid,
      inviterName: _name,
      recipientUid: recipientUid,
      recipientEmailLower: emailLower,
      status: InviteStatus.pending,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<void> sendToFriend(String friendUid, Game game) async {
    _invites.add(_make(game, recipientUid: friendUid));
    _emit();
  }

  @override
  Future<void> sendToEmail(String email, Game game) async {
    final lower = email.trim().toLowerCase();
    if (lower.isEmpty) return;
    _invites.add(_make(game, emailLower: lower));
    _emit();
  }

  @override
  Stream<List<Invite>> watchMyInvites() async* {
    yield _myPending();
    yield* _controller.stream;
  }

  @override
  Future<String> accept(Invite invite) async {
    final gameId =
        await _gameRepository.joinGame(invite.inviteCode, _uid, _name);
    final idx = _invites.indexWhere((i) => i.id == invite.id);
    if (idx != -1) {
      _invites[idx] = _invites[idx].copyWith(status: InviteStatus.accepted);
      _emit();
    }
    return gameId;
  }

  @override
  Future<void> decline(Invite invite) async {
    final idx = _invites.indexWhere((i) => i.id == invite.id);
    if (idx != -1) {
      _invites[idx] = _invites[idx].copyWith(status: InviteStatus.declined);
      _emit();
    }
  }

  @override
  Future<void> claimEmailInvites() async {
    final email = _email;
    if (email == null || email.isEmpty) return;
    var changed = false;
    for (var i = 0; i < _invites.length; i++) {
      final inv = _invites[i];
      if (inv.recipientUid == null && inv.recipientEmailLower == email) {
        _invites[i] = inv.copyWith(recipientUid: _uid);
        changed = true;
      }
    }
    if (changed) _emit();
  }

  void dispose() => _controller.close();
}
