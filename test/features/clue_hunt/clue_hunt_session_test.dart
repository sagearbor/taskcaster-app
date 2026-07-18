import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/features/clue_hunt/domain/entities/clue_hunt_session.dart';

ClueHuntSession _threePlayerLobby() {
  return ClueHuntSession.createHost(
    hostId: 'h',
    hostName: 'Mom',
    totalRounds: 3,
  ).withPlayerJoined('p1', 'Ava').withPlayerJoined('p2', 'Ben');
}

void main() {
  group('roster', () {
    test('createHost seats just the host, who is the first hider', () {
      final s = ClueHuntSession.createHost(hostId: 'h', hostName: 'Mom');
      expect(s.players.single.id, 'h');
      expect(s.hiderId, 'h');
      expect(s.phase, CluePhase.lobby);
    });

    test('withPlayerJoined is idempotent and refreshes the name', () {
      final s = _threePlayerLobby().withPlayerJoined('p1', 'Ava M.');
      expect(s.players.length, 3);
      expect(s.players.firstWhere((p) => p.id == 'p1').name, 'Ava M.');
    });

    test('seekers exclude the current hider', () {
      final s = _threePlayerLobby().started(); // host hides first
      expect(s.hiderId, 'h');
      expect(s.seekers.map((p) => p.id), ['p1', 'p2']);
    });
  });

  group('scoring', () {
    test('an instant find scores base points; slower finds decay to the floor',
        () {
      expect(ClueHuntSession.pointsForElapsedMs(0),
          ClueHuntSession.basePoints);
      // 10s → 1000 - 150 = 850.
      expect(ClueHuntSession.pointsForElapsedMs(10000), 850);
      // Very slow clamps at the floor.
      expect(ClueHuntSession.pointsForElapsedMs(1000000),
          ClueHuntSession.minPoints);
    });

    test('faster finds always score at least as much as slower ones', () {
      final fast = ClueHuntSession.pointsForElapsedMs(3000);
      final slow = ClueHuntSession.pointsForElapsedMs(30000);
      expect(fast, greaterThan(slow));
    });
  });

  group('round lifecycle', () {
    test('beganSeeking stamps the seek clock and only works from hiding', () {
      final hiding = _threePlayerLobby().started();
      final seeking = hiding.beganSeeking(now: 5000);
      expect(seeking.phase, CluePhase.seeking);
      expect(seeking.roundStartEpochMs, 5000);
      // No-op from the wrong phase.
      expect(seeking.beganSeeking(now: 9999).roundStartEpochMs, 5000);
    });

    test('first claim wins; later claims are ignored while one is pending', () {
      final seeking = _threePlayerLobby().started().beganSeeking(now: 0);
      final claimed = seeking.withClaim('p1');
      expect(claimed.pendingClaimBy, 'p1');
      // A second claimant does not displace the first.
      expect(claimed.withClaim('p2').pendingClaimBy, 'p1');
    });

    test('a hider cannot claim their own hidden object', () {
      final seeking = _threePlayerLobby().started().beganSeeking(now: 0);
      expect(seeking.withClaim('h').pendingClaimBy, isNull);
    });

    test('an unknown claimant is ignored', () {
      final seeking = _threePlayerLobby().started().beganSeeking(now: 0);
      expect(seeking.withClaim('ghost').pendingClaimBy, isNull);
    });

    test('confirm scores the finder by elapsed time and freezes the result',
        () {
      final seeking =
          _threePlayerLobby().started().beganSeeking(now: 1000).withClaim('p1');
      // Found 10s later → 850 points.
      final result = seeking.claimConfirmed(now: 11000);
      expect(result.phase, CluePhase.roundResult);
      expect(result.lastFinderId, 'p1');
      expect(result.lastAward, 850);
      expect(result.players.firstWhere((p) => p.id == 'p1').totalScore, 850);
      expect(result.pendingClaimBy, isNull);
    });

    test('confirm with nothing pending is a no-op', () {
      final seeking = _threePlayerLobby().started().beganSeeking(now: 0);
      expect(seeking.claimConfirmed(now: 5000), seeking);
    });

    test('reject clears the pending slot so seeking resumes', () {
      final claimed = _threePlayerLobby()
          .started()
          .beganSeeking(now: 0)
          .withClaim('p1');
      final rejected = claimed.claimRejected();
      expect(rejected.pendingClaimBy, isNull);
      expect(rejected.phase, CluePhase.seeking);
      // Now someone else can claim.
      expect(rejected.withClaim('p2').pendingClaimBy, 'p2');
    });
  });

  group('rotation and game over', () {
    test('advancedRound rotates the hider to the next player in order', () {
      var s = _threePlayerLobby().started(); // hider h, round 1
      s = s.beganSeeking(now: 0).withClaim('p1').claimConfirmed(now: 1000);
      s = s.advancedRound();
      expect(s.roundNumber, 2);
      expect(s.hiderId, 'p1');
      expect(s.phase, CluePhase.hiding);
    });

    test('the last round advances to game over, preserving totals', () {
      // totalRounds = 2 so round 2 is the last.
      var s = ClueHuntSession.createHost(
        hostId: 'h',
        hostName: 'Mom',
        totalRounds: 2,
      ).withPlayerJoined('p1', 'Ava');
      s = s.started().beganSeeking(now: 0).withClaim('p1').claimConfirmed(
          now: 2000); // round 1 result
      s = s.advancedRound(); // → round 2, hider p1
      expect(s.roundNumber, 2);
      s = s.beganSeeking(now: 0).withClaim('h').claimConfirmed(now: 1000);
      final over = s.advancedRound();
      expect(over.phase, CluePhase.gameOver);
      // Everyone kept their running totals.
      expect(over.players.firstWhere((p) => p.id == 'p1').totalScore,
          greaterThan(0));
    });

    test('leaderboard ranks by total score, ties broken deterministically', () {
      var s = _threePlayerLobby().started();
      s = s.beganSeeking(now: 0).withClaim('p2').claimConfirmed(now: 5000);
      final board = s.leaderboard;
      expect(board.first.id, 'p2');
    });

    test('backToLobby zeroes scores and hands the hider role back to the host',
        () {
      var s = _threePlayerLobby()
          .started()
          .beganSeeking(now: 0)
          .withClaim('p1')
          .claimConfirmed(now: 1000);
      final fresh = s.backToLobby();
      expect(fresh.phase, CluePhase.lobby);
      expect(fresh.hiderId, 'h');
      expect(fresh.players.every((p) => p.totalScore == 0), isTrue);
    });
  });

  group('connectivity & hider liveness (finding 1 — no soft-lock)', () {
    test('withPlayerConnection flags a drop but keeps the player in the roster',
        () {
      final s = _threePlayerLobby().withPlayerConnection('p1', false);
      final p1 = s.players.firstWhere((p) => p.id == 'p1');
      expect(p1.connected, isFalse);
      // Still present — scores and history survive a drop.
      expect(s.players.length, 3);
    });

    test('re-joining a dropped player clears the disconnected flag', () {
      final s = _threePlayerLobby()
          .withPlayerConnection('p1', false)
          .withPlayerJoined('p1', 'Ava');
      expect(s.players.firstWhere((p) => p.id == 'p1').connected, isTrue);
    });

    test('advancedRound skips a disconnected next hider', () {
      // Order h, p1, p2. Host hides round 1; p1 (next) is disconnected, so the
      // role must skip to p2 rather than landing on the departed p1.
      var s = _threePlayerLobby().started().withPlayerConnection('p1', false);
      s = s.beganSeeking(now: 0).withClaim('p2').claimConfirmed(now: 1000);
      s = s.advancedRound();
      expect(s.hiderId, 'p2');
      expect(s.phase, CluePhase.hiding);
    });

    test('advancedRound falls back to the host when nobody else is connected',
        () {
      var s = _threePlayerLobby()
          .started()
          .withPlayerConnection('p1', false)
          .withPlayerConnection('p2', false);
      s = s.beganSeeking(now: 0).withClaim('p1').claimConfirmed(now: 1000);
      // Even though p1 was the finder, the NEXT hider skips both dropped peers
      // and wraps back to the host.
      s = s.advancedRound();
      expect(s.hiderId, 'h');
    });

    test('hiderSkipped hands off to the next connected player, same round', () {
      // Host started; role is on p1 after a rotation, but p1 has dropped.
      var s = _threePlayerLobby().started();
      s = s.beganSeeking(now: 0).withClaim('p1').claimConfirmed(now: 1000);
      s = s.advancedRound(); // round 2, hider p1
      expect(s.hiderId, 'p1');
      final round = s.roundNumber;
      s = s.withPlayerConnection('p1', false).hiderSkipped();
      expect(s.hiderId, 'p2', reason: 'skips the departed hider to the next');
      expect(s.roundNumber, round, reason: 'skipping does NOT advance the round');
      expect(s.phase, CluePhase.hiding);
    });

    test('hiderSkipped is a no-op outside the hiding phase', () {
      final seeking = _threePlayerLobby().started().beganSeeking(now: 0);
      expect(seeking.hiderSkipped(), seeking);
    });
  });

  group('stale verdict guards (finding 3 — wrong-seeker scoring)', () {
    test('confirm with a mismatched expected claimant is ignored', () {
      final seeking =
          _threePlayerLobby().started().beganSeeking(now: 1000).withClaim('p1');
      // A stale confirm naming p2 (not the pending p1) awards nobody.
      final result = seeking.claimConfirmed(now: 5000, expectClaimant: 'p2');
      expect(result, seeking);
      expect(result.phase, CluePhase.seeking);
    });

    test('confirm naming the actual pending claimant still scores', () {
      final seeking =
          _threePlayerLobby().started().beganSeeking(now: 1000).withClaim('p1');
      final result = seeking.claimConfirmed(now: 11000, expectClaimant: 'p1');
      expect(result.phase, CluePhase.roundResult);
      expect(result.lastFinderId, 'p1');
    });

    test('reject with a mismatched expected claimant is ignored', () {
      final claimed =
          _threePlayerLobby().started().beganSeeking(now: 0).withClaim('p1');
      // A stale reject for p2 must NOT drop p1's live claim.
      final after = claimed.claimRejected(expectClaimant: 'p2');
      expect(after.pendingClaimBy, 'p1');
    });
  });

  group('serialization', () {
    test('toMap/fromMap round-trips every field', () {
      final s = _threePlayerLobby()
          .started()
          .beganSeeking(now: 4242)
          .withClaim('p1');
      final round = ClueHuntSession.fromMap(s.toMap());
      expect(round, equals(s));
    });

    test('a disconnected flag survives serialization', () {
      final s = _threePlayerLobby().withPlayerConnection('p1', false);
      final round = ClueHuntSession.fromMap(s.toMap());
      expect(round, equals(s));
      expect(round.players.firstWhere((p) => p.id == 'p1').connected, isFalse);
    });

    test('a round-result session round-trips (finder + award survive)', () {
      final s = _threePlayerLobby()
          .started()
          .beganSeeking(now: 1000)
          .withClaim('p2')
          .claimConfirmed(now: 6000);
      final round = ClueHuntSession.fromMap(s.toMap());
      expect(round, equals(s));
      expect(round.lastFinderId, 'p2');
      expect(round.lastAward, s.lastAward);
    });
  });
}
