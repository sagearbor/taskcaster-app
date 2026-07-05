import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/models/telephone_session.dart';
import 'package:taskcaster_app/core/utils/friendly_errors.dart';
import 'package:taskcaster_app/features/telephone/data/datasources/nearby_telephone_transport.dart';
import 'package:taskcaster_app/features/telephone/data/repositories/nearby_telephone_repository.dart';

/// In-memory [NearbyTelephoneTransport] that never touches the Nearby plugin.
/// Two instances can be [linkedTo] each other to form a fake radio link, so a
/// host repository and a peer repository can play a real game in a unit test —
/// the same pattern as `balloon_blitz_repository_test.dart`.
class FakeNearbyTransport extends NearbyTelephoneTransport {
  FakeNearbyTransport(this.selfEndpointId) : super(serviceId: 'test-service');

  /// The endpoint id the OTHER side sees our messages arrive from.
  final String selfEndpointId;

  /// The transport on the other end of the fake radio link.
  FakeNearbyTransport? linkedTo;

  /// When true every send throws — a radio failure mid-connection.
  bool failSends = false;

  final Set<String> _fakeConnected = {};
  final List<Map<String, dynamic>> sentMessages = [];

  @override
  Set<String> get connectedEndpoints => Set.unmodifiable(_fakeConnected);

  @override
  bool get hasConnection => _fakeConnected.isNotEmpty;

  @override
  Future<bool> startAdvertising(String advertisedName) async => true;

  @override
  Future<void> stopAdvertising() async {}

  @override
  Future<bool> startDiscovery(String selfName) async => true;

  @override
  Future<void> stopDiscovery() async {}

  @override
  Future<bool> connect(String endpointId) async => true;

  @override
  Future<void> sendToEndpoint(
      String endpointId, Map<String, dynamic> message) async {
    if (endpointId.isEmpty) {
      // Mirror the hardened real transport: refuse loudly, never hang.
      throw StateError('Not connected — no endpoint to send to.');
    }
    if (failSends) throw Exception('simulated radio failure');
    sentMessages.add(message);
    // Deliver through a JSON round-trip, exactly like the real wire does.
    final wire =
        Map<String, dynamic>.from(jsonDecode(jsonEncode(message)) as Map);
    linkedTo?.onMessage?.call(selfEndpointId, wire);
  }

  @override
  Future<void> broadcast(Map<String, dynamic> message) async {
    for (final id in _fakeConnected.toList()) {
      try {
        await sendToEndpoint(id, message);
      } catch (_) {
        // Real transport skips dead peers on broadcast too.
      }
    }
  }

  @override
  Future<void> dispose() async {}

  // ---- test helpers --------------------------------------------------------

  void simulateConnected(String endpointId) {
    _fakeConnected.add(endpointId);
    onEndpointConnected?.call(endpointId);
  }

  void simulateDisconnected(String endpointId) {
    _fakeConnected.remove(endpointId);
    onEndpointDisconnected?.call(endpointId);
  }
}

