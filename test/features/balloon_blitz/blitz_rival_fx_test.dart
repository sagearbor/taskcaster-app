import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:taskcaster_app/core/services/ar/ar_engine.dart';
import 'package:taskcaster_app/core/services/ar/ar_race.dart';
import 'package:taskcaster_app/core/services/sfx/game_sfx.dart';
import 'package:taskcaster_app/core/widgets/ar_fx.dart';
import 'package:taskcaster_app/features/balloon_blitz/presentation/widgets/blitz_play_view.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

/// Widget-level proof of the positioned rival-pop FX in Balloon Blitz:
/// when a rival pops a balloon and the camera matrices are available, the view
/// projects the balloon's LOCAL world position to screen and burns a
/// [FlameBurst] there; when projection is unavailable (tracking lost) or
/// impossible (balloon behind the camera), it falls back to the legacy
/// amber-flash + toast exactly as before.

class _FakeEngine implements ArEngine {
  final _planes = StreamController<ArPlane>.broadcast();
  final _taps = StreamController<ArTap>.broadcast();
  int _n = 0;
  final List<String> liveIds = [];

  /// Configurable camera matrices; null = the "tracking lost" signal.
  ArCameraProjection? projection;

  @override
  Widget buildView() => const ColoredBox(color: Colors.black);
  @override
  Future<void> initSession() async {}
  @override
  Stream<ArPlane> get planes => _planes.stream;
  @override
  Stream<ArTap> get taps => _taps.stream;
  @override
  Future<ArVector3?> cameraPosition() async => null;
  @override
  Future<ArCameraProjection?> cameraProjection() async => projection;

  @override
  Future<ArCameraPose?> cameraPose() async => null;
  @override
  Future<ArNode> spawn({
    required String modelRef,
    required ArVector3 position,
    ArPlane? onPlane,
  }) async {
    final id = 'n${_n++}';
    liveIds.add(id);
    return ArNode(id);
  }

  @override
  Future<void> move(ArNode node, ArVector3 position) async {}
  @override
  Future<void> remove(ArNode node) async => liveIds.remove(node.id);
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

/// A scriptable race seam: the test IS the authority and injects events
/// straight into the mirror-side controller under test.
class _FakeRace implements ArRaceSync {
  final _events = StreamController<ArRaceEvent>.broadcast();

  @override
  bool get isAuthority => false;
  @override
  String get selfPlayerId => 'me';
  @override
  Stream<ArRaceEvent> get events => _events.stream;
  @override
  void announceGo() {}
  @override
  void publishSpawn(ArRaceObject object) {}
  @override
  void publishPop({
    required String objectId,
    required String playerId,
    required int value,
    required bool isBomb,
  }) {}
  @override
  void publishEscape(String objectId) {}
  @override
  void publishSnapshot(List<ArRaceObject> objects) {}
  @override
  void claimPop(String objectId) {}
  @override
  String playerName(String playerId) => playerId == 'rival' ? 'Dad' : playerId;

