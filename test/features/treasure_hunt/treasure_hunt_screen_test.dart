import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:taskcaster_app/core/services/ar/ar_capability_service.dart';
import 'package:taskcaster_app/core/services/ar/ar_engine.dart';
import 'package:taskcaster_app/core/services/sfx/game_sfx.dart';
import 'package:taskcaster_app/features/treasure_hunt/treasure_hunt_screen.dart';

class _FakeEngine implements ArEngine {
  final _planes = StreamController<ArPlane>.broadcast();
  final _taps = StreamController<ArTap>.broadcast();
  int _n = 0;
  ArVector3? pose = const ArVector3(0, 0, 0);

  @override
  Widget buildView() => const ColoredBox(color: Colors.black);
  @override
  Future<void> initSession() async {}
  @override
  Stream<ArPlane> get planes => _planes.stream;
  @override
  Stream<ArTap> get taps => _taps.stream;
  @override
  Future<ArVector3?> cameraPosition() async => pose;
  @override
  Future<ArCameraPose?> cameraPose() async => pose == null
      ? null
      : ArCameraPose(position: pose!, forward: const ArVector3(0, 0, -1));
  @override
  Future<ArNode?> spawnInFrontOfCamera({
    required String modelRef,
    double distance = 1.0,
    double drop = 0.0,
  }) async =>
      ArNode('gem${_n++}');
  @override
  Future<ArNode> spawn({
    required String modelRef,
    required ArVector3 position,
    ArPlane? onPlane,
  }) async =>
      ArNode('n${_n++}');
  @override
  Future<void> move(ArNode node, ArVector3 position) async {}
  @override
  Future<void> remove(ArNode node) async {}
  @override
  Future<void> dispose() async {}
}

class _SupportedCapability implements ArCapabilityService {
  @override
  Future<ArSupport> check() async => ArSupport.supported;
  @override
  Future<bool> requestCamera() async => true;
  @override
  Future<void> openSettings() async {}
}

class _UnsupportedCapability implements ArCapabilityService {
  @override
  Future<ArSupport> check() async => ArSupport.unsupportedPlatform;
  @override
  Future<bool> requestCamera() async => false;
  @override
  Future<void> openSettings() async {}
}

void main() {
  final sl = GetIt.instance;
  late _FakeEngine engine;

  Future<void> register(ArCapabilityService capability) async {
    await sl.reset();
    engine = _FakeEngine();
    sl.registerLazySingleton<ArCapabilityService>(() => capability);
    sl.registerFactory<ArEngine>(() => engine);
    sl.registerLazySingleton<GameSfx>(() => const SilentGameSfx());
  }

  tearDown(() => sl.reset());

  testWidgets('unsupported device shows the fallback view', (tester) async {
    await register(_UnsupportedCapability());
    await tester.pumpWidget(const MaterialApp(home: TreasureHuntScreen()));
    await tester.pumpAndSettle();
    expect(find.text('AR not available here'), findsOneWidget);
    expect(find.text('Skip this task'), findsOneWidget);
  });

  testWidgets('hide → handoff → hunt happy path', (tester) async {
    await register(_SupportedCapability());
    await tester.pumpWidget(const MaterialApp(home: TreasureHuntScreen()));
    await tester.pumpAndSettle();

    // Hide phase.
    expect(find.text('Hide here'), findsOneWidget);
    engine.pose = const ArVector3(0, 0, 0);
    await tester.tap(find.text('Hide here'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1/5 hidden'), findsOneWidget);

    // Move the "seeker" away so the hunt doesn't insta-reveal, then hand off.
    engine.pose = const ArVector3(5, 0, 0);
    await tester.tap(find.text('Done hiding'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Hand the phone to'), findsOneWidget);

    // Tap-to-start → 3-2-1 countdown → hunting.
    await tester.tap(find.textContaining('Tap anywhere to start'));
    await tester.pump(); // enter countdown
    expect(find.text('3'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2200)); // finish countdown
    await tester.pump(); // settle into hunting overlay

    expect(find.text('90s'), findsOneWidget);
    expect(find.textContaining('Follow the ticking'), findsOneWidget);

    // Let a couple of geiger polls run without settling (repeating timers).
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('debug toggle reveals the debug HUD', (tester) async {
    await register(_SupportedCapability());
    await tester.pumpWidget(const MaterialApp(home: TreasureHuntScreen()));
    await tester.pumpAndSettle();

    // Hide one so we can start, then flip debug on (visible during hunt).
    engine.pose = const ArVector3(0, 0, 0);
    await tester.tap(find.text('Hide here'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Debug'));
    await tester.pumpAndSettle();

    engine.pose = const ArVector3(5, 0, 0);
    await tester.tap(find.text('Done hiding'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Tap anywhere to start'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2200));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('track:'), findsOneWidget);
  });
}
