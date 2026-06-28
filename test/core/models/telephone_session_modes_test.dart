import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/models/telephone_session.dart';

/// A started same-prompt session with [n] players (p0 = creator).
TelephoneSession samePromptStarted({
  TelephoneGameMode mode = TelephoneGameMode.samePrompt,
  int n = 3,
  String prompt = 'Draw a cat',
}) {
  var s = TelephoneSession.create(
    id: 's1',
    gameName: 'Test',
    inviteCode: 'ABC123',
    creatorUid: 'p0',
    creatorName: 'P0',
    gameMode: mode,
    createdAt: DateTime(2026, 1, 1),
  );
  for (var i = 1; i < n; i++) {
    s = s.withPlayerJoined('p$i', 'P$i');
  }
  return s.started(prompt: prompt);
}

/// Every player rates every OTHER player using [value(rater, target)]. Returns
/// the session once all ratings are in (which flips it to results).
TelephoneSession rateEveryone(
    TelephoneSession s, int Function(String rater, String target) value) {
  for (final rater in s.players) {
    for (final target in s.players) {
      if (rater.uid == target.uid) continue;
      s = s.withRating(
        raterUid: rater.uid,
        targetUid: target.uid,
        value: value(rater.uid, target.uid),
      );
    }
  }
  return s;
}

