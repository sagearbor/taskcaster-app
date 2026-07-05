import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:taskcaster_app/core/models/telephone_session.dart';
import 'package:taskcaster_app/core/utils/friendly_errors.dart';
import 'package:taskcaster_app/features/telephone/domain/repositories/telephone_repository.dart';
import 'package:taskcaster_app/features/telephone/presentation/bloc/telephone_bloc.dart';

class MockTelephoneRepository extends Mock implements TelephoneRepository {}

TelephoneSession _session() => TelephoneSession.create(
      id: 's1',
      gameName: 'Test',
      inviteCode: 'ABC123',
      creatorUid: 'p0',
      creatorName: 'P0',
      gameMode: TelephoneGameMode.samePrompt,
      createdAt: DateTime(2026, 1, 1),
    ).withPlayerJoined('p1', 'P1');

void main() {
  late MockTelephoneRepository repo;

  setUp(() => repo = MockTelephoneRepository());

  group('TelephoneBloc — subscription', () {
    blocTest<TelephoneBloc, TelephoneState>(
      'streams the session into a loaded state',
      build: () {
        when(() => repo.watchSession('s1'))
            .thenAnswer((_) => Stream.value(_session()));
        return TelephoneBloc(repository: repo);
      },
      act: (bloc) => bloc.add(const TelephoneSubscribed('s1')),
      expect: () => [
        isA<TelephoneState>()
            .having((s) => s.status, 'status', TelephoneStatus.loading),
        isA<TelephoneState>()
            .having((s) => s.status, 'status', TelephoneStatus.loaded)
            .having((s) => s.session?.id, 'session id', 's1'),
      ],
    );
  });

  group('TelephoneBloc — actions forward to the repository', () {
    blocTest<TelephoneBloc, TelephoneState>(
      'submitEntry is forwarded',
      build: () {
        when(() => repo.submitEntry(
              sessionId: any(named: 'sessionId'),
              uid: any(named: 'uid'),
              content: any(named: 'content'),
            )).thenAnswer((_) async {});
        return TelephoneBloc(repository: repo);
      },
      act: (bloc) => bloc.add(const TelephoneEntrySubmitted(
        sessionId: 's1',
        uid: 'p0',
        content: 'draw',
      )),
      verify: (_) {
        verify(() => repo.submitEntry(
              sessionId: 's1',
              uid: 'p0',
              content: 'draw',
            )).called(1);
      },
    );

    blocTest<TelephoneBloc, TelephoneState>(
      'rating is forwarded with rater/target/value',
      build: () {
        when(() => repo.submitRating(
              sessionId: any(named: 'sessionId'),
              raterUid: any(named: 'raterUid'),
              targetUid: any(named: 'targetUid'),
              value: any(named: 'value'),
            )).thenAnswer((_) async {});
        return TelephoneBloc(repository: repo);
      },
      act: (bloc) => bloc.add(const TelephoneRatingSubmitted(
        sessionId: 's1',
        raterUid: 'p0',
        targetUid: 'p1',
        value: 8,
      )),
      verify: (_) {
        verify(() => repo.submitRating(
              sessionId: 's1',
              raterUid: 'p0',
              targetUid: 'p1',
              value: 8,
            )).called(1);
      },
    );

    blocTest<TelephoneBloc, TelephoneState>(
      'play again is forwarded',
      build: () {
        when(() => repo.playAgain(any())).thenAnswer((_) async {});
        return TelephoneBloc(repository: repo);
      },
      act: (bloc) => bloc.add(const TelephonePlayAgainRequested('s1')),
      verify: (_) {
        verify(() => repo.playAgain('s1')).called(1);
      },
    );

    blocTest<TelephoneBloc, TelephoneState>(
      'submit toggles the in-flight flag around a successful send',
      build: () {
        when(() => repo.submitEntry(
              sessionId: any(named: 'sessionId'),
              uid: any(named: 'uid'),
              content: any(named: 'content'),
            )).thenAnswer((_) async {});
        return TelephoneBloc(repository: repo);
      },
      act: (bloc) => bloc.add(const TelephoneEntrySubmitted(
        sessionId: 's1',
        uid: 'p0',
        content: 'draw',
      )),
      expect: () => [
        isA<TelephoneState>()
            .having((s) => s.submitting, 'submitting', true)
            .having((s) => s.error, 'error', isNull),
        isA<TelephoneState>()
            .having((s) => s.submitting, 'submitting', false)
            .having((s) => s.error, 'error', isNull),
      ],
    );

    blocTest<TelephoneBloc, TelephoneState>(
      "a failed offline submit surfaces the repository's player-ready copy "
      'and re-enables the submit button',
      build: () {
        when(() => repo.submitEntry(
              sessionId: any(named: 'sessionId'),
              uid: any(named: 'uid'),
              content: any(named: 'content'),
            )).thenThrow(StateError(FriendlyErrors.nearbyHostLost));
        return TelephoneBloc(repository: repo);
      },
      act: (bloc) => bloc.add(const TelephoneEntrySubmitted(
        sessionId: 's1',
        uid: 'p0',
        content: 'draw',
      )),
      expect: () => [
        isA<TelephoneState>()
            .having((s) => s.submitting, 'submitting', true),
        isA<TelephoneState>()
            .having((s) => s.submitting, 'submitting', false)
            .having((s) => s.error, 'error', FriendlyErrors.nearbyHostLost),
      ],
    );

    blocTest<TelephoneBloc, TelephoneState>(
      'a failed rating surfaces a friendly error without blanking the session',
      build: () {
        when(() => repo.submitRating(
              sessionId: any(named: 'sessionId'),
              raterUid: any(named: 'raterUid'),
              targetUid: any(named: 'targetUid'),
              value: any(named: 'value'),
            )).thenThrow(Exception('network down'));
        return TelephoneBloc(repository: repo);
      },
      act: (bloc) => bloc.add(const TelephoneRatingSubmitted(
        sessionId: 's1',
        raterUid: 'p0',
        targetUid: 'p1',
        value: 8,
      )),
      expect: () => [
        isA<TelephoneState>()
            .having((s) => s.error, 'error', 'network down'),
      ],
    );
  });
}
