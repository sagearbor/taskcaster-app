import 'package:equatable/equatable.dart';

/// A person the current user has played with. Stored, self-write only, at
/// `users/{myUid}/friends/{friendUid}` — the document id IS the friend's uid.
class Friend extends Equatable {
  /// The friend's Firebase Auth uid (also the Firestore document id).
  final String uid;
  final String displayName;

  /// The friend's chosen avatar emoji, when known (co-players don't always
  /// carry one — falls back to a name initial in the UI).
  final String? avatarEmoji;

  /// When we last shared a game with this friend. Drives the "last played"
  /// line and newest-first ordering on the friends screen.
  final DateTime? lastPlayedAt;

  const Friend({
    required this.uid,
    required this.displayName,
    this.avatarEmoji,
    this.lastPlayedAt,
  });

  factory Friend.fromMap(String uid, Map<String, dynamic> map) {
    final rawLastPlayed = map['lastPlayedAt'];
    return Friend(
      uid: uid,
      displayName: (map['displayName'] as String?)?.trim().isNotEmpty == true
          ? map['displayName'] as String
          : 'Friend',
      avatarEmoji: map['avatarEmoji'] as String?,
      lastPlayedAt:
          rawLastPlayed is String ? DateTime.tryParse(rawLastPlayed) : null,
    );
  }

  /// The stored fields (the uid lives in the document id, not the body).
  Map<String, dynamic> toMap() {
    return {
      'displayName': displayName,
      'avatarEmoji': avatarEmoji,
      'lastPlayedAt': lastPlayedAt?.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [uid, displayName, avatarEmoji, lastPlayedAt];
}
