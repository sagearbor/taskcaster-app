import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/models/session_mode.dart';
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
    inviteCode: 'ABC123',
    creatorUid: players.first.uid,
    createdAt: DateTime(2026, 7, 1),
    players: players,
    phase: phase,
    step: step,
    chains: chains,
    submittedUids: submittedUids,
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
}
