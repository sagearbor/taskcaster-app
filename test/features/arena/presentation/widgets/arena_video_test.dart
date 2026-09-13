import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/features/arena/presentation/widgets/arena_video.dart';
import 'package:taskcaster_app/features/arena/presentation/widgets/countdown_burn.dart';
import 'package:video_player/video_player.dart';

import '../../../../helpers/fake_video_player_platform.dart';

void main() {
  late FakeVideoPlayerPlatform platform;

  setUp(() {
    platform = FakeVideoPlayerPlatform.install();
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 300, height: 375, child: child),
        ),
      ),
    );
    // create() -> initialized event -> setVolume/play -> first frame.
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  testWidgets('plays the clip muted and autoplaying', (tester) async {
    await pump(
      tester,
      const ArenaVideo(url: 'https://cdn.test/clip.mp4', timerSeconds: 30),
    );

    expect(find.byType(VideoPlayer), findsOneWidget);
    expect(platform.dataSources.single.uri, 'https://cdn.test/clip.mp4');
    // Browsers refuse to autoplay with sound, so every clip starts muted.
    expect(platform.volumes.last, 0);
    expect(platform.played, isNotEmpty);
  });

  testWidgets('a source that will not load shows the calm placeholder',
      (tester) async {
    platform.failToInitialize = true;

    await pump(tester, const ArenaVideo(url: 'https://cdn.test/gone.mp4'));

    expect(find.text(ClipUnavailable.message), findsOneWidget);
    expect(find.byType(VideoPlayer), findsNothing);
    // Never an error widget, never a red box.
    expect(tester.takeException(), isNull);
  });

  testWidgets('a null url is the placeholder, not a crash', (tester) async {
    await pump(tester, const ArenaVideo(url: null));
    expect(find.text(ClipUnavailable.message), findsOneWidget);
  });

  testWidgets('a clip that will not load still reports onEnded',
      (tester) async {
    platform.failToInitialize = true;
    var ended = 0;

    await pump(
      tester,
      ArenaVideo(
        url: 'https://cdn.test/gone.mp4',
        loop: false,
        onEnded: () => ended++,
      ),
    );

    // Watch together relies on this: a broken entry must never stall the run.
    expect(ended, 1);
  });

  testWidgets('draws the task countdown over playback', (tester) async {
    await pump(
      tester,
      const ArenaVideo(
        url: 'https://cdn.test/clip.mp4',
        timerSeconds: 30,
        clockOffsetSeconds: 5,
      ),
    );

    expect(find.byType(CountdownBurn), findsOneWidget);
    expect(find.text('0:25'), findsOneWidget);

    platform.emitPosition(platform.lastPlayerId!, const Duration(seconds: 8));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    expect(find.text('0:17'), findsOneWidget);
  });

  testWidgets('a house clip has its clock burned in, so no overlay',
      (tester) async {
    await pump(
      tester,
      const ArenaVideo(
        url: 'https://cdn.test/house.mp4',
        timerSeconds: 30,
        clockOffsetSeconds: 0,
        burnedIn: true,
      ),
    );

    expect(find.byType(CountdownBurn), findsNothing);
    // A position readout is still shown.
    expect(find.textContaining('/'), findsOneWidget);
  });

  testWidgets('currentPositionSeconds follows playback', (tester) async {
    final key = GlobalKey<ArenaVideoState>();
    await pump(tester, ArenaVideo(key: key, url: 'https://cdn.test/clip.mp4'));

    expect(key.currentState!.currentPositionSeconds, 0);

    platform.emitPosition(platform.lastPlayerId!, const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 600));

    expect(key.currentState!.currentPositionSeconds, closeTo(4, 0.01));
  });

  testWidgets('loops back to the start at the cap — the auto-trim',
      (tester) async {
    // A 45 s source is capped to 30 s by VideoPolicy.
    platform.duration = const Duration(seconds: 45);
    final key = GlobalKey<ArenaVideoState>();

    await pump(tester, ArenaVideo(key: key, url: 'https://cdn.test/long.mp4'));
    expect(key.currentState!.capSeconds, 30);

    platform.emitPosition(platform.lastPlayerId!, const Duration(seconds: 31));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    expect(platform.seeks, contains(Duration.zero));
    expect(key.currentState!.currentPositionSeconds, 0);
  });

  testWidgets('with loop off it pauses at the cap and reports onEnded',
      (tester) async {
    platform.duration = const Duration(seconds: 45);
    var ended = 0;

    await pump(
      tester,
      ArenaVideo(
        url: 'https://cdn.test/long.mp4',
        loop: false,
        onEnded: () => ended++,
      ),
    );

    platform.emitPosition(platform.lastPlayerId!, const Duration(seconds: 30));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    expect(ended, 1);
    expect(platform.paused, isNotEmpty);

    // Fires exactly once, however many ticks arrive afterwards.
    platform.emitPosition(platform.lastPlayerId!, const Duration(seconds: 31));
    await tester.pump(const Duration(milliseconds: 600));
    expect(ended, 1);
  });

  testWidgets('a short clip ends when the source runs out', (tester) async {
    platform.duration = const Duration(seconds: 6);
    var ended = 0;

    await pump(
      tester,
      ArenaVideo(
        url: 'https://cdn.test/short.mp4',
        loop: false,
        onEnded: () => ended++,
      ),
    );

    platform.emitCompleted(platform.lastPlayerId!);
    await tester.pump();
    await tester.pump();

    expect(ended, 1);
  });

  testWidgets('tapping the speaker unmutes', (tester) async {
    await pump(tester, const ArenaVideo(url: 'https://cdn.test/clip.mp4'));

    expect(find.byIcon(Icons.volume_off), findsOneWidget);
    await tester.tap(find.byIcon(Icons.volume_off));
    await tester.pump();

    expect(find.byIcon(Icons.volume_up), findsOneWidget);
    expect(platform.volumes.last, 1);
  });

  testWidgets('disposes its controller when it leaves the tree',
      (tester) async {
    await pump(tester, const ArenaVideo(url: 'https://cdn.test/clip.mp4'));
    final id = platform.lastPlayerId!;

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    // VideoPlayerController.dispose() is asynchronous all the way down to the
    // platform, so it needs a real event-loop turn, not just a pump.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));

    expect(platform.disposed, contains(id));
  });
}