  void emit(ArRaceEvent e) => _events.add(e);
}

/// fovY 90°, aspect 1 perspective (f = 1): for an eye-space point (x, y, z),
/// ndc = (x/-z, y/-z) — hand-checkable, same matrix as ar_projection_test.
vm.Matrix4 _proj90() {
  const near = 0.01;
  const far = 100.0;
  const a = (far + near) / (near - far);
  const b = 2 * far * near / (near - far);
  return vm.Matrix4(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, a, -1, 0, 0, b, 0);
}

void main() {
  final sl = GetIt.instance;
  late _FakeEngine engine;
  late _FakeRace race;

  setUp(() async {
    await sl.reset();
    engine = _FakeEngine();
    race = _FakeRace();
    sl.registerFactory<ArEngine>(() => engine);
    sl.registerLazySingleton<GameSfx>(() => const SilentGameSfx());
  });

  tearDown(() => sl.reset());

  /// Boots a mirror-side BlitzPlayView through GO, then has 'rival' (Dad) pop
  /// a shared balloon whose LOCAL position is [worldZ] metres along z.
  Future<void> bootAndRivalPop(WidgetTester tester, {double worldZ = -2}) async {
    await tester.pumpWidget(MaterialApp(
      home: BlitzPlayView(onFinished: () {}, race: race),
    ));
    await tester.pump();

    // Authority announces GO → synchronized 3-2-1 pre-roll (3 × 900 ms).
    race.emit(const ArRaceEvent(ArRaceEventType.go));
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 900));
    }

    // The shared balloon arrives; the mirror places it at its LOCAL position.
    // phase 0 & zero-duration pumps from here on ⇒ age stays 0, so the live
    // position is exactly base + (sin(0)*0.1, 0, cos(0)*0.05) = (0,0,z+0.05).
    race.emit(ArRaceEvent(
      ArRaceEventType.spawn,
      object: ArRaceObject(
        id: 'r0',
        position: ArVector3(0, 0, worldZ),
        modelRef: 'assets/ar/balloon_red.glb',
        value: 3,
        isBomb: false,
        phase: 0,
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(engine.liveIds, isNotEmpty, reason: 'mirror spawned the balloon');

    // Dad pops it (adjudicated by the authority) → rivalPop on this phone.
    race.emit(const ArRaceEvent(
      ArRaceEventType.pop,
      objectId: 'r0',
      playerId: 'rival',
      value: 3,
    ));
    await tester.pump(); // controller handles pop → view awaits projection
    await tester.pump(); // projection future completes → setState
    await tester.pump(); // flame/toast frame
  }

  testWidgets(
      'rival pop WITH projectable position burns a FlameBurst at the '
      'projected screen point (no toast, no flash)', (tester) async {
    // Identity view (camera at origin looking down -z) + fovY-90/aspect-1
    // projection: the balloon straight ahead projects to the screen CENTER.
    engine.projection = ArCameraProjection(
      view: vm.Matrix4.identity(),
      proj: _proj90(),
    );

    await bootAndRivalPop(tester);

    final flameFinder = find.byType(FlameBurst);
    expect(flameFinder, findsOneWidget);
    final flame = tester.widget<FlameBurst>(flameFinder);
    // Default test surface is 800×600 logical: center = (400, 300). The live
    // position (0,0,-1.95) is dead ahead → ndc (0,0) → exact center.
    expect(flame.center.dx, closeTo(400, 1e-6));
    expect(flame.center.dy, closeTo(300, 1e-6));
    expect(flame.label, '🔥 Dad +3');
    // The positioned path must NOT also fire the legacy toast.
    expect(find.byType(ArToast), findsNothing);

    // Let the one-shot finish, then unmount to cancel game timers.
    await tester.pump(const Duration(milliseconds: 950));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'rival pop with NULL projection (tracking lost) falls back to the '
      'legacy toast + flash', (tester) async {
    engine.projection = null; // tracking lost

    await bootAndRivalPop(tester);

    expect(find.byType(FlameBurst), findsNothing);
    expect(find.byType(ArToast), findsOneWidget);
    expect(find.textContaining('Dad'), findsOneWidget);
    expect(find.textContaining('+3'), findsOneWidget);

    // Drain the toast (1100 ms) + rival flash (350 ms) timers, then unmount.
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'rival pop of a balloon BEHIND the camera falls back to the toast even '
      'though matrices are available', (tester) async {
    engine.projection = ArCameraProjection(
      view: vm.Matrix4.identity(),
      proj: _proj90(),
    );

    // +z is behind a camera that looks down -z → worldToScreen returns null.
    await bootAndRivalPop(tester, worldZ: 2);

    expect(find.byType(FlameBurst), findsNothing);
    expect(find.byType(ArToast), findsOneWidget);
    expect(find.textContaining('Dad'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
