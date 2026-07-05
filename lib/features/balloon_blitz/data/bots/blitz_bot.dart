import 'dart:async';
import 'dart:math';

import '../../../../core/services/ar/ar_race.dart';
import '../../domain/entities/blitz_session.dart';
import '../repositories/balloon_blitz_repository.dart';

/// A simulated opponent for "Solo test: race a bot".
///
/// It drives a real [BalloonBlitzRepository.peer] on the far end of a
/// [LoopbackBlitzTransport], so from the host's point of view it is
/// indistinguishable from a second phone: it joins the lobby, mirrors the shared
/// balloon set, and sends genuine pop claims that the host adjudicates and scores
/// onto the real leaderboard.
///
/// Behaviour after GO:
///  * It tracks the live shared objects (and which are bombs) from the
///    authority's spawn / popped / escaped / snapshot events.
///  * It claims a pop every ~1.5–3.5 s (human-ish reaction time).
///  * It prefers real balloons but tags a bomb about [bombHitChance] of the time
///    — it KNOWS which are bombs from the spawn descriptors, so this is a
///    deliberate "oops", not blind tapping.
///  * It stops the moment the round leaves the playing phase (results / lobby).
///
/// Everything random flows through the injected [Random], so a seeded bot plays
/// an identical game every time — which is what makes the solo-mode tests
/// deterministic under `fakeAsync`.
class BlitzBot {
  /// The default rival name, shared with the peer repository so the roster,
  /// leaderboard and rival-pop flyouts all agree on who the bot is.
  static const String defaultName = 'Robo Rival 🤖';

  BlitzBot({
    required this.repository,
    Random? random,
    this.name = defaultName,
    double bombHitChance = 0.15,
    Duration minReaction = const Duration(milliseconds: 1500),
    Duration maxReaction = const Duration(milliseconds: 3500),
  })  : assert(maxReaction >= minReaction),
        _random = random ?? Random(),
        _bombHitChance = bombHitChance,
        _minReactionMs = minReaction.inMilliseconds,
        _reactionSpanMs =
            (maxReaction - minReaction).inMilliseconds;

  /// The peer repository the bot plays through. The bot owns its lifecycle and
  /// disposes it (and therefore its loopback endpoint) in [dispose].
  final BalloonBlitzRepository repository;

  /// The rival's display name, shown in the lobby, leaderboard and rival-pop
  /// flyouts on the host's screen.
  final String name;

  final Random _random;
  final double _bombHitChance;
  final int _minReactionMs;
  final int _reactionSpanMs;

  /// Live shared objects the bot could tap: logical race id → isBomb.
  final Map<String, bool> _liveIsBomb = {};

  StreamSubscription<ArRaceEvent>? _raceSub;
  StreamSubscription<BlitzSession?>? _sessionSub;
  Timer? _attemptTimer;

  bool _started = false;
  bool _racing = false;
  bool _disposed = false;

  /// True while the bot is actively claiming pops (between GO and results).
  bool get isRacing => _racing;

  /// Begin observing the race. The peer repository announces its `join` to the
  /// host automatically when the loopback link comes up, so this is all that is
  /// needed to seat the bot in the lobby and have it race when the host hits GO.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    _raceSub = repository.events.listen(_onRaceEvent);
    _sessionSub = repository.watchSession().listen(_onSession);
  }

  void _onSession(BlitzSession? session) {
    if (session == null || _disposed) return;
    // The authority flipped us out of the round (results, or back to lobby):
    // down tools until the next GO.
    if (_racing && session.phase != BlitzPhase.playing) {
      _stopRacing();
    }
  }

  void _onRaceEvent(ArRaceEvent event) {
    if (_disposed) return;
    switch (event.type) {
      case ArRaceEventType.go:
        _startRacing();
        break;
      case ArRaceEventType.spawn:
        final object = event.object;
        if (object != null) _liveIsBomb[object.id] = object.isBomb;
        break;
      case ArRaceEventType.pop:
      case ArRaceEventType.escape:
        final id = event.objectId;
        if (id != null) _liveIsBomb.remove(id);
        break;
      case ArRaceEventType.snapshot:
        // Heal drift: the snapshot is the authoritative live set.
        _liveIsBomb
          ..clear()
          ..addEntries(
              event.objects.map((o) => MapEntry(o.id, o.isBomb)));
        break;
      case ArRaceEventType.popClaim:
        // Authority-only; a peer bot never receives these.
        break;
    }
  }

  void _startRacing() {
    if (_racing || _disposed) return;
    _racing = true;
    _scheduleAttempt();
  }

  void _scheduleAttempt() {
    _attemptTimer?.cancel();
    final jitter =
        _reactionSpanMs == 0 ? 0 : _random.nextInt(_reactionSpanMs + 1);
    _attemptTimer = Timer(
      Duration(milliseconds: _minReactionMs + jitter),
      _attempt,
    );
  }

  void _attempt() {
    if (!_racing || _disposed) return;
    _tryPop();
    if (_racing) _scheduleAttempt(); // keep tapping until the round ends
  }

  void _tryPop() {
    if (_liveIsBomb.isEmpty) return; // nothing on screen yet — wait for spawns
    final bombs = <String>[];
    final safe = <String>[];
    _liveIsBomb.forEach((id, isBomb) => (isBomb ? bombs : safe).add(id));

    // Aim for a bomb only occasionally, and only if one is actually live.
    final aimBomb = bombs.isNotEmpty && _random.nextDouble() < _bombHitChance;
    var pool = aimBomb ? bombs : safe;
    if (pool.isEmpty) pool = aimBomb ? safe : bombs; // whatever is left
    if (pool.isEmpty) return;

    final target = pool[_random.nextInt(pool.length)];
    // Optimistic: the balloon is gone either way (our claim wins or another
    // player's already did), so don't try to claim it twice.
    _liveIsBomb.remove(target);
    repository.claimPop(target);
  }

  void _stopRacing() {
    _racing = false;
    _attemptTimer?.cancel();
    _attemptTimer = null;
  }

  /// Tear the bot down: stop the attempt timer, drop the subscriptions and
  /// dispose the underlying peer repository (which closes its loopback endpoint).
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _stopRacing();
    await _raceSub?.cancel();
    await _sessionSub?.cancel();
    await repository.dispose();
  }
}
