import 'dart:async';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/services/ar/ar_engine.dart';
import 'package:taskcaster_app/core/services/ar/ar_games.dart';
import 'package:taskcaster_app/core/services/ar/ar_minigame_controller.dart';
import 'package:taskcaster_app/features/balloon_blitz/data/bots/blitz_bot.dart';
import 'package:taskcaster_app/features/balloon_blitz/data/datasources/loopback_blitz_transport.dart';
import 'package:taskcaster_app/features/balloon_blitz/data/repositories/balloon_blitz_repository.dart';
import 'package:taskcaster_app/features/balloon_blitz/domain/entities/blitz_session.dart';

/// Proof of "Solo test: race a bot": a REAL host controller + repository on one
/// end of a [LoopbackBlitzTransport] and a [BlitzBot]-driven peer repository on
/// the other, running the exact shared-race protocol with no radio. Everything
/// is real except the transport — which is why this can surface the same timing
/// bugs a second phone would.

/// The same fake engine the shared-race test uses.
class FakeArEngine implements ArEngine {
  final _planes = StreamController<ArPlane>.broadcast();
  final _taps = StreamController<ArTap>.broadcast();
  int _counter = 0;

  final List<String> liveIds = [];

  @override
  Widget buildView() => const SizedBox.shrink();

  @override
  Future<void> initSession() async {}

  @override
  Stream<ArPlane> get planes => _planes.stream;

  @override
  Stream<ArTap> get taps => _taps.stream;

  @override
  Future<ArNode> spawn({
    required String modelRef,
    required ArVector3 position,
    ArPlane? onPlane,
  }) async {
    final id = 'n${_counter++}';
    liveIds.add(id);
    return ArNode(id);
  }

  @override
  Future<void> move(ArNode node, ArVector3 position) async {}

  @override
  Future<void> remove(ArNode node) async {
    liveIds.remove(node.id);
  }

  @override
  Future<ArVector3?> cameraPosition() async => null;

  @override
  Future<ArNode?> spawnInFrontOfCamera({
    required String modelRef,
    double distance = 1.0,
    double drop = 0.0,
  }) async =>
      null;

  @override
  Future<void> dispose() async {}
}

/// Fixed-latency loopback so delivery is deterministic under fakeAsync.
Duration _latency100(Random _) => const Duration(milliseconds: 100);

const _config = ArGameConfig(
  id: 'race',
  title: 'race',
  modelRef: 'balloon.glb',
  objectCount: 3,
  duration: Duration(seconds: 45),
  respawnOnHit: true,
  pointsPerHit: 1,
  speedBonus: false,
  objectLifespan: Duration(seconds: 60),
  scoreByDistance: true,
  bombChance: 0, // keep the bot's payout positive & predictable
  bombPenalty: 3,
  bombModelRef: 'bomb.glb',
);

