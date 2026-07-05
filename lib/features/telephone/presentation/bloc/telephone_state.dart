part of 'telephone_bloc.dart';

enum TelephoneStatus { initial, loading, loaded, error }

class TelephoneState extends Equatable {
  final TelephoneStatus status;
  final TelephoneSession? session;

  /// Transient action error (e.g. a failed submit). The live [session] is kept
  /// so the UI never blanks out; the screen surfaces this via a SnackBar.
  final String? error;

  /// True while a submit (prompt / drawing / guess) is in flight against the
  /// repository. Drives the submit button's spinner + disabled state, so a
  /// slow or offline send gives visible feedback instead of silence.
  final bool submitting;

  const TelephoneState({
    required this.status,
    this.session,
    this.error,
    this.submitting = false,
  });

  const TelephoneState.initial()
      : status = TelephoneStatus.initial,
        session = null,
        error = null,
        submitting = false;

  TelephoneState copyWith({
    TelephoneStatus? status,
    TelephoneSession? session,
    String? error,
    bool clearError = false,
    bool? submitting,
  }) {
    return TelephoneState(
      status: status ?? this.status,
      session: session ?? this.session,
      error: clearError ? null : (error ?? this.error),
      submitting: submitting ?? this.submitting,
    );
  }

  @override
  List<Object?> get props => [status, session, error, submitting];
}
