import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// A `VideoPlayerPlatform` that never touches a real decoder, so widget tests
/// can drive `video_player` on the Dart VM.
///
/// This follows the pattern video_player's own test suite uses: swap
/// `VideoPlayerPlatform.instance` for a fake, hand every created player a
/// scripted `initialized` event (or an `error`), then push position updates by
/// hand. Install it with [install] in a `setUp`.
class FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  /// Every data source [create] was asked for, oldest first.
  final List<DataSource> dataSources = [];

  /// Player ids that have been disposed.
  final List<int> disposed = [];

  /// Calls to [play], [pause] and [seekTo], for assertions about looping.
  final List<int> played = [];
  final List<int> paused = [];
  final List<Duration> seeks = [];

  /// Volumes set, newest last. 0 is muted.
  final List<double> volumes = [];

  /// When true, a created player reports an error instead of initializing —
  /// the "this clip won't load" case.
  bool failToInitialize = false;

  /// The duration reported for a successfully created player.
  Duration duration = const Duration(seconds: 12);

  /// The size reported for a successfully created player.
  Size size = const Size(720, 1280);

  int _nextId = 1;
  final Map<int, StreamController<VideoEvent>> _events = {};
  final Map<int, Duration> _positions = {};

  /// Installs this fake as the platform for the current test and restores the
  /// previous one afterwards.
  static FakeVideoPlayerPlatform install() {
    final previous = VideoPlayerPlatform.instance;
    final fake = FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = fake;
    addTearDown(() {
      fake.shutDown();
      VideoPlayerPlatform.instance = previous;
    });
    return fake;
  }

  /// The most recently created player id, or null when nothing was created.
  int? get lastPlayerId => _events.keys.isEmpty ? null : _events.keys.last;

  /// Moves a player's playhead and tells the controller about it.
  void emitPosition(int playerId, Duration position) {
    _positions[playerId] = position;
    _events[playerId]?.add(VideoEvent(
      eventType: VideoEventType.unknown,
      duration: duration,
      size: size,
    ));
  }

  /// Reports that a player reached the end of its source.
  void emitCompleted(int playerId) {
    _positions[playerId] = duration;
    _events[playerId]?.add(
      VideoEvent(eventType: VideoEventType.completed),
    );
  }

  /// Closes every event stream this fake opened. Called for you by [install].
  void shutDown() {
    for (final controller in _events.values) {
      controller.close();
    }
    _events.clear();
  }

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose(int playerId) async {
    disposed.add(playerId);
    await _events.remove(playerId)?.close();
  }

  @override
  Future<int?> create(DataSource dataSource) async {
    dataSources.add(dataSource);
    final id = _nextId++;
    late final StreamController<VideoEvent> controller;
    // VideoPlayerController subscribes to videoEventsFor() only after create()
    // has returned, and the stream is broadcast — so the first event has to
    // wait for that subscription or it is dropped on the floor.
    controller = StreamController<VideoEvent>.broadcast(onListen: () {
      scheduleMicrotask(() {
        if (controller.isClosed) return;
        if (failToInitialize) {
          controller.addError(
            PlatformException(code: 'VideoError', message: 'no clip here'),
          );
          return;
        }
        controller.add(VideoEvent(
          eventType: VideoEventType.initialized,
          duration: duration,
          size: size,
        ));
      });
    });
    _events[id] = controller;
    _positions[id] = Duration.zero;
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) =>
      _events[playerId]?.stream ?? const Stream<VideoEvent>.empty();

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> play(int playerId) async => played.add(playerId);

  @override
  Future<void> pause(int playerId) async => paused.add(playerId);

  @override
  Future<void> setVolume(int playerId, double volume) async =>
      volumes.add(volume);

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    seeks.add(position);
    _positions[playerId] = position;
  }

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<Duration> getPosition(int playerId) async =>
      _positions[playerId] ?? Duration.zero;

  @override
  Widget buildView(int playerId) =>
      ColoredBox(key: ValueKey('fake-video-$playerId'), color: Colors.black);

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<void> setWebOptions(int playerId, VideoPlayerWebOptions options) async {}
}
