import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:taskcaster_app/core/models/game.dart';
import 'package:taskcaster_app/features/games/domain/repositories/game_repository.dart';
import 'package:taskcaster_app/features/games/presentation/bloc/game_detail_bloc.dart';

class MockGameRepository extends Mock implements GameRepository {}

class FakeGame extends Fake implements Game {}

/// The scoreboard countdown fires AdvanceToNextTask / CompleteGame on every
/// viewer's device. The bloc must hand the caller to the repository (which
/// writes only for the judge/creator, and only the one field) and never write
/// its cached game back.
void main() {
  late MockGameRepository repo;

  setUpAll(() => registerFallbackValue(FakeGame()));

  setUp(() {
    repo = MockGameRepository();
    when(() => repo.advanceToTask(any(), any(),
        callerId: any(named: 'callerId'))).thenAnswer((_) async {});
    when(() => repo.completeGame(any(), callerId: any(named: 'callerId')))
        .thenAnswer((_) async {});
  });

  Future<void> settle(GameDetailBloc bloc) async {
    await Future<void>.delayed(Duration.zero);
    await bloc.close();
  }

  test('advance goes through advanceToTask with the viewer as caller',
      () async {
    final bloc = GameDetailBloc(gameRepository: repo, currentUserId: 'alice')
      ..add(const AdvanceToNextTaskEvent('g1', 2));
    await settle(bloc);

    verify(() => repo.advanceToTask('g1', 2, callerId: 'alice')).called(1);
    verifyNever(() => repo.updateGame(any(), any()));
  });

  test('complete goes through completeGame with the viewer as caller',
      () async {
    final bloc = GameDetailBloc(gameRepository: repo, currentUserId: 'alice')
      ..add(const CompleteGameEvent('g1'));
    await settle(bloc);

    verify(() => repo.completeGame('g1', callerId: 'alice')).called(1);
    verifyNever(() => repo.updateGame(any(), any()));
  });

  test('without a signed-in viewer nothing is written', () async {
    final bloc = GameDetailBloc(gameRepository: repo)
      ..add(const AdvanceToNextTaskEvent('g1', 1))
      ..add(const CompleteGameEvent('g1'));
    await settle(bloc);

    verifyNever(() =>
        repo.advanceToTask(any(), any(), callerId: any(named: 'callerId')));
    verifyNever(
        () => repo.completeGame(any(), callerId: any(named: 'callerId')));
  });
}
