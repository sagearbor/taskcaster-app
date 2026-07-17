part of 'clue_hunt_bloc.dart';

/// Host / hider / seeker actions on a Clue Hunt. Mutations are fire-and-forget
/// against the repository; the authoritative state always returns via the live
/// session stream.
abstract class ClueHuntEvent extends Equatable {
  const ClueHuntEvent();

  @override
  List<Object?> get props => [];
}

/// Start listening to the authoritative session stream.
class ClueSubscribed extends ClueHuntEvent {
  const ClueSubscribed();
}

/// HOST: leave the lobby and begin round 1 (host hides first).
class ClueGameStarted extends ClueHuntEvent {
  const ClueGameStarted();
}

/// HIDER: the object is hidden — start the hunt.
class ClueBeganSeeking extends ClueHuntEvent {
  const ClueBeganSeeking();
}

/// SEEKER: "Found it!" — I physically grabbed the object.
class ClueFoundClaimed extends ClueHuntEvent {
  const ClueFoundClaimed();
}

/// HIDER: confirm the pending claim (score the finder).
class ClueFindConfirmed extends ClueHuntEvent {
  const ClueFindConfirmed();
}

/// HIDER: reject the pending claim (resume seeking).
class ClueFindRejected extends ClueHuntEvent {
  const ClueFindRejected();
}

/// HOST: advance past the round result — rotate the hider or end the game.
class ClueNextRound extends ClueHuntEvent {
  const ClueNextRound();
}

/// HOST: start a whole new game from the winner ceremony.
class CluePlayAgain extends ClueHuntEvent {
  const CluePlayAgain();
}

/// Internal: a new authoritative session arrived from the repository stream.
class _ClueSessionUpdated extends ClueHuntEvent {
  final ClueHuntSession? session;
  const _ClueSessionUpdated(this.session);

  @override
  List<Object?> get props => [session];
}
