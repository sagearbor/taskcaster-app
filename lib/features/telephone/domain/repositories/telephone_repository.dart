import '../../../../core/models/telephone_session.dart';

/// Domain API for the Drawing Telephone game. UI talks only to this; the
/// concrete impl wires it to either the mock or Firestore data source.
abstract class TelephoneRepository {
  /// Live state for a session (null once it stops existing).
  Stream<TelephoneSession?> watchSession(String sessionId);

  /// Create a new session in the lobby owned by [creatorUid]. Returns the new
  /// session id together with its generated invite code (the caller persists
  /// both so the host can be resumed later). [creatorUid] is a per-session
  /// player id, NOT the auth uid, so two tabs / guests stay distinct.
  Future<({String sessionId, String inviteCode})> createSession({
    required String creatorUid,
    required String creatorName,
    String? gameName,
    TelephoneGameMode gameMode,
  });

  /// Join the lobby of the session with [inviteCode]. Returns the session id.
  /// Throws if no session matches or the game already started. Idempotent on
  /// [uid]: re-joining with the same per-session id never adds a duplicate.
  Future<String> joinSession({
    required String inviteCode,
    required String uid,
    required String displayName,
  });

  /// Host action: remove [uid] from a lobby's roster (kick an accidental
  /// duplicate or a no-show). No-op once the game has started, or if [uid] is
  /// the creator or not present.
  Future<void> removePlayer({
    required String sessionId,
    required String uid,
  });

  /// Lock the roster and begin play (creator action).
  Future<void> startGame(String sessionId);

  /// Submit the current step's contribution for [uid]. [content] is text for a
  /// prompt/guess or JSON strokes for a drawing.
  Future<void> submitEntry({
    required String sessionId,
    required String uid,
    required String content,
  });

  /// Same-prompt modes: [raterUid] scores [targetUid]'s drawing [value] (1–10).
  /// A player may never rate their own drawing (enforced in the model). Once
  /// every player has rated everyone else the session flips to results.
  Future<void> submitRating({
    required String sessionId,
    required String raterUid,
    required String targetUid,
    required int value,
  });

  /// One-tap "Play again": start a fresh round with the same players, mode and
  /// settings, carrying the running leaderboard. No-op unless the game is at a
  /// terminal phase (reveal/results), so concurrent taps are safe.
  Future<void> playAgain(String sessionId);
}