void main() {
  ({
    BalloonBlitzRepository hostRepo,
    BlitzBot bot,
    FakeArEngine hostEngine,
    ArMinigameController hostCtrl,
  }) boot(FakeAsync async) {
    final (hostT, botT) = LoopbackBlitzTransport.pair(latency: _latency100);
    final hostRepo = BalloonBlitzRepository.host(
      transport: hostT,
      session: BlitzSession.createHost(hostId: 'h', hostName: 'Mom'),
      now: () => 1000,
    );
    final botRepo = BalloonBlitzRepository.peer(
      transport: botT,
      selfId: 'bot',
      selfName: BlitzBot.defaultName,
    );
    // Deterministic bot: reacts every 800ms exactly (span 0).
    final bot = BlitzBot(
      repository: botRepo,
      random: Random(7),
      minReaction: const Duration(milliseconds: 800),
      maxReaction: const Duration(milliseconds: 800),
    )..start();

    // Loopback auto-connects; drain the 100ms handshake + the bot's join.
    async.elapse(const Duration(milliseconds: 300));
    async.flushMicrotasks();

    // Host taps "Start race": lobby → playing, exactly as the session screen
    // does before it mounts the live play view (and its controller).
    hostRepo.startRound();
    async.flushMicrotasks();

    final hostEngine = FakeArEngine();
    final hostCtrl = ArMinigameController(
      engine: hostEngine,
      config: _config,
      race: hostRepo,
    );
    hostCtrl.start();
    async.flushMicrotasks();

    return (
      hostRepo: hostRepo,
      bot: bot,
      hostEngine: hostEngine,
      hostCtrl: hostCtrl,
    );
  }

  test('the loopback delivers both directions, but only after its delay', () {
    fakeAsync((async) {
      final (a, b) = LoopbackBlitzTransport.pair(
        latency: _latency100,
        autoConnect: false,
      );
      final fromA = <Map<String, dynamic>>[];
      final fromB = <Map<String, dynamic>>[];
      a.onMessage = (_, m) => fromB.add(m); // a receives what b sent
      b.onMessage = (_, m) => fromA.add(m);

      a.sendToEndpoint('peer-endpoint', {'k': 'ping', 'n': 1});
      b.sendToEndpoint('host-endpoint', {'k': 'pong', 'n': 2});
      async.flushMicrotasks();
      expect(fromA, isEmpty, reason: 'delivery is delayed, not synchronous');
      expect(fromB, isEmpty);

      async.elapse(const Duration(milliseconds: 100));
      expect(fromA.single['k'], 'ping');
      expect(fromB.single['k'], 'pong');

      a.dispose();
      b.dispose();
    });
  });

  test('the bot auto-joins the host lobby over the loopback', () {
    fakeAsync((async) {
      final (hostT, botT) =
          LoopbackBlitzTransport.pair(latency: _latency100);
      final hostRepo = BalloonBlitzRepository.host(
        transport: hostT,
        session: BlitzSession.createHost(hostId: 'h', hostName: 'Mom'),
        now: () => 1000,
      );
      final botRepo = BalloonBlitzRepository.peer(
        transport: botT,
        selfId: 'bot',
        selfName: BlitzBot.defaultName,
      );
      final bot = BlitzBot(repository: botRepo, random: Random(1))..start();

      async.elapse(const Duration(milliseconds: 300));
      async.flushMicrotasks();

      final roster = hostRepo.current!.players;
      expect(roster.map((p) => p.id), containsAll(<String>['h', 'bot']));
      expect(
        roster.firstWhere((p) => p.id == 'bot').name,
        BlitzBot.defaultName,
      );

      bot.dispose();
      hostRepo.dispose();
    });
  });

  test('after GO the bot pops shared balloons and climbs the host leaderboard',
      () {
    fakeAsync((async) {
      final r = boot(async);

      // Fallback (2s) → announceGo → 3-2-1 pre-roll (2.7s) → GO spawns the set.
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 2800));
      async.flushMicrotasks();

      // The host published a full shared set; the bot mirrors it and, on its
      // reaction cadence, claims pops that the host adjudicates and scores.
      async.elapse(const Duration(seconds: 8));
      async.flushMicrotasks();

      final botOnHost =
          r.hostRepo.current!.players.firstWhere((p) => p.id == 'bot');
      expect(botOnHost.liveScore, greaterThan(0),
          reason: "the bot's claims must reach the host's ledger");
      // The host never taps, so the bot leads.
      expect(r.hostRepo.current!.leaderboard.first.id, 'bot');
      expect(r.bot.isRacing, isTrue);

      r.hostCtrl.dispose();
      r.bot.dispose();
      r.hostRepo.dispose();
    });
  });

  test('the bot stops racing when the round reaches results', () {
    fakeAsync((async) {
      final r = boot(async);
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 2800));
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 5));
      async.flushMicrotasks();
      expect(r.bot.isRacing, isTrue);

      // Round starts at now()=1000ms wall clock; the authoritative time-up flips
      // everyone to results. Elapse well past the 45s round.
      async.elapse(const Duration(seconds: 60));
      async.flushMicrotasks();

      expect(r.hostRepo.current!.phase, BlitzPhase.results);
      expect(r.bot.isRacing, isFalse,
          reason: 'the bot downs tools at results');

      r.hostCtrl.dispose();
      r.bot.dispose();
      r.hostRepo.dispose();
    });
  });

  test('disposing everything leaves no dangling timers', () {
    fakeAsync((async) {
      final r = boot(async);
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 2800));
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 6));
      async.flushMicrotasks();

      r.hostCtrl.dispose();
      r.bot.dispose();
      r.hostRepo.dispose();

      // Let any in-flight loopback deliveries fire (they early-return once
      // disposed) so nothing is left pending.
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();

      expect(async.periodicTimerCount, 0, reason: 'no leaked periodic timers');
      expect(async.nonPeriodicTimerCount, 0,
          reason: 'no leaked one-shot timers');
    });
  });
}
