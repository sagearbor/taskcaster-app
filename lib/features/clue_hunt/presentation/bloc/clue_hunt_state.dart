part of 'clue_hunt_bloc.dart';

enum ClueStatus { initial, loading, loaded, error }

/// UI-facing state for a Clue Hunt: the latest authoritative session plus a
/// transient error message for action failures.
class ClueHuntState extends Equatable {
  final ClueStatus status;
  final ClueHuntSession? session;
  final String? error;

  const ClueHuntState({
    this.status = ClueStatus.initial,
    this.session,
    this.error,
  });

  const ClueHuntState.initial() : this();

  ClueHuntState copyWith({
    ClueStatus? status,
    ClueHuntSession? session,
    String? error,
    bool clearError = false,
  }) {
    return ClueHuntState(
      status: status ?? this.status,
      session: session ?? this.session,
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  List<Object?> get props => [status, session, error];
}
