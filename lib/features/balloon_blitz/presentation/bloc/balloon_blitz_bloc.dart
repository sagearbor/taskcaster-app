import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/repositories/balloon_blitz_repository.dart';
import '../../domain/entities/blitz_session.dart';

part 'balloon_blitz_event.dart';
part 'balloon_blitz_state.dart';

/// Streams a single Balloon Blitz race and forwards player / host actions to the
/// [BalloonBlitzRepository]. Every mutation is fire-and-forget; the host-owned
/// authoritative state always comes back through the live session stream, so
/// every phone converges on the same leaderboard.
class BalloonBlitzBloc extends Bloc<BalloonBlitzEvent, BalloonBlitzState> {
  final BalloonBlitzRepository repository;
  StreamSubscription<BlitzSession?>? _sub;

  BalloonBlitzBloc({required this.repository})
      : super(const BalloonBlitzState.initial()) {
    on<BlitzSubscribed>(_onSubscribed);
    on<_BlitzSessionUpdated>(_onSessionUpdated);
    on<BlitzRoundStarted>(_onRoundStarted);
    on<BlitzRoundEnded>(_onRoundEnded);
    on<BlitzPlayAgainRequested>(_onPlayAgain);
  }

  void _onSubscribed(BlitzSubscribed event, Emitter<BalloonBlitzState> emit) {
    emit(state.copyWith(status: BlitzStatus.loading));
    _sub?.cancel();
    _sub = repository.watchSession().listen(
          (session) => add(_BlitzSessionUpdated(session)),
          onError: (Object e) => add(const _BlitzSessionUpdated(null)),
        );
  }

  void _onSessionUpdated(
    _BlitzSessionUpdated event,
    Emitter<BalloonBlitzState> emit,
  ) {
    final session = event.session;
    if (session == null) {
      emit(state.copyWith(status: BlitzStatus.loaded));
      return;
    }
    emit(state.copyWith(
      status: BlitzStatus.loaded,
      session: session,
      clearError: true,
    ));
  }

  Future<void> _onRoundStarted(
    BlitzRoundStarted event,
    Emitter<BalloonBlitzState> emit,
  ) async {
    await repository.startRound();
  }

  Future<void> _onRoundEnded(
    BlitzRoundEnded event,
    Emitter<BalloonBlitzState> emit,
  ) async {
    repository.endRound();
  }

  Future<void> _onPlayAgain(
    BlitzPlayAgainRequested event,
    Emitter<BalloonBlitzState> emit,
  ) async {
    await repository.playAgain();
  }

  @override
  Future<void> close() {
    _sub?.cancel();
    return super.close();
  }
}
