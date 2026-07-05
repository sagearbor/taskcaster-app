part of 'balloon_blitz_bloc.dart';

/// Player / host actions on a Balloon Blitz race. Mutations are fire-and-forget
/// against the repository; the authoritative state always returns via the live
/// session stream.
abstract class BalloonBlitzEvent extends Equatable {
  const BalloonBlitzEvent();

  @override
  List<Object?> get props => [];
}

/// Start listening to the authoritative session stream.
class BlitzSubscribed extends BalloonBlitzEvent {
  const BlitzSubscribed();
}

/// HOST: begin a synchronized round (everyone starts popping).
class BlitzRoundStarted extends BalloonBlitzEvent {
  const BlitzRoundStarted();
}

/// HOST: end the round early (e.g. the local AR game finished). Idempotent.
class BlitzRoundEnded extends BalloonBlitzEvent {
  const BlitzRoundEnded();
}

/// HOST: return everyone to the lobby for another race.
class BlitzPlayAgainRequested extends BalloonBlitzEvent {
  const BlitzPlayAgainRequested();
}

/// Internal: a new authoritative session arrived from the repository stream.
class _BlitzSessionUpdated extends BalloonBlitzEvent {
  final BlitzSession? session;
  const _BlitzSessionUpdated(this.session);

  @override
  List<Object?> get props => [session];
}
