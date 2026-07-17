import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:taskcaster_app/core/services/ar/ar_capability_service.dart';
import 'package:taskcaster_app/core/services/ar/ar_engine.dart';
import 'package:taskcaster_app/core/services/sfx/game_sfx.dart';
import 'package:taskcaster_app/features/tower_trials/tower_trials_screen.dart';

class _FakeEngine implements ArEngine {
  final _planes = StreamController<ArPlane>.broadcast();
  final _taps = StreamController<ArTap>.broadcast();
  int _n = 0;

  ArVector3? pose = const ArVector3(0, 0, 0);
  ArCameraPose? cameraPoseValue;

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
  Future<ArCameraPose?> cameraPose() async => cameraPoseValue;

  @override
  Future<ArCameraProjection?> cameraProjection() async => null;
  @override
  Future<ArNode?> spawnInFrontOfCamera({
    required String modelRef,
    double distance = 1.0,
    double drop = 0.0,
  }) async =>
      ArNode('f${_n++}');
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
    await tester.pumpWidget(const MaterialApp(home: TowerTrialsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('AR not available here'), findsOneWidget);
    expect(find.text('Skip this task'), findsOneWidget);
  });

  testWidgets('setup → handoff → aim → PERFECT drop → next handoff',
      (tester) async {
    await register(_SupportedCapability());
    await tester.pumpWidget(const MaterialApp(home: TowerTrialsScreen()));
    await tester.pumpAndSettle();

    // Start card with two default players.
    expect(find.text('Tower Trials'), findsOneWidget);
    expect(find.text('Start stacking'), findsOneWidget);
    await tester.tap(find.text('Start stacking'));
    await tester.pump();
    await tester.pump(); // base + ghost spawn microtasks

    // Handoff card for player 1.
    expect(find.textContaining('Hand the phone to Player 1'), findsOneWidget);
    await tester.tap(find.textContaining('Tap anywhere to build'));
    await tester.pump();

    // Aiming HUD: stability meter, drop button (disabled — no aim yet).
    expect(find.text('Stability'), findsOneWidget);
    expect(find.text('DROP 🧱'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'DROP 🧱'))
          .onPressed,
      isNull,
      reason: 'camera not aimed at the tower yet',
    );
    expect(find.textContaining('Point your camera'), findsOneWidget);

    // Aim dead-centre at the landing spot: base is at (0, -0.55, -1.1), so
    // the next block lands centred on (0, -0.30, -1.1).
    final len = sqrt(0.3 * 0.3 + 1.1 * 1.1);
    engine.cameraPoseValue = ArCameraPose(
      position: const ArVector3(0, 0, 0),
      forward: ArVector3(0, -0.3 / len, -1.1 / len),
    );
    await tester.pump(const Duration(milliseconds: 250)); // aim poll ticks
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'DROP 🧱'))
          .onPressed,
      isNotNull,
    );

    // Drop: dead-centre → PERFECT flash, then the pass-the-phone card.
    await tester.tap(find.text('DROP 🧱'));
    await tester.pump();
    expect(find.text('✨ PERFECT! ✨'), findsOneWidget);
    expect(find.textContaining('Hand the phone to Player 2'), findsOneWidget);
    expect(find.textContaining('1 block up'), findsOneWidget);

    // Let the one-shot FX (burst + flash + GO) finish cleanly.
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('losing the aim disables the drop again', (tester) async {
    await register(_SupportedCapability());
    await tester.pumpWidget(const MaterialApp(home: TowerTrialsScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start stacking'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.textContaining('Tap anywhere to build'));
    await tester.pump();

    final len = sqrt(0.3 * 0.3 + 1.1 * 1.1);
    engine.cameraPoseValue = ArCameraPose(
      position: const ArVector3(0, 0, 0),
      forward: ArVector3(0, -0.3 / len, -1.1 / len),
    );
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'DROP 🧱'))
          .onPressed,
      isNotNull,
    );

    // Camera swings up to the ceiling — no landing-plane intersection.
    engine.cameraPoseValue = const ArCameraPose(
      position: ArVector3(0, 0, 0),
      forward: ArVector3(0, 0.9, -0.44),
    );
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'DROP 🧱'))
          .onPressed,
      isNull,
    );
    expect(find.textContaining('Point your camera'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1)); // GO flash finishes
  });
}
