import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/models/telephone_session.dart';
import 'package:taskcaster_app/features/telephone/data/practice/local_practice_telephone_repository.dart';
import 'package:taskcaster_app/features/telephone/presentation/widgets/drawing_canvas.dart';

void main() {
  late LocalPracticeTelephoneRepository repo;

  setUp(() => repo = LocalPracticeTelephoneRepository());
  tearDown(() => repo.dispose());

  Future<TelephoneSession> read(String id) async =>
      (await repo.watchSession(id).first)!;

  Future<String> start() => repo.startPractice(
        humanUid: 'me',
        humanName: 'Sage',
        random: Random(7), // deterministic bot content
      );

  group('startPractice', () {
    test('opens an in-memory game already in play: human + 2 bots, step 0',
        () async {
      final id = await start();
      final s = await read(id);

      expect(s.isPlaying, isTrue, reason: 'no lobby, no Start button');
      expect(s.step, 0);
      expect(s.currentEntryType, TelephoneEntryType.prompt);
      expect(s.playerCount, 3, reason: 'you plus exactly two bots → 3 chains');
      expect(s.creatorUid, 'me');
      expect(s.hasSubmittedCurrentStep('me'), isFalse,
          reason: 'it is the human turn first');
    });
  });

  group('bot auto-submit', () {
    test('a single human submission advances straight to the human next turn',
        () async {
      final id = await start();

      await repo.submitEntry(sessionId: id, uid: 'me', content: 'a robot chef');
      final s = await read(id);

      // Both bots filled step 0, so the step advanced and the human is up again
      // — the human never sees a "waiting on N players" screen.
      expect(s.step, 1);
      expect(s.currentEntryType, TelephoneEntryType.drawing);
      expect(s.hasSubmittedCurrentStep('me'), isFalse);
      // Step 0 (the prompts) collected one entry per chain from all 3 players.
      expect(s.chains.every((c) => c.length == 1), isTrue);
    });
  });

  group('full game to reveal', () {
    test('playing every human step drives the game to a complete reveal',
        () async {
      final id = await start();

      var s = await read(id);
      var humanSteps = 0;
      while (s.isPlaying) {
        // Provide human content appropriate to the step (the model does not
        // validate content, so any non-empty string works for every type).
        await repo.submitEntry(
          sessionId: id,
          uid: 'me',
          content: 'human-step-${s.step}',
        );
        s = await read(id);
        humanSteps++;
        expect(humanSteps, lessThanOrEqualTo(3), reason: 'must terminate');
      }

      expect(s.isRevealing, isTrue);
      expect(humanSteps, 3, reason: 'one human action per step, 3 players');
      expect(s.chains, hasLength(3), reason: 'one full chain per player');
      for (final chain in s.chains) {
        expect(chain, hasLength(3),
            reason: 'every chain has an entry from every player');
      }

      // Bot drawings use the real drawing JSON format and decode to actual
      // strokes the reveal can render. (The human's drawing entries here are
      // plain placeholder text, so we check the bot-authored ones.)
      final botDrawings = s.chains
          .expand((c) => c)
          .where((e) =>
              e.type == TelephoneEntryType.drawing && e.authorUid != 'me')
          .toList();
      expect(botDrawings, isNotEmpty);
      for (final d in botDrawings) {
        expect(parseStrokes(d.content), isNotEmpty,
            reason: 'a bot scribble must parse to drawable strokes');
      }
    });
  });

  group('offline only', () {
    test('online lobby/network actions are not available in practice', () async {
      expect(
        () => repo.createSession(creatorUid: 'me', creatorName: 'Sage'),
        throwsUnsupportedError,
      );
      expect(
        () => repo.joinSession(inviteCode: 'SOLO', uid: 'x', displayName: 'y'),
        throwsUnsupportedError,
      );
    });
  });

  group('same-prompt practice (drawings + bot ratings)', () {
    Future<String> startSamePrompt() => repo.startPractice(
          humanUid: 'me',
          humanName: 'Sage',
          gameMode: TelephoneGameMode.samePrompt,
          random: Random(7),
        );

    test('one human drawing fills the bots and lands on the rating phase',
        () async {
      final id = await startSamePrompt();
      var s = await read(id);
      expect(s.gameMode, TelephoneGameMode.samePrompt);
      expect(s.prompt, isNotEmpty, reason: 'a shared prompt is chosen');

      await repo.submitEntry(sessionId: id, uid: 'me', content: 'my cat');
      s = await read(id);

      expect(s.isRating, isTrue, reason: 'bots drew the moment the human did');
      expect(s.chains.every((c) => c.length == 1), isTrue,
          reason: 'every player has exactly one drawing');
    });

    test('human ratings + bot ratings drive the game to a winner', () async {
      final id = await startSamePrompt();
      await repo.submitEntry(sessionId: id, uid: 'me', content: 'my cat');
      var s = await read(id);

      // The human rates each bot; the bots auto-rate once the human is done.
      for (final p in s.players.where((p) => p.uid != 'me')) {
        await repo.submitRating(
            sessionId: id, raterUid: 'me', targetUid: p.uid, value: 7);
        s = await read(id);
      }

      expect(s.isShowingResults, isTrue);
      expect(s.winnerUids, isNotEmpty, reason: 'someone wins');
      // Every player received a rating from each of the other two.
      expect(s.ratings, hasLength(3 * 2));
      expect(s.tallyPoints.values.fold<int>(0, (a, b) => a + b),
          greaterThan(0));
    });

    test('play again restarts a fresh round, carrying the running tally',
        () async {
      final id = await startSamePrompt();
      await repo.submitEntry(sessionId: id, uid: 'me', content: 'my cat');
      var s = await read(id);
      for (final p in s.players.where((p) => p.uid != 'me')) {
        await repo.submitRating(
            sessionId: id, raterUid: 'me', targetUid: p.uid, value: 7);
      }
      s = await read(id);
      expect(s.isShowingResults, isTrue);
      final tallyBefore = Map<String, int>.from(s.tallyPoints);

      await repo.playAgain(id);
      s = await read(id);

      expect(s.isPlaying, isTrue);
      expect(s.roundNumber, 2);
      expect(s.chains.every((c) => c.isEmpty), isTrue);
      expect(s.ratings, isEmpty);
      expect(s.tallyPoints, equals(tallyBefore), reason: 'tally carries over');
      expect(s.hasSubmittedCurrentStep('me'), isFalse,
          reason: 'human draws first again');
    });
  });
}
