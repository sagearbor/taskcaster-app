import 'ar_engine.dart';

/// The multiplayer seam for a SHARED AR tap-race (Balloon Blitz today, any
/// future anchor-point versus game tomorrow).
///
/// One device is the AUTHORITY (the offline host): its [ArMinigameController]
/// runs the real game logic — spawn positions, bomb rolls, lifespans, scoring —
/// and publishes each event through this interface. Every other device mirrors:
/// it spawns/removes the SAME logical objects (same ids, same base positions,
/// same wiggle phase) in its OWN AR coordinate frame, so the whole family races
/// for one shared balloon set. Positions are never streamed — the rise/wiggle
/// animation is a pure function of (base, phase, age), so each phone animates
/// deterministically and only discrete events cross the radio.
///
/// Pop adjudication is first-claim-wins on the authority. Non-authority taps
/// remove the balloon optimistically (it is gone either way — either my claim
/// wins or someone else's already did); scores always come from the authority.
abstract class ArRaceSync {
  /// True on the device that runs the real game logic (the host).
  bool get isAuthority;

  /// This device's player id (matches the session roster).
  String get selfPlayerId;

  /// Remote race events to apply locally (spawns/removals for mirrors, pop
  /// claims + GO signal for everyone).
  Stream<ArRaceEvent> get events;

  /// AUTHORITY: surface found and ready — tells every phone (including the
  /// caller, via [events]) to run the synchronized 3-2-1-GO now.
  void announceGo();

  /// AUTHORITY: a logical object joined the shared set.
  void publishSpawn(ArRaceObject object);

  /// AUTHORITY: [objectId] was popped by [playerId] (already adjudicated).
  void publishPop({
    required String objectId,
    required String playerId,
    required int value,
    required bool isBomb,
  });

  /// AUTHORITY: [objectId] aged out and escaped.
  void publishEscape(String objectId);

  /// AUTHORITY: periodic full-set snapshot (ids + positions + ages) so mirrors
  /// heal dropped messages and pause-induced age drift.
  void publishSnapshot(List<ArRaceObject> objects);

  /// NON-AUTHORITY: ask the authority to score my tap on [objectId].
  void claimPop(String objectId);

  /// Display name for a player id (for "🔥 Dad +3" flyouts).
  String playerName(String playerId);
}

/// A logical shared object: everything a mirror needs to render and animate it
/// identically (in its own coordinate frame).
class ArRaceObject {
  final String id; // logical id, NOT the local engine node id
  final ArVector3 position;
  final String modelRef;
  final int value;
  final bool isBomb;
  final double phase;

  /// Seconds the object had already lived when this descriptor was built —
  /// zero for fresh spawns, >0 in resync snapshots.
  final double age;

  const ArRaceObject({
    required this.id,
    required this.position,
    required this.modelRef,
    required this.value,
    required this.isBomb,
    required this.phase,
    this.age = 0,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'x': position.x,
        'y': position.y,
        'z': position.z,
        'm': modelRef,
        'v': value,
        'b': isBomb,
        'p': phase,
        'a': age,
      };

  static ArRaceObject fromMap(Map<String, dynamic> m) => ArRaceObject(
        id: m['id'] as String,
        position: ArVector3(
          (m['x'] as num).toDouble(),
          (m['y'] as num).toDouble(),
          (m['z'] as num).toDouble(),
        ),
        modelRef: m['m'] as String,
        value: (m['v'] as num?)?.toInt() ?? 1,
        isBomb: m['b'] as bool? ?? false,
        phase: (m['p'] as num?)?.toDouble() ?? 0,
        age: (m['a'] as num?)?.toDouble() ?? 0,
      );
}

enum ArRaceEventType {
  /// Run the synchronized 3-2-1-GO now (sent by the authority to everyone).
  go,

  /// Mirror: add this object to the local scene.
  spawn,

  /// Everyone: [objectId] is gone, popped by [playerId] for [value] points.
  pop,

  /// Mirror: [objectId] escaped.
  escape,

  /// Authority: a mirror claims a tap on [objectId].
  popClaim,

  /// Mirror: authoritative full object set (heals drops/late joins).
  snapshot,
}

class ArRaceEvent {
  final ArRaceEventType type;
  final String? objectId;
  final String? playerId;
  final int value;
  final bool isBomb;
  final ArRaceObject? object;
  final List<ArRaceObject> objects;

  const ArRaceEvent(
    this.type, {
    this.objectId,
    this.playerId,
    this.value = 0,
    this.isBomb = false,
    this.object,
    this.objects = const [],
  });
}