/// Let queued microtasks (message delivery, stream emissions) run.
Future<void> pump() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeNearbyTransport hostTransport;
  late FakeNearbyTransport peerTransport;
  late NearbyTelephoneRepository host;
  late NearbyTelephoneRepository peer;
  TelephoneSession? hostLatest;
  TelephoneSession? peerLatest;

  setUp(() {
    hostTransport = FakeNearbyTransport('host-ep');
    peerTransport = FakeNearbyTransport('peer-ep');
    hostTransport.linkedTo = peerTransport;
    peerTransport.linkedTo = hostTransport;

    host = NearbyTelephoneRepository.host(
      transport: hostTransport,
      session: TelephoneSession.create(
        id: 'game-1',
        gameName: 'Drawing Telephone',
        inviteCode: 'ABCD',
        creatorUid: 'host-uid',
        creatorName: 'Host',
        createdAt: DateTime(2026, 1, 1),
      ),
    );
    peer = NearbyTelephoneRepository.peer(
      transport: peerTransport,
      selfUid: 'peer-uid',
      selfName: 'Pat',
    );

    hostLatest = null;
    peerLatest = null;
    host.watchSession('game-1').listen((s) => hostLatest = s);
    peer.watchSession('game-1').listen((s) => peerLatest = s);
  });

  tearDown(() async {
    await host.dispose();
    await peer.dispose();
  });

  /// Complete the Nearby handshake on both sides: the host pushes the lobby
  /// to the fresh peer, the peer announces itself and gets rostered.
  Future<void> connectPair() async {
    hostTransport.simulateConnected('peer-ep');
    peerTransport.simulateConnected('host-ep');
    await pump();
  }

  group('host ↔ peer over a fake transport pair', () {
    test('join handshake rosters the peer and syncs the lobby both ways',
        () async {
      await connectPair();

      expect(hostLatest!.players.map((p) => p.uid),
          containsAll(['host-uid', 'peer-uid']));
      expect(peerLatest, isNotNull,
          reason: 'the peer must receive the authoritative session');
      expect(peerLatest!.players.map((p) => p.uid),
          containsAll(['host-uid', 'peer-uid']));
    });

    test('peer submit reaches the host, host state updates and re-broadcasts',
        () async {
      await connectPair();
      await host.startGame('game-1');
      await pump();
      expect(peerLatest!.isPlaying, isTrue);

      // Step 0 of the classic chain: everyone writes a prompt.
      await peer.submitEntry(
        sessionId: 'game-1',
        uid: 'peer-uid',
        content: 'a cat riding a bike',
      );
      await pump();

      expect(hostLatest!.hasSubmittedCurrentStep('peer-uid'), isTrue,
          reason: "the peer's submission must land in the host session");
      final peerChain = hostLatest!.chains[
          hostLatest!.orderIndexOf('peer-uid')]; // own chain at step 0
      expect(peerChain.single.content, 'a cat riding a bike');
      // …and the peer sees its own submission come back authoritatively.
      expect(peerLatest!.hasSubmittedCurrentStep('peer-uid'), isTrue);
    });

    test('host advancing the step is received by the peer', () async {
      await connectPair();
      await host.startGame('game-1');
      // Both players submit their prompt → step advances to 1 (drawing).
      await peer.submitEntry(
          sessionId: 'game-1', uid: 'peer-uid', content: 'peer prompt');
      await host.submitEntry(
          sessionId: 'game-1', uid: 'host-uid', content: 'host prompt');
      await pump();

      expect(hostLatest!.step, 1);
      expect(peerLatest!.step, 1,
          reason: 'the peer must follow the host into the drawing step');
      expect(peerLatest!.currentEntryType, TelephoneEntryType.drawing);
    });
  });

  group('peer submit resilience (the "Submit did nothing" bug)', () {
    test('submit with no connection throws player-ready copy, never hangs',
        () async {
      // No connectPair(): the peer never completed (or lost) its connection.
      await expectLater(
        peer.submitEntry(
            sessionId: 'game-1', uid: 'peer-uid', content: 'a cat'),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', FriendlyErrors.nearbyHostLost)),
      );
    });

    test('submit after the host link drops mid-game throws, never hangs',
        () async {
      await connectPair();
      await host.startGame('game-1');
      peerTransport.simulateDisconnected('host-ep');

      await expectLater(
        peer.submitEntry(
            sessionId: 'game-1', uid: 'peer-uid', content: 'a cat'),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', FriendlyErrors.nearbyHostLost)),
      );
    });

    test('a failed radio send surfaces the retry copy instead of hanging',
        () async {
      await connectPair();
      await host.startGame('game-1');
      peerTransport.failSends = true;

      await expectLater(
        peer.submitEntry(
            sessionId: 'game-1', uid: 'peer-uid', content: 'a cat'),
        throwsA(isA<StateError>().having((e) => e.message, 'message',
            FriendlyErrors.nearbyHostUnreachable)),
      );
    });

    test('rating and play-again sends fail loudly too', () async {
      await expectLater(
        peer.submitRating(
            sessionId: 'game-1', raterUid: 'peer-uid', targetUid: 'host-uid',
            value: 7),
        throwsA(isA<StateError>()),
      );
      await expectLater(peer.playAgain('game-1'), throwsA(isA<StateError>()));
    });
  });
}
