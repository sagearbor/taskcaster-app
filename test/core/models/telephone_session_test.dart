import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/models/session_mode.dart';
import 'package:taskcaster_app/core/models/telephone_session.dart';

/// Build a started 3-player session: p0 (creator), p1, p2.
TelephoneSession startedThreePlayer() {
  return TelephoneSession.create(
    id: 's1',
    gameName: 'Test',
    inviteCode: 'ABC123',
    creatorUid: 'p0',
    creatorName: 'P0',
    createdAt: DateTime(2026, 1, 1),
  )
      .withPlayerJoined('p1', 'P1')
      .withPlayerJoined('p2', 'P2')
      .started();
}

/// Every player submits the current step (in player order). Returns the new
/// session after the step has fully resolved.
TelephoneSession submitWholeStep(
    TelephoneSession s, String Function(String uid, int chainIdx) content) {
  final step = s.step;
  for (final p in s.players) {
    final chainIdx = s.assignedChainForUid(p.uid)!;
    s = s.withSubmission(p.uid, content(p.uid, chainIdx));
    // Step should not advance until the LAST player submits.
    if (p.uid != s.players.last.uid && step == s.step) {
      // still same step — expected for all but the last submitter
    }
  }
  return s;
}

void main() {
  group('TelephoneSession — defaults & serialization', () {
    test('new session is a party-mode lobby with just the creator', () {
      final s = TelephoneSession.create(
        id: 's1',
        gameName: 'Game',
        inviteCode: 'CODE12',
        creatorUid: 'p0',
        creatorName: 'P0',
      );
      expect(s.mode, SessionMode.party);
      expect(s.phase, TelephonePhase.lobby);
      expect(s.players.single.uid, 'p0');
      expect(s.isInLobby, isTrue);
    });

    test('round-trips through toMap/fromMap', () {
      final s = startedThreePlayer();
      final restored = TelephoneSession.fromMap(s.toMap());
      expect(restored, equals(s));
    });
  });

  group('TelephoneSession — chain assignment', () {
    test('expectedTypeForStep follows prompt → draw → guess → draw …', () {
      expect(TelephoneSession.expectedTypeForStep(0), TelephoneEntryType.prompt);
      expect(TelephoneSession.expectedTypeForStep(1), TelephoneEntryType.drawing);
      expect(TelephoneSession.expectedTypeForStep(2), TelephoneEntryType.guess);
      expect(TelephoneSession.expectedTypeForStep(3), TelephoneEntryType.drawing);
      expect(TelephoneSession.expectedTypeForStep(4), TelephoneEntryType.guess);
    });

    test('players never work on their own chain after step 0', () {
      final s = startedThreePlayer();
      final n = s.playerCount;
      // Step 0: each player is on their own chain.
      for (var p = 0; p < n; p++) {
        expect(s.chainIndexForPlayer(p, 0), p);
      }
      // Later steps: a player's chain rotates and is never their own.
      for (var step = 1; step < n; step++) {
        for (var p = 0; p < n; p++) {
          expect(s.chainIndexForPlayer(p, step), isNot(p));
        }
      }
    });

    test('each chain gets exactly one entry per distinct player', () {
      final s = startedThreePlayer();
      final n = s.playerCount;
      // For each step, the mapping player→chain is a permutation (bijection).
      for (var step = 0; step < n; step++) {
        final chains = <int>{};
        for (var p = 0; p < n; p++) {
          chains.add(s.chainIndexForPlayer(p, step));
        }
        expect(chains.length, n, reason: 'step $step must cover all chains');
      }
    });
  });

  group('TelephoneSession — phase gating', () {
    test('step advances ONLY after every player submits', () {
      var s = startedThreePlayer();
      expect(s.step, 0);

      s = s.withSubmission('p0', 'prompt0');
      expect(s.step, 0, reason: 'one of three submitted');
      expect(s.submittedUids, ['p0']);

      s = s.withSubmission('p1', 'prompt1');
      expect(s.step, 0, reason: 'two of three submitted');

      s = s.withSubmission('p2', 'prompt2');
      expect(s.step, 1, reason: 'all submitted → advance');
      expect(s.submittedUids, isEmpty, reason: 'submitted set resets');
    });

    test('re-submitting the same step is ignored (idempotent)', () {
      var s = startedThreePlayer();
      s = s.withSubmission('p0', 'prompt0');
      final again = s.withSubmission('p0', 'prompt0-dup');
      expect(again.submittedUids, ['p0']);
      expect(again.chains[0].length, 1);
    });

    test('a non-player submission is ignored', () {
      var s = startedThreePlayer();
      final after = s.withSubmission('stranger', 'x');
      expect(after, equals(s));
    });
  });

  group('TelephoneSession — full game & reveal assembly', () {
    test('3-player game ends in reveal with correctly-authored chains', () {
      var s = startedThreePlayer();

      // Step 0: prompts. content encodes the chain it lands on.
      s = submitWholeStep(s, (uid, chainIdx) => 'prompt-by-$uid');
      expect(s.step, 1);
      // Step 1: drawings.
      s = submitWholeStep(s, (uid, chainIdx) => 'drawing-by-$uid');
      expect(s.step, 2);
      // Step 2: guesses.
      s = submitWholeStep(s, (uid, chainIdx) => 'guess-by-$uid');

      // After the final step the game flips to reveal.
      expect(s.phase, TelephonePhase.reveal);
      expect(s.step, 3);

      // Every chain has exactly N entries, one per distinct author, in the
      // order prompt → drawing → guess, authored by players[(c+s) % N].
      final order = ['p0', 'p1', 'p2'];
      for (var c = 0; c < s.chains.length; c++) {
        final chain = s.chains[c];
        expect(chain.length, 3);
        expect(chain[0].type, TelephoneEntryType.prompt);
        expect(chain[1].type, TelephoneEntryType.drawing);
        expect(chain[2].type, TelephoneEntryType.guess);
        for (var step = 0; step < 3; step++) {
          final expectedAuthor = order[(c + step) % 3];
          expect(chain[step].authorUid, expectedAuthor,
              reason: 'chain $c step $step author');
        }
      }
    });

    test('promptEntryForUid hands a player the previous link to react to', () {
      var s = startedThreePlayer();
      // Step 0 (prompt) shows nothing to react to.
      expect(s.promptEntryForUid('p0'), isNull);

      s = submitWholeStep(s, (uid, _) => 'prompt-by-$uid');
      // Step 1: p1 should draw chain 0 → p0's prompt.
      expect(s.assignedChainForUid('p1'), 0);
      expect(s.promptEntryForUid('p1')!.content, 'prompt-by-p0');

      s = submitWholeStep(s, (uid, _) => 'drawing-by-$uid');
      // Step 2: p2 guesses chain 0 → the step-1 drawing on chain 0 (p1's).
      expect(s.assignedChainForUid('p2'), 0);
      expect(s.promptEntryForUid('p2')!.content, 'drawing-by-p1');
      expect(s.promptEntryForUid('p2')!.type, TelephoneEntryType.drawing);
    });
  });

  group('TelephoneSession — host kick (withPlayerRemoved)', () {
    TelephoneSession threePlayerLobby() => TelephoneSession.create(
          id: 's1',
          gameName: 'Test',
          inviteCode: 'ABC123',
          creatorUid: 'p0',
          creatorName: 'P0',
          createdAt: DateTime(2026, 1, 1),
        ).withPlayerJoined('p1', 'P1').withPlayerJoined('p2', 'P2');

    test('removes a non-host player from the lobby roster', () {
      final s = threePlayerLobby();
      final after = s.withPlayerRemoved('p1');
      expect(after.playerCount, 2);
      expect(after.hasPlayer('p1'), isFalse);
      expect(after.hasPlayer('p0'), isTrue);
      expect(after.hasPlayer('p2'), isTrue);
    });

    test('cannot remove the creator (host)', () {
      final s = threePlayerLobby();
      expect(s.withPlayerRemoved('p0').playerCount, 3);
    });

    test('removing an absent uid is a no-op', () {
      final s = threePlayerLobby();
      expect(s.withPlayerRemoved('ghost'), equals(s));
    });

    test('cannot remove once the game has started', () {
      final s = threePlayerLobby().started();
      expect(s.withPlayerRemoved('p1'), equals(s));
    });
  });

  group('TelephoneSession — start guards', () {
    test('cannot start with fewer than 2 players', () {
      final s = TelephoneSession.create(
        id: 's',
        gameName: 'g',
        inviteCode: 'CODE12',
        creatorUid: 'p0',
        creatorName: 'P0',
      );
      expect(s.started, throwsStateError);
    });

    test('starting is idempotent once playing', () {
      final s = startedThreePlayer();
      expect(s.started(), equals(s));
    });

    test('joining is blocked once not in lobby and dedupes uids', () {
      var s = startedThreePlayer();
      // Already playing → join is a no-op.
      expect(s.withPlayerJoined('p9', 'P9').playerCount, 3);

      var lobby = TelephoneSession.create(
        id: 's',
        gameName: 'g',
        inviteCode: 'CODE12',
        creatorUid: 'p0',
        creatorName: 'P0',
      );
      lobby = lobby.withPlayerJoined('p0', 'dup');
      expect(lobby.playerCount, 1, reason: 'duplicate uid not added');
    });
  });

  group('TelephoneSession — classic chain by player count (2/3/4)', () {
    TelephoneSession startedWithPlayers(int n) {
      var s = TelephoneSession.create(
        id: 's-n$n',
        gameName: 'Test',
        inviteCode: 'CODE12',
        creatorUid: 'p0',
        creatorName: 'P0',
        createdAt: DateTime(2026, 1, 1),
      );
      for (var i = 1; i < n; i++) {
        s = s.withPlayerJoined('p$i', 'P$i');
      }
      return s.started();
    }

    /// Plays a whole classic game to the reveal and returns the final session.
    TelephoneSession playToReveal(TelephoneSession s) {
      var guard = 0;
      while (s.isPlaying && guard++ < 20) {
        for (final p in [...s.players]) {
          if (s.isAwaitingSubmission(p.uid)) {
            s = s.withSubmission(p.uid, 'c-${p.uid}-s${s.step}');
          }
        }
      }
      return s;
    }

    List<TelephoneEntryType> typesOf(List<TelephoneEntry> chain) =>
        chain.map((e) => e.type).toList();

    test('2 players: prompt → drawing, then reveal (no guess step)', () {
      final s = playToReveal(startedWithPlayers(2));
      expect(s.phase, TelephonePhase.reveal,
          reason: '2-player classic must still reach a reveal');
      for (final chain in s.chains) {
        expect(typesOf(chain),
            [TelephoneEntryType.prompt, TelephoneEntryType.drawing],
            reason: 'with 2 players the game ends after one drawing — '
                'this is why the mode picker says "best with 3+"');
        // Two distinct authors: writer then drawer.
        expect(chain.map((e) => e.authorUid).toSet().length, 2);
      }
    });

    test('3 players: prompt → drawing → guess alternation', () {
      final s = playToReveal(startedWithPlayers(3));
      expect(s.phase, TelephonePhase.reveal);
      for (final chain in s.chains) {
        expect(typesOf(chain), [
          TelephoneEntryType.prompt,
          TelephoneEntryType.drawing,
          TelephoneEntryType.guess,
        ]);
        expect(chain.map((e) => e.authorUid).toSet().length, 3,
            reason: 'every entry in a chain comes from a distinct player');
      }
    });

    test('4 players: prompt → drawing → guess → drawing alternation', () {
      final s = playToReveal(startedWithPlayers(4));
      expect(s.phase, TelephonePhase.reveal);
      for (final chain in s.chains) {
        expect(typesOf(chain), [
          TelephoneEntryType.prompt,
          TelephoneEntryType.drawing,
          TelephoneEntryType.guess,
          TelephoneEntryType.drawing,
        ]);
        expect(chain.map((e) => e.authorUid).toSet().length, 4);
      }
    });
  });
}
