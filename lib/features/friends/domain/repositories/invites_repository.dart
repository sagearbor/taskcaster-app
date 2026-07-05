import '../../../../core/models/game.dart';
import '../models/invite.dart';

/// One-tap game invites (top-level `invites/{id}` collection). No server is
/// involved: accepting simply joins the game via its invite code. Delivery of a
/// push notification is a later, additive concern.
abstract class InvitesRepository {
  /// Invite a known friend (by uid) to [game].
  Future<void> sendToFriend(String friendUid, Game game);

  /// Invite someone by email to [game]. The recipient is resolved to a uid the
  /// next time they sign in (see [claimEmailInvites]).
  Future<void> sendToEmail(String email, Game game);

  /// Pending invites addressed to the current user, newest first.
  Stream<List<Invite>> watchMyInvites();

  /// Join the invited game (via its invite code) and stamp the invite accepted.
  /// Returns the joined game id so the caller can navigate into it.
  Future<String> accept(Invite invite);

  /// Politely dismiss an invite.
  Future<void> decline(Invite invite);

  /// On sign-in: find email invites addressed to the current user's email that
  /// have no recipientUid yet and stamp it, so they surface in the inbox.
  Future<void> claimEmailInvites();
}
