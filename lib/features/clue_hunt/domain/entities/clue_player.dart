import 'package:equatable/equatable.dart';

/// One participant in a Clue Hunt game. Everyone rotates through the hider role;
/// [totalScore] is the running total across every round and is the only score
/// that matters (there is no per-round live score — a round pays out once, when
/// the hider confirms the find).
class CluePlayer extends Equatable {
  /// Per-session identity (a fresh UUID per device).
  final String id;

  /// Display name shown in the roster, scoreboard and winner ceremony.
  final String name;

  /// Running points across all rounds so far.
  final int totalScore;

  /// True for the device that hosts the lobby and owns the authoritative game.
  final bool isHost;

  /// Whether this player's phone currently has a live link to the host. A drop
  /// flips this to false (the player is KEPT in the roster so their score and
  /// history survive), and it flips back to true when they re-join. The hider
  /// rotation skips non-connected players so the role can never land on a
  /// departed phone and soft-lock the game. The host is always connected to
  /// itself, so its own record stays true.
  final bool connected;

  const CluePlayer({
    required this.id,
    required this.name,
    this.totalScore = 0,
    this.isHost = false,
    this.connected = true,
  });

  CluePlayer copyWith(
      {String? name, int? totalScore, bool? isHost, bool? connected}) {
    return CluePlayer(
      id: id,
      name: name ?? this.name,
      totalScore: totalScore ?? this.totalScore,
      isHost: isHost ?? this.isHost,
      connected: connected ?? this.connected,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'totalScore': totalScore,
        'isHost': isHost,
        'connected': connected,
      };

  factory CluePlayer.fromMap(Map<String, dynamic> map) => CluePlayer(
        id: map['id'] as String? ?? '',
        name: map['name'] as String? ?? 'Player',
        totalScore: (map['totalScore'] as num?)?.toInt() ?? 0,
        isHost: map['isHost'] as bool? ?? false,
        // Older snapshots without the field default to connected.
        connected: map['connected'] as bool? ?? true,
      );

  @override
  List<Object?> get props => [id, name, totalScore, isHost, connected];
}
