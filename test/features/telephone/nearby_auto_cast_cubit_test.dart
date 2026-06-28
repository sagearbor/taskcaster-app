import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/features/telephone/data/datasources/nearby_telephone_transport.dart';
import 'package:taskcaster_app/features/telephone/domain/nearby_cast_label.dart';
import 'package:taskcaster_app/features/telephone/presentation/cubit/nearby_auto_cast_cubit.dart';

/// A fully in-memory [NearbyDiscovery] — no Nearby plugin, no radio. Lets us
/// drive the cubit through every branch and push fake discovery results.
class _FakeDiscovery implements NearbyDiscovery {
  final _controller = StreamController<List<NearbyDevice>>.broadcast();
  bool startResult = true;
  int startCalls = 0;
  int stopCalls = 0;
  int disposeCalls = 0;

  @override
  Stream<List<NearbyDevice>> get discoveredDevices => _controller.stream;

  @override
  Future<bool> startDiscovery(String selfName) async {
    startCalls++;
    return startResult;
  }

  @override
  Future<void> stopDiscovery() async => stopCalls++;

  @override
  Future<void> dispose() async {
    disposeCalls++;
    if (!_controller.isClosed) await _controller.close();
  }

  void emit(List<NearbyDevice> devices) {
    if (!_controller.isClosed) _controller.add(devices);
  }
}

/// Lets a microtask-scheduled stream event reach the cubit's listener.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

NearbyDevice _castDevice(String id, String host) => NearbyDevice(
      id,
      NearbyCastLabel.encode(hostName: host, gameType: NearbyGameType.telephone),
    );

void main() {
  group('gating', () {
    test('does nothing on an unsupported platform', () async {
      var built = 0;
      final cubit = NearbyAutoCastCubit(
        isSupported: () => false,
        transportFactory: () {
          built++;
          return _FakeDiscovery();
        },
        permissionCheck: () async => true,
      );

      await cubit.start();

      expect(cubit.state, const AutoCastIdle(AutoCastIdleReason.unsupported));
      expect(built, 0, reason: 'no transport spun up when unsupported');
      expect(cubit.isActive, isFalse);
      await cubit.close();
    });

    test('stays dormant when permissions are not yet granted (no nag)', () async {
      final cubit = NearbyAutoCastCubit(
        isSupported: () => true,
        transportFactory: _FakeDiscovery.new,
        permissionCheck: () async => false,
      );

      await cubit.start();

      expect(
          cubit.state, const AutoCastIdle(AutoCastIdleReason.permissionsMissing));
      expect(cubit.isActive, isFalse);
      await cubit.close();
    });

    test('goes idle(failed) and disposes the transport if discovery cannot start',
        () async {
      final fake = _FakeDiscovery()..startResult = false;
      final cubit = NearbyAutoCastCubit(
        isSupported: () => true,
        transportFactory: () => fake,
        permissionCheck: () async => true,
      );

      await cubit.start();

      expect(cubit.state, const AutoCastIdle(AutoCastIdleReason.failed));
      expect(fake.disposeCalls, 1);
      expect(cubit.isActive, isFalse);
      await cubit.close();
    });
  });

  group('discovery lifecycle', () {
    late _FakeDiscovery fake;
    late NearbyAutoCastCubit cubit;

    setUp(() {
      fake = _FakeDiscovery();
      cubit = NearbyAutoCastCubit(
        isSupported: () => true,
        transportFactory: () => fake,
        permissionCheck: () async => true,
      );
    });

    tearDown(() => cubit.close());

    test('scans when started and nothing is visible yet', () async {
      await cubit.start();
      expect(cubit.state, const AutoCastScanning());
      expect(cubit.isActive, isTrue);
      expect(fake.startCalls, 1);
    });

    test('surfaces a found host with a decoded, friendly label', () async {
      await cubit.start();

      fake.emit([_castDevice('ep-1', 'Sage')]);
      await _settle();

      final state = cubit.state;
      expect(state, isA<AutoCastGameAvailable>());
      state as AutoCastGameAvailable;
      expect(state.host.endpointId, 'ep-1');
      expect(state.label.hostName, 'Sage');
      expect(state.label.gameType, NearbyGameType.telephone);
      expect(state.endpointName, _castDevice('ep-1', 'Sage').name);
    });

    test('falls back to scanning when the host disappears', () async {
      await cubit.start();
      fake.emit([_castDevice('ep-1', 'Sage')]);
      await _settle();
      expect(cubit.state, isA<AutoCastGameAvailable>());

      fake.emit(const []);
      await _settle();
      expect(cubit.state, const AutoCastScanning());
    });

    test('prefers a real TaskCaster cast over a foreign advertiser', () async {
      await cubit.start();

      fake.emit([
        const NearbyDevice('other', 'some random device'),
        _castDevice('ours', 'Robin'),
      ]);
      await _settle();

      final state = cubit.state as AutoCastGameAvailable;
      expect(state.host.endpointId, 'ours');
      expect(state.label.hostName, 'Robin');
    });

    test('stop() tears the transport down and goes idle', () async {
      await cubit.start();
      await cubit.stop();

      expect(cubit.state, const AutoCastIdle(AutoCastIdleReason.stopped));
      expect(cubit.isActive, isFalse);
      expect(fake.stopCalls, 1);
      expect(fake.disposeCalls, 1);
    });
  });

  group('robustness', () {
    test('a second start() while active is a no-op (one transport only)',
        () async {
      var built = 0;
      final cubit = NearbyAutoCastCubit(
        isSupported: () => true,
        transportFactory: () {
          built++;
          return _FakeDiscovery();
        },
        permissionCheck: () async => true,
      );

      await cubit.start();
      await cubit.start();

      expect(built, 1, reason: 'overlapping starts must not leak transports');
      await cubit.close();
    });

    test('start → stop → start re-discovers with a fresh transport', () async {
      final transports = <_FakeDiscovery>[];
      final cubit = NearbyAutoCastCubit(
        isSupported: () => true,
        transportFactory: () {
          final t = _FakeDiscovery();
          transports.add(t);
          return t;
        },
        permissionCheck: () async => true,
      );

      await cubit.start();
      await cubit.stop();
      await cubit.start();

      expect(transports, hasLength(2));
      expect(transports.first.disposeCalls, 1, reason: 'first one cleaned up');
      expect(cubit.state, const AutoCastScanning());
      await cubit.close();
    });

    test('close() disposes the active transport', () async {
      final fake = _FakeDiscovery();
      final cubit = NearbyAutoCastCubit(
        isSupported: () => true,
        transportFactory: () => fake,
        permissionCheck: () async => true,
      );

      await cubit.start();
      await cubit.close();

      expect(fake.disposeCalls, 1);
    });
  });
}
