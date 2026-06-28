part of 'telephone_bloc.dart';

abstract class TelephoneEvent extends Equatable {
  const TelephoneEvent();

  @override
  List<Object?> get props => [];
}

/// Start listening to a session's live state.
class TelephoneSubscribed extends TelephoneEvent {
  final String sessionId;
  const TelephoneSubscribed(this.sessionId);

  @override
  List<Object?> get props => [sessionId];
}

/// Creator begins play (locks the roster).
class TelephoneStarted extends TelephoneEvent {
  final String sessionId;
  const TelephoneStarted(this.sessionId);

  @override
  List<Object?> get props => [sessionId];
}

/// Host removes a player from the lobby (kick).
class TelephonePlayerRemoved extends TelephoneEvent {
  final String sessionId;
  final String uid;

  const TelephonePlayerRemoved({required this.sessionId, required this.uid});

  @override
  List<Object?> get props => [sessionId, uid];
}

/// A player submits the current step's contribution.
class TelephoneEntrySubmitted extends TelephoneEvent {
  final String sessionId;
  final String uid;
  final String content;

  const TelephoneEntrySubmitted({
    required this.sessionId,
    required this.uid,
    required this.content,
  });

  @override
  List<Object?> get props => [sessionId, uid, content];
}

/// A player rates another player's drawing (same-prompt modes).
class TelephoneRatingSubmitted extends TelephoneEvent {
  final String sessionId;
  final String raterUid;
  final String targetUid;
  final int value;

  const TelephoneRatingSubmitted({
    required this.sessionId,
    required this.raterUid,
    required this.targetUid,
    required this.value,
  });

  @override
  List<Object?> get props => [sessionId, raterUid, targetUid, value];
}

/// One-tap "Play again": repeat with the same players and settings.
class TelephonePlayAgainRequested extends TelephoneEvent {
  final String sessionId;
  const TelephonePlayAgainRequested(this.sessionId);

  @override
  List<Object?> get props => [sessionId];
}
