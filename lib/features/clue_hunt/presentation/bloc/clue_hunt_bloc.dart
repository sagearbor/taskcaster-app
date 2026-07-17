import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/repositories/clue_hunt_repository.dart';
import '../../domain/entities/clue_hunt_session.dart';

part 'clue_hunt_event.dart';
part 'clue_hunt_state.dart';

/// Streams a single Clue Hunt game and forwards host / hider / seeker actions to
/// the [ClueHuntRepository]. Every mutation is fire-and-forget; the host-owned
/// authoritative state always comes back through the live session stream, so
/// every phone converges on the same roster, scores and round state.
class ClueHuntBloc extends Bloc<ClueHuntEvent, ClueHuntState> {
  final ClueHuntRepository repository;
  StreamSubscription<ClueHuntSession?>? _sub;

  ClueHuntBloc({required this.repository})
      : super(const ClueHuntState.initial()) {
    on<ClueSubscribed>(_onSubscribed);
    on<_ClueSessionUpdated>(_onSessionUpdated);
    on<ClueGameStarted>((_, __) => repository.startGame());
    on<ClueBeganSeeking>((_, __) => repository.beginSeeking());
    on<ClueFoundClaimed>((_, __) => repository.claimFound());
    on<ClueFindConfirmed>((_, __) => repository.confirmFind());
    on<ClueFindRejected>((_, __) => repository.rejectFind());
    on<ClueNextRound>((_, __) => repository.nextRound());
    on<CluePlayAgain>((_, __) => repository.playAgain());
  }

  void _onSubscribed(ClueSubscribed event, Emitter<ClueHuntState> emit) {
    emit(state.copyWith(status: ClueStatus.loading));
    _sub?.cancel();
    _sub = repository.watchSession().listen(
          (session) => add(_ClueSessionUpdated(session)),
          onError: (Object e) => add(const _ClueSessionUpdated(null)),
        );
  }

  void _onSessionUpdated(
    _ClueSessionUpdated event,
    Emitter<ClueHuntState> emit,
  ) {
    final session = event.session;
    if (session == null) {
      emit(state.copyWith(status: ClueStatus.loaded));
      return;
    }
    emit(state.copyWith(status: ClueStatus.loaded, session: session));
  }

  @override
  Future<void> close() {
    _sub?.cancel();
    return super.close();
  }
}
