import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/models/session_mode.dart';
import 'package:taskcaster_app/core/utils/friendly_errors.dart';
import 'package:taskcaster_app/core/models/telephone_session.dart';
import 'package:taskcaster_app/core/widgets/user_avatar.dart';
import 'package:taskcaster_app/features/telephone/domain/repositories/telephone_repository.dart';
import 'package:taskcaster_app/features/telephone/presentation/screens/telephone_session_screen.dart';

/// Serves one fixed session over the repository interface — enough for the
/// screen's read-only reveal / waiting states.
class _FakeTelephoneRepository implements TelephoneRepository {
  final TelephoneSession session;
  _FakeTelephoneRepository(this.session);

  @override
  Stream<TelephoneSession?> watchSession(String sessionId) =>
      Stream<TelephoneSession?>.value(session);

  @override
  Future<({String sessionId, String inviteCode})> createSession({
    required String creatorUid,
    required String creatorName,
    String? gameName,
    TelephoneGameMode gameMode = TelephoneGameMode.classicTelephone,
  }) =>
      throw UnimplementedError();

  @override
  Future<String> joinSession({
    required String inviteCode,
    required String uid,
    required String displayName,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> removePlayer({required String sessionId, required String uid}) =>
      throw UnimplementedError();

  @override
  Future<void> startGame(String sessionId) => throw UnimplementedError();

  @override
  Future<void> submitEntry({
    required String sessionId,
    required String uid,
    required String content,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> submitRating({
    required String sessionId,
    required String raterUid,
    required String targetUid,
    required int value,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> playAgain(String sessionId) => throw UnimplementedError();
}

const _drawingJson = '[{"c":4278190080,"p":[0.1,0.1,0.5,0.5,0.9,0.2]}]';

TelephoneEntry _entry(TelephoneEntryType type, String content, String uid,
        String name) =>
    TelephoneEntry(
        type: type, content: content, authorUid: uid, authorName: name);

TelephoneSession _session({
  required TelephonePhase phase,
  required int step,
  required List<TelephonePlayer> players,
  required List<List<TelephoneEntry>> chains,
  List<String> submittedUids = const [],
}) {
  return TelephoneSession(
    id: 'session-1',
    gameName: 'Drawing Telephone',
    mode: SessionMode.party,
    gameMode: TelephoneGameMode.classicTelephone,
    inviteCode: 'ABC123',
    creatorUid: players.first.uid,
    createdAt: DateTime(2026, 7, 1),
    players: players,
    phase: phase,
    step: step,
    prompt: '',
    chains: chains,
    submittedUids: submittedUids,
    ratings: const [],
    roundNumber: 1,
    tallyPoints: const {},
    roundsWon: const {},
  );
}

Widget _screen(TelephoneSession session, {String playerId = 'p1'}) {
  return MaterialApp(
    home: TelephoneSessionScreen(
      sessionId: session.id,
      playerId: playerId,
      displayName: 'Ana',
      repository: _FakeTelephoneRepository(session),
    ),
  );
}

void main() {
  group('staged reveal', () {
    // 2 players → 2 chains × 2 entries (prompt, drawing).
    final revealSession = _session(
      phase: TelephonePhase.reveal,
      step: 2,
      players: const [
        TelephonePlayer(uid: 'p1', displayName: 'Ana'),
        TelephonePlayer(uid: 'p2', displayName: 'Ben'),
      ],
      chains: [
        [
          _entry(TelephoneEntryType.prompt, 'A cat in space', 'p1', 'Ana'),
          _entry(TelephoneEntryType.drawing, _drawingJson, 'p2', 'Ben'),
        ],
        [
          _entry(TelephoneEntryType.prompt, 'Robot chef', 'p2', 'Ben'),
          _entry(TelephoneEntryType.drawing, _drawingJson, 'p1', 'Ana'),
        ],
      ],
    );

    testWidgets(
        'advances entry-by-entry, then chain-by-chain, then lands on the recap',
        (tester) async {
      await tester.pumpWidget(_screen(revealSession));
      await tester.pumpAndSettle();

      // Chain 1, entry 1 only.
      expect(find.text('Chain 1 of 2 · step 1/2'), findsOneWidget);
      expect(find.text("Ana's chain"), findsOneWidget);
      expect(find.text('A cat in space'), findsOneWidget);
      expect(find.textContaining('Ben drew'), findsNothing);

      // Advance within the chain: the drawing entry appears (animated).
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Chain 1 of 2 · step 2/2'), findsOneWidget);
      expect(find.textContaining('Ben drew'), findsOneWidget);

      // End of chain 1 → next chain.
      expect(find.text('Next chain'), findsOneWidget);
      await tester.tap(find.text('Next chain'));
      await tester.pumpAndSettle();
      expect(find.text('Chain 2 of 2 · step 1/2'), findsOneWidget);
      expect(find.text('Robot chef'), findsOneWidget);
      expect(find.text('A cat in space'), findsNothing);

      // Last entry of the last chain → recap.
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('See full recap'), findsOneWidget);
      await tester.tap(find.text('See full recap'));
      await tester.pumpAndSettle();

      // Full recap: every chain in one list, plus the ceremony on top.
      expect(find.text("That's a wrap!"), findsOneWidget);
      expect(find.byIcon(Icons.emoji_events), findsOneWidget);
      expect(find.text('A cat in space'), findsOneWidget);
      expect(find.text("Ana's chain"), findsOneWidget);
      // The second chain's card sits below the fold — scroll it into view.
      await tester.scrollUntilVisible(find.text('Robot chef'), 200);
      expect(find.text('Robot chef'), findsOneWidget);
      expect(find.text("Ben's chain"), findsOneWidget);
    });

    testWidgets('tap-anywhere advances the reveal too', (tester) async {
      await tester.pumpWidget(_screen(revealSession));
      await tester.pumpAndSettle();

      expect(find.text('Chain 1 of 2 · step 1/2'), findsOneWidget);
      // Tap the chain card itself (not the button).
      await tester.tap(find.text('A cat in space'));
      await tester.pumpAndSettle();
      expect(find.text('Chain 1 of 2 · step 2/2'), findsOneWidget);
    });
  });

  group('waiting view', () {
    final waitingSession = _session(
      phase: TelephonePhase.playing,
      step: 1,
      players: const [
        TelephonePlayer(uid: 'p1', displayName: 'Ana'),
        TelephonePlayer(uid: 'p2', displayName: 'Ben'),
        TelephonePlayer(uid: 'p3', displayName: 'Cara'),
      ],
      chains: [
        [_entry(TelephoneEntryType.prompt, 'A cat in space', 'p1', 'Ana')],
        [_entry(TelephoneEntryType.prompt, 'Robot chef', 'p2', 'Ben')],
        [_entry(TelephoneEntryType.prompt, 'Moon cheese', 'p3', 'Cara')],
      ],
      submittedUids: const ['p1'],
    );

    testWidgets('shows one avatar per player with submitted-state badges',
        (tester) async {
      await tester.pumpWidget(_screen(waitingSession));
      await tester.pumpAndSettle();

      expect(find.text('Submitted! 🎉'), findsOneWidget);
      expect(find.text('1/3 done'), findsOneWidget);

      // One chip per player; only the submitted player gets a check badge.
      expect(find.byType(UserAvatar), findsNWidgets(3));
      expect(find.byIcon(Icons.check_circle), findsOneWidget);

      // The spinner purgatory is gone.
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows a playful quip naming a player still working',
        (tester) async {
      await tester.pumpWidget(_screen(waitingSession));
      await tester.pumpAndSettle();

      // step 1 → quip index 1, name = first non-submitted player (Ben).
      expect(find.text('Ben is still picking the perfect colour…'),
          findsOneWidget);
    });
  });

  group('submit resilience (offline peer whose send fails)', () {
    // Playing, step 0 of the classic chain → the prompt input for p1.
    final promptSession = _session(
      phase: TelephonePhase.playing,
      step: 0,
      players: const [
        TelephonePlayer(uid: 'p1', displayName: 'Ana'),
        TelephonePlayer(uid: 'p2', displayName: 'Ben'),
      ],
      chains: [[], []],
    );

    Widget probeScreen(_SubmitProbeRepository repo) => MaterialApp(
          home: TelephoneSessionScreen(
            sessionId: promptSession.id,
            playerId: 'p1',
            displayName: 'Ana',
            repository: repo,
          ),
        );

    testWidgets('shows a spinner while the submit is in flight',
        (tester) async {
      final repo = _SubmitProbeRepository(promptSession)
        ..pending = Completer<void>();
      await tester.pumpWidget(probeScreen(repo));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'A cat in space');
      await tester.tap(find.text('Submit prompt'));
      await tester.pump();

      // In flight: label swapped for a spinner, button disabled.
      expect(find.text('Submit prompt'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      repo.pending!.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('Submit prompt'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets(
        'a failed submit shows the friendly SnackBar and re-enables the '
        'button for a retry — never a silent dead button', (tester) async {
      final repo = _SubmitProbeRepository(promptSession)
        ..throwOnSubmit = StateError(FriendlyErrors.nearbyHostLost);
      await tester.pumpWidget(probeScreen(repo));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'A cat in space');
      await tester.tap(find.text('Submit prompt'));
      await tester.pump();
      await tester.pump();

      // The player is told what happened, in FriendlyErrors voice.
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text(FriendlyErrors.nearbyHostLost), findsOneWidget);

      // And the button is usable again for a retry with the same content.
      final button = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Submit prompt'));
      expect(button.onPressed, isNotNull);
      expect(repo.submitCalls, 1);

      // Retry actually re-sends.
      repo.throwOnSubmit = null;
      await tester.tap(find.text('Submit prompt'));
      await tester.pump();
      await tester.pump();
      expect(repo.submitCalls, 2);

      // Let the SnackBar's auto-dismiss timer finish so the test ends clean.
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });
  });
}

/// A [_FakeTelephoneRepository] whose [submitEntry] can be held open (to see
/// the in-flight spinner) or made to throw (to see the error SnackBar).
class _SubmitProbeRepository extends _FakeTelephoneRepository {
  _SubmitProbeRepository(super.session);

  Completer<void>? pending;
  Object? throwOnSubmit;
  int submitCalls = 0;

  @override
  Future<void> submitEntry({
    required String sessionId,
    required String uid,
    required String content,
  }) async {
    submitCalls++;
    final error = throwOnSubmit;
    if (error != null) throw error;
    final gate = pending;
    if (gate != null) await gate.future;
  }
}
