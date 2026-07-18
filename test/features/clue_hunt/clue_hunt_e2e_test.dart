import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/features/clue_hunt/data/datasources/loopback_clue_hunt_transport.dart';
import 'package:taskcaster_app/features/clue_hunt/data/repositories/clue_hunt_repository.dart';
import 'package:taskcaster_app/features/clue_hunt/domain/entities/clue_hunt_session.dart';

/// Two-phone end-to-end over a real [LoopbackClueHuntTransport]: a genuine host
/// repository and a genuine seeker repository running the whole wire protocol
/// with no radio. Everything is real except the transport — so this surfaces the
/// same timing behaviour (delayed delivery, snapshot heals, throttled heat) a
/// second phone would.

/// Fixed-latency loopback so delivery is deterministic under fakeAsync.
Duration _latency100(Random _) => const Duration(milliseconds: 100);

/// Drain a few link round-trips worth of delayed delivery.
void _settle(FakeAsync async, [int ms = 400]) {
  async.elapse(Duration(milliseconds: ms));
  async.flushMicrotasks();
}

void main() {
  test('host + seeker: join, heat propagates, found → confirm → score → rotate',
      () {
    fakeAsync((async) {
      final (hostT, seekerT) =
          LoopbackClueHuntTransport.pair(latency: _latency100);

      var hostClock = 1000;
      final host = ClueHuntRepository.host(
        transport: hostT,
        session: ClueHuntSession.createHost(hostId: 'h', hostName: 'Mom'),
        now: () => hostClock,
      );
      final seeker = ClueHuntRepository.seeker(
        transport: seekerT,
        selfId: 'seek',
        selfName: 'Ava',
      );

      // ---- join: the loopback auto-connects and the seeker announces itself --
      _settle(async);
      expect(host.current!.players.map((p) => p.id),
          containsAll(<String>['h', 'seek']));

      // The seeker mirrored the host's lobby.
      expect(seeker.current, isNotNull);
      expect(seeker.current!.phase, CluePhase.lobby);

      // ---- host starts the game; host hides first --------------------------
      host.startGame();
      _settle(async);
      expect(seeker.current!.phase, CluePhase.hiding);
      expect(seeker.current!.hiderId, 'h');
      expect(seeker.isHider, isFalse);

      // ---- host (the hider) begins the hunt at t=1000 ----------------------
      hostClock = 1000;
      host.beginSeeking();
      _settle(async);
      expect(seeker.current!.phase, CluePhase.seeking);

      // ---- host drives the warmer/colder meter; the seeker receives heat ---
      final seekerHeats = <double>[];
      final heatSub = seeker.watchHeat().listen(seekerHeats.add);
      host.setHeat(0.85);
      _settle(async);
      expect(seekerHeats.last, closeTo(0.85, 1e-9),
          reason: 'the hider heat reaches the seeker phone');

      // ---- the seeker physically grabs it and claims -----------------------
      seeker.claimFound();
      _settle(async);
      expect(host.current!.pendingClaimBy, 'seek',
          reason: "the seeker's claim reaches the host's pending slot");

      // ---- the hider confirms 5s in → the seeker is scored -----------------
      hostClock = 6000; // 5s after the seek started
      host.confirmFind();
      _settle(async);
      expect(host.current!.phase, CluePhase.roundResult);
      final award = ClueHuntSession.pointsForElapsedMs(5000);
      expect(host.current!.players.firstWhere((p) => p.id == 'seek').totalScore,
          award);
      // The seeker phone shows the same result and score.
      expect(seeker.current!.phase, CluePhase.roundResult);
      expect(
          seeker.current!.players.firstWhere((p) => p.id == 'seek').totalScore,
          award);
      expect(seeker.current!.lastFinderId, 'seek');

      // ---- rotate: next round, the seeker becomes the hider ----------------
      host.nextRound();
      _settle(async);
      expect(host.current!.hiderId, 'seek');
      expect(seeker.current!.phase, CluePhase.hiding);
      expect(seeker.isHider, isTrue,
          reason: 'the role rotates to the seeker on the next round');

      heatSub.cancel();
      host.dispose();
      seeker.dispose();
      // Let any in-flight deliveries drain (they early-return once disposed).
      _settle(async);
      expect(async.periodicTimerCount, 0);
      expect(async.nonPeriodicTimerCount, 0);
    });
  });

  test('a seeker whose first join send is DROPPED still lands in the roster '
      '(finding 4 — retry heals a lost join)', () {
    fakeAsync((async) {
      final (hostT, seekerT) =
          LoopbackClueHuntTransport.pair(latency: _latency100);
      // Fail the seeker's FIRST join send (simulate a dropped radio send); let
      // everything after through so the retry succeeds.
      var dropped = false;
      seekerT.failSend = (msg) {
        if (msg['k'] == 'join' && !dropped) {
          dropped = true;
          return true;
        }
        return false;
      };

      final host = ClueHuntRepository.host(
        transport: hostT,
        session: ClueHuntSession.createHost(hostId: 'h', hostName: 'Mom'),
        now: () => 1000,
      );
      final seeker = ClueHuntRepository.seeker(
        transport: seekerT,
        selfId: 'seek',
        selfName: 'Ava',
      );

      // Link-up + first (dropped) join + backoff + retry + delivery.
      _settle(async, 1500);
      expect(dropped, isTrue, reason: 'the first join send was dropped');
      expect(host.current!.players.any((p) => p.id == 'seek'), isTrue,
          reason: 'the retry heals the dropped first join');

      host.dispose();
      seeker.dispose();
      _settle(async);
    });
  });

  test('a game with totalRounds=1 ends at game over after the first find', () {
    fakeAsync((async) {
      final (hostT, seekerT) =
          LoopbackClueHuntTransport.pair(latency: _latency100);
      var hostClock = 1000;
      final host = ClueHuntRepository.host(
        transport: hostT,
        session: ClueHuntSession.createHost(
            hostId: 'h', hostName: 'Mom', totalRounds: 1),
        now: () => hostClock,
      );
      final seeker = ClueHuntRepository.seeker(
        transport: seekerT,
        selfId: 'seek',
        selfName: 'Ava',
      );
      _settle(async);

      host.startGame();
      host.beginSeeking();
      _settle(async);
      seeker.claimFound();
      _settle(async);
      hostClock = 4000;
      host.confirmFind();
      _settle(async);
      host.nextRound(); // the only round is done → game over
      _settle(async);

      expect(host.current!.phase, CluePhase.gameOver);
      expect(seeker.current!.phase, CluePhase.gameOver);
      expect(seeker.current!.leaderboard.first.id, 'seek');

      host.dispose();
      seeker.dispose();
      _settle(async);
    });
  });
}