void main() {
  group('Same prompt (simultaneous)', () {
    test('start sets a shared prompt, one empty chain per player, single step',
        () {
      final s = samePromptStarted();
      expect(s.gameMode, TelephoneGameMode.samePrompt);
      expect(s.isPlaying, isTrue);
      expect(s.prompt, 'Draw a cat');
      expect(s.chains, hasLength(3));
      expect(s.chains.every((c) => c.isEmpty), isTrue);
      expect(s.totalSteps, 1, reason: 'everyone draws in one shared step');
      expect(s.currentEntryType, TelephoneEntryType.drawing);
    });

    test('each player draws into their OWN chain; all drawn → rating phase', () {
      var s = samePromptStarted();
      s = s.withSubmission('p0', 'draw-0');
      expect(s.isPlaying, isTrue, reason: 'still waiting on others');
      expect(s.chains[0].single.authorUid, 'p0');
      s = s.withSubmission('p1', 'draw-1');
      s = s.withSubmission('p2', 'draw-2');

      expect(s.isRating, isTrue, reason: 'all drawings in → rate');
      for (var i = 0; i < 3; i++) {
        expect(s.chains[i].single.type, TelephoneEntryType.drawing);
        expect(s.chains[i].single.authorUid, 'p$i');
      }
    });

    test('re-submitting a drawing is ignored (idempotent)', () {
      var s = samePromptStarted();
      s = s.withSubmission('p0', 'first');
      s = s.withSubmission('p0', 'second');
      expect(s.chains[0], hasLength(1));
      expect(s.chains[0].single.content, 'first');
    });
  });

  group('Same prompt (turn-taking)', () {
    test('only the active drawer may submit; out-of-turn is a no-op', () {
      var s = samePromptStarted(mode: TelephoneGameMode.samePromptTurns);
      expect(s.totalSteps, 3, reason: 'one turn per player');
      expect(s.activeDrawer!.uid, 'p0');
      expect(s.isAwaitingSubmission('p0'), isTrue);
      expect(s.isAwaitingSubmission('p1'), isFalse, reason: 'not their turn');

      // p1 tries to draw out of turn → ignored.
      final unchanged = s.withSubmission('p1', 'sneaky');
      expect(unchanged, equals(s));

      // p0 draws → turn advances to p1.
      s = s.withSubmission('p0', 'draw-0');
      expect(s.activeDrawer!.uid, 'p1');
      expect(s.step, 1);
    });

    test('sequential turns fill every chain then move to rating', () {
      var s = samePromptStarted(mode: TelephoneGameMode.samePromptTurns);
      s = s.withSubmission('p0', 'd0');
      s = s.withSubmission('p1', 'd1');
      expect(s.isPlaying, isTrue);
      s = s.withSubmission('p2', 'd2');
      expect(s.isRating, isTrue);
      for (var i = 0; i < 3; i++) {
        expect(s.chains[i].single.authorUid, 'p$i');
      }
    });
  });

  group('Rating — rules', () {
    TelephoneSession allDrawn({TelephoneGameMode mode = TelephoneGameMode.samePrompt}) {
      var s = samePromptStarted(mode: mode);
      for (final p in s.players) {
        s = s.withSubmission(p.uid, 'drawing-by-${p.uid}');
      }
      return s; // now in rating phase
    }

    test('a player CANNOT rate their own drawing', () {
      final s = allDrawn();
      final after = s.withRating(raterUid: 'p0', targetUid: 'p0', value: 10);
      expect(after, equals(s), reason: 'self-rating is rejected');
      expect(after.ratingValue('p0', 'p0'), isNull);
    });

    test('ratings outside 1..10 are ignored', () {
      final s = allDrawn();
      expect(s.withRating(raterUid: 'p0', targetUid: 'p1', value: 0),
          equals(s));
      expect(s.withRating(raterUid: 'p0', targetUid: 'p1', value: 11),
          equals(s));
    });

    test('rating only applies during the rating phase', () {
      final playing = samePromptStarted(); // still playing
      expect(
        playing.withRating(raterUid: 'p0', targetUid: 'p1', value: 5),
        equals(playing),
      );
    });

    test('re-rating the same target replaces the previous value', () {
      var s = allDrawn();
      s = s.withRating(raterUid: 'p0', targetUid: 'p1', value: 3);
      s = s.withRating(raterUid: 'p0', targetUid: 'p1', value: 9);
      expect(s.ratingValue('p0', 'p1'), 9);
      expect(
        s.ratings.where((r) => r.raterUid == 'p0' && r.targetUid == 'p1'),
        hasLength(1),
        reason: 'no duplicate rating rows',
      );
    });

    test('nextUnratedTarget walks the remaining players for a rater', () {
      var s = allDrawn();
      expect(s.nextUnratedTarget('p0'), 'p1');
      s = s.withRating(raterUid: 'p0', targetUid: 'p1', value: 5);
      expect(s.nextUnratedTarget('p0'), 'p2');
      s = s.withRating(raterUid: 'p0', targetUid: 'p2', value: 5);
      expect(s.nextUnratedTarget('p0'), isNull);
      expect(s.raterHasFinished('p0'), isTrue);
    });
  });

  group('Results — winner + tally', () {
    TelephoneSession allDrawn() {
      var s = samePromptStarted();
      for (final p in s.players) {
        s = s.withSubmission(p.uid, 'drawing-by-${p.uid}');
      }
      return s;
    }

    test('tallies scores, crowns the top scorer and rolls a running tally', () {
      var s = allDrawn();
      // Everyone loves p1's drawing (10); everyone else gets 1.
      s = rateEveryone(s, (rater, target) => target == 'p1' ? 10 : 1);

      expect(s.isShowingResults, isTrue);
      expect(s.roundScores['p1'], 20, reason: '10 from p0 + 10 from p2');
      expect(s.roundScores['p0'], 2);
      expect(s.roundScores['p2'], 2);

      expect(s.winnerUids, ['p1']);
      expect(s.roundLeaderboard.first.uid, 'p1');

      // Running tally + rounds-won updated exactly once.
      expect(s.tallyPoints['p1'], 20);
      expect(s.tallyPoints['p0'], 2);
      expect(s.roundsWon['p1'], 1);
      expect(s.roundsWon['p0'] ?? 0, 0);
    });

    test('a tie crowns every top scorer', () {
      var s = allDrawn();
      // p0 and p1 both top out; everyone rates the same regardless of target.
      s = rateEveryone(
          s, (rater, target) => target == 'p2' ? 1 : 8);
      expect(s.isShowingResults, isTrue);
      expect(s.winnerUids.toSet(), {'p0', 'p1'});
      expect(s.roundsWon['p0'], 1);
      expect(s.roundsWon['p1'], 1);
    });

    test('works 1-on-1: each rates the other and a winner emerges', () {
      var s = samePromptStarted(n: 2);
      s = s.withSubmission('p0', 'd0');
      s = s.withSubmission('p1', 'd1');
      expect(s.isRating, isTrue);

      s = s.withRating(raterUid: 'p0', targetUid: 'p1', value: 9);
      expect(s.isRating, isTrue, reason: 'still need p1 to rate p0');
      s = s.withRating(raterUid: 'p1', targetUid: 'p0', value: 4);

      expect(s.isShowingResults, isTrue);
      expect(s.winnerUids, ['p1']);
      expect(s.tallyPoints['p1'], 9);
      expect(s.tallyPoints['p0'], 4);
    });
  });

  group('Play again — reset + running tally', () {
    TelephoneSession finishedRound() {
      var s = samePromptStarted();
      for (final p in s.players) {
        s = s.withSubmission(p.uid, 'd-${p.uid}');
      }
      return rateEveryone(s, (rater, target) => target == 'p1' ? 10 : 1);
    }

    test('one tap from results starts a fresh round, carrying the tally', () {
      final results = finishedRound();
      final next = results.playAgain(prompt: 'Draw a dog');

      expect(next.isPlaying, isTrue, reason: 'straight back into play');
      expect(next.roundNumber, 2);
      expect(next.prompt, 'Draw a dog');
      expect(next.chains.every((c) => c.isEmpty), isTrue);
      expect(next.ratings, isEmpty);
      expect(next.submittedUids, isEmpty);

      // Running tally + wins carry across the replay.
      expect(next.tallyPoints['p1'], 20);
      expect(next.roundsWon['p1'], 1);
    });

    test('tally accumulates across repeated rounds', () {
      var s = finishedRound(); // p1: +20
      s = s.playAgain(prompt: 'r2');
      for (final p in s.players) {
        s = s.withSubmission(p.uid, 'd2-${p.uid}');
      }
      s = rateEveryone(s, (rater, target) => target == 'p1' ? 10 : 1);

      expect(s.roundNumber, 2);
      expect(s.tallyPoints['p1'], 40, reason: '20 + 20 across two rounds');
      expect(s.roundsWon['p1'], 2);
    });

    test('play again is a no-op unless at a terminal phase', () {
      final playing = samePromptStarted();
      expect(playing.playAgain(), equals(playing));
    });

    test('classic reveal also supports play again (no rating)', () {
      var s = TelephoneSession.create(
        id: 'c1',
        gameName: 'Classic',
        inviteCode: 'AAA111',
        creatorUid: 'p0',
        creatorName: 'P0',
        createdAt: DateTime(2026, 1, 1),
      ).withPlayerJoined('p1', 'P1').started();
      // 2-player classic: 2 steps (prompt, draw).
      s = s.withSubmission('p0', 'prompt0').withSubmission('p1', 'prompt1');
      s = s.withSubmission('p0', 'draw0').withSubmission('p1', 'draw1');
      expect(s.isRevealing, isTrue);

      final next = s.playAgain();
      expect(next.isPlaying, isTrue);
      expect(next.roundNumber, 2);
      expect(next.prompt, isEmpty, reason: 'classic writes its own prompts');
      expect(next.chains.every((c) => c.isEmpty), isTrue);
    });
  });

  group('Serialization & backward compatibility', () {
    test('round-trips the new fields (mode, prompt, ratings, tally)', () {
      var s = samePromptStarted();
      for (final p in s.players) {
        s = s.withSubmission(p.uid, 'd-${p.uid}');
      }
      s = rateEveryone(s, (rater, target) => target == 'p1' ? 10 : 1);

      final restored = TelephoneSession.fromMap(s.toMap());
      expect(restored, equals(s));
      expect(restored.gameMode, TelephoneGameMode.samePrompt);
      expect(restored.tallyPoints['p1'], 20);
    });

    test('a legacy document (no gameMode/prompt/ratings) defaults to classic',
        () {
      final legacy = {
        'id': 'old1',
        'gameName': 'Legacy',
        'inviteCode': 'OLD123',
        'creatorUid': 'p0',
        'createdAt': DateTime(2025, 1, 1).toIso8601String(),
        'players': [
          {'uid': 'p0', 'displayName': 'P0'},
          {'uid': 'p1', 'displayName': 'P1'},
        ],
        'phase': 'lobby',
        'step': 0,
        'chains': const [],
        'submittedUids': const [],
      };
      final s = TelephoneSession.fromMap(legacy);
      expect(s.gameMode, TelephoneGameMode.classicTelephone);
      expect(s.prompt, isEmpty);
      expect(s.ratings, isEmpty);
      expect(s.roundNumber, 1);
      expect(s.tallyPoints, isEmpty);
    });
  });
}
