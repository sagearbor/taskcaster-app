import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/models/telephone_session.dart';
import '../../domain/repositories/telephone_repository.dart';

part 'telephone_event.dart';
part 'telephone_state.dart';

/// Streams a single Drawing Telephone session and forwards player actions to
/// the repository. Mutations (start/submit) are fire-and-forget against the
/// repo — the authoritative state always comes back via the live stream, so
/// every device converges on the same Firestore document.
class TelephoneBloc extends Bloc<TelephoneEvent, TelephoneState> {
  final TelephoneRepository repository;

  TelephoneBloc({required this.repository})
      : super(const TelephoneState.initial()) {
    on<TelephoneSubscribed>(_onSubscribed);
    on<TelephoneStarted>(_onStarted);
    on<TelephonePlayerRemoved>(_onPlayerRemoved);
    on<TelephoneEntrySubmitted>(_onSubmitted);
    on<TelephoneRatingSubmitted>(_onRated);
    on<TelephonePlayAgainRequested>(_onPlayAgain);
  }

  Future<void> _onSubscribed(
    TelephoneSubscribed event,
    Emitter<TelephoneState> emit,
  ) async {
    emit(state.copyWith(status: TelephoneStatus.loading));
    await emit.forEach<TelephoneSession?>(
      repository.watchSession(event.sessionId),
      onData: (session) => session == null
          ? state.copyWith(
              status: TelephoneStatus.error,
              error: 'This game no longer exists.',
            )
          : state.copyWith(
              status: TelephoneStatus.loaded,
              session: session,
              clearError: true,
            ),
      onError: (error, _) =>
          state.copyWith(status: TelephoneStatus.error, error: error.toString()),
    );
  }

  Future<void> _onStarted(
    TelephoneStarted event,
    Emitter<TelephoneState> emit,
  ) async {
    try {
      await repository.startGame(event.sessionId);
    } catch (e) {
      emit(state.copyWith(error: _friendly(e)));
    }
  }

  Future<void> _onPlayerRemoved(
    TelephonePlayerRemoved event,
    Emitter<TelephoneState> emit,
  ) async {
    try {
      await repository.removePlayer(
        sessionId: event.sessionId,
        uid: event.uid,
      );
    } catch (e) {
      emit(state.copyWith(error: _friendly(e)));
    }
  }

  Future<void> _onSubmitted(
    TelephoneEntrySubmitted event,
    Emitter<TelephoneState> emit,
  ) async {
    // Clearing the error up front means the SAME failure twice in a row still
    // re-triggers the screen's error listener (it fires on error *changes*).
    emit(state.copyWith(submitting: true, clearError: true));
    try {
      await repository.submitEntry(
        sessionId: event.sessionId,
        uid: event.uid,
        content: event.content,
      );
      emit(state.copyWith(submitting: false));
    } catch (e) {
      // Surface the failure AND re-enable the submit button, so an offline
      // player whose send to the host failed can just move closer and retry.
      emit(state.copyWith(submitting: false, error: _friendly(e)));
    }
  }

  Future<void> _onRated(
    TelephoneRatingSubmitted event,
    Emitter<TelephoneState> emit,
  ) async {
    try {
      await repository.submitRating(
        sessionId: event.sessionId,
        raterUid: event.raterUid,
        targetUid: event.targetUid,
        value: event.value,
      );
    } catch (e) {
      emit(state.copyWith(error: _friendly(e)));
    }
  }

  Future<void> _onPlayAgain(
    TelephonePlayAgainRequested event,
    Emitter<TelephoneState> emit,
  ) async {
    try {
      await repository.playAgain(event.sessionId);
    } catch (e) {
      emit(state.copyWith(error: _friendly(e)));
    }
  }

  /// Repositories throw [StateError]s whose message is already player-ready
  /// copy (e.g. the offline Nearby repo when the host link drops) — surface
  /// those verbatim. Everything else keeps the legacy prefix-stripping.
  String _friendly(Object error) {
    if (error is StateError) return error.message;
    return error.toString().replaceFirst('Exception: ', '');
  }
}
