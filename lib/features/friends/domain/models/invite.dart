import 'package:equatable/equatable.dart';

/// Where an invite currently stands.
enum InviteStatus { pending, accepted, declined }

/// A one-tap game invite living in the top-level `invites/{id}` collection.
///
/// Two flavours:
/// - Friend invite: [recipientUid] is set to a known friend's uid.
/// - Email invite: [recipientUid] is null and [recipientEmailLower] holds the
///   lowercased target address. When that person signs in, `claimEmailInvites`
///   stamps [recipientUid] so the invite appears in their inbox.
class Invite extends Equatable {
  final String id;
  final String gameId;
  final String gameName;

  /// The game's 6-char invite code — accepting joins via this code, so nothing
  /// server-side is required.
  final String inviteCode;

  final String inviterUid;
  final String inviterName;

  /// Set for friend invites (and stamped onto email invites once claimed).
  final String? recipientUid;

  /// Lowercased target email for email invites; null for friend invites.
  final String? recipientEmailLower;

  final InviteStatus status;
  final DateTime createdAt;

  const Invite({
    required this.id,
    required this.gameId,
    required this.gameName,
    required this.inviteCode,
    required this.inviterUid,
    required this.inviterName,
    this.recipientUid,
    this.recipientEmailLower,
    this.status = InviteStatus.pending,
    required this.createdAt,
  });

  factory Invite.fromMap(String id, Map<String, dynamic> map) {
    final rawCreated = map['createdAt'];
    return Invite(
      id: id,
      gameId: map['gameId'] as String? ?? '',
      gameName: map['gameName'] as String? ?? 'a game',
      inviteCode: map['inviteCode'] as String? ?? '',
      inviterUid: map['inviterUid'] as String? ?? '',
      inviterName: (map['inviterName'] as String?)?.trim().isNotEmpty == true
          ? map['inviterName'] as String
          : 'A friend',
      recipientUid: map['recipientUid'] as String?,
      recipientEmailLower:
          (map['recipientEmailLower'] as String?)?.toLowerCase(),
      status: InviteStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => InviteStatus.pending,
      ),
      createdAt: rawCreated is String
          ? (DateTime.tryParse(rawCreated) ?? DateTime.now())
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'gameId': gameId,
      'gameName': gameName,
      'inviteCode': inviteCode,
      'inviterUid': inviterUid,
      'inviterName': inviterName,
      'recipientUid': recipientUid,
      'recipientEmailLower': recipientEmailLower,
      'status': status.name,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  Invite copyWith({
    String? recipientUid,
    InviteStatus? status,
  }) {
    return Invite(
      id: id,
      gameId: gameId,
      gameName: gameName,
      inviteCode: inviteCode,
      inviterUid: inviterUid,
      inviterName: inviterName,
      recipientUid: recipientUid ?? this.recipientUid,
      recipientEmailLower: recipientEmailLower,
      status: status ?? this.status,
      createdAt: createdAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        gameId,
        gameName,
        inviteCode,
        inviterUid,
        inviterName,
        recipientUid,
        recipientEmailLower,
        status,
        createdAt,
      ];
}
