import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/models/submission.dart';
import 'package:taskcaster_app/features/arena/domain/models/feed_post.dart';
import 'package:taskcaster_app/features/arena/presentation/widgets/arena_video.dart';
import 'package:taskcaster_app/features/arena/presentation/widgets/countdown_burn.dart';
import 'package:taskcaster_app/features/arena/presentation/widgets/post_card.dart';
import 'package:video_player/video_player.dart';

import '../../../../helpers/fake_video_player_platform.dart';

FeedPost videoPost({
  bool isHouse = false,
  int? timerSeconds = 30,
  int? clockOffsetSeconds = 0,
  String? url = 'https://cdn.test/clip.mp4',
  String? playbackUrl,
  String? posterUrl,
}) {
  return FeedPost(
    id: 'p1',
    gameId: 'game-1',
    taskId: 'starter-01',
    taskTitle: 'Egg on a spoon, to the far wall and back',
    rubric: 'Distance covered before disaster.',
    userId: 'user-1',
    displayName: 'Sophie',
    mediaType: SubmissionMediaType.video,
    videoUrl: url,
    playbackUrl: playbackUrl,
    posterUrl: posterUrl,
    videoStoragePath: 'submissions/user-1/20260912/0',
    timerSeconds: timerSeconds,
    clockOffsetSeconds: clockOffsetSeconds,
    caption: 'Nature documentary · Done in 22 s',
    stamp: 'NO REGRETS',
    isHouse: isHouse,
    createdAt: DateTime.utc(2026, 9, 12),
  );
}

FeedPost textPost() => FeedPost(
      id: 'p2',
      gameId: 'game-1',
      taskId: 'starter-03',
      taskTitle: 'Rename a household object',
      userId: 'user-2',
      displayName: 'Kit',
      mediaType: SubmissionMediaType.text,
      text: 'The lamp is now The Understudy.',
      createdAt: DateTime.utc(2026, 9, 12),
    );

void main() {
  late FakeVideoPlayerPlatform platform;

  setUp(() {
    platform = FakeVideoPlayerPlatform.install();
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  testWidgets('a video post renders a player in the 4:5 media box',
      (tester) async {
    await pump(tester, PostCard(post: videoPost()));

    expect(find.byType(ArenaVideo), findsOneWidget);
    expect(find.byType(VideoPlayer), findsOneWidget);
    // The existing card chrome is untouched.
    expect(find.text('Sophie'), findsOneWidget);
    expect(find.text('Nature documentary · Done in 22 s'), findsOneWidget);
  });

  testWidgets('WP-08: a transcoded post plays playbackUrl, with its poster',
      (tester) async {
    await pump(
      tester,
      PostCard(
        post: videoPost(
          url: 'https://cdn.test/original.mov',
          playbackUrl: 'https://cdn.test/transcoded.mp4',
          posterUrl: 'https://cdn.test/poster.jpg',
        ),
      ),
    );
    final video = tester.widget<ArenaVideo>(find.byType(ArenaVideo));
    expect(video.url, 'https://cdn.test/transcoded.mp4');
    expect(video.posterUrl, 'https://cdn.test/poster.jpg');
    expect(platform.dataSources.single.uri, 'https://cdn.test/transcoded.mp4');
  });

  testWidgets('WP-08: an old post without playbackUrl still plays videoUrl',
      (tester) async {
    await pump(tester, PostCard(post: videoPost()));
    final video = tester.widget<ArenaVideo>(find.byType(ArenaVideo));
    expect(video.url, 'https://cdn.test/clip.mp4');
    expect(video.posterUrl, isNull);
    expect(platform.dataSources.single.uri, 'https://cdn.test/clip.mp4');
  });

  testWidgets('the countdown is drawn over a player clip', (tester) async {
    await pump(tester, PostCard(post: videoPost(clockOffsetSeconds: 12)));
    expect(find.byType(CountdownBurn), findsOneWidget);
    expect(find.text('0:18'), findsOneWidget);
  });

  testWidgets('a house clip gets no overlay — it is burned in', (tester) async {
    await pump(tester, PostCard(post: videoPost(isHouse: true)));
    expect(find.byType(CountdownBurn), findsNothing);
  });

  testWidgets(
      'WP-3: a house clip shows one label and one clock — no HOUSE chip, '
      'no position pill', (tester) async {
    await pump(tester, PostCard(post: videoPost(isHouse: true)));
    expect(find.text('HOUSE'), findsNothing);
    // The "0:03 / 0:07" readout is gone: the clip's burned-in clock is it.
    expect(find.textContaining(' / '), findsNothing);
  });

  testWidgets('WP-3: a player clip with no timer keeps its position pill',
      (tester) async {
    await pump(tester, PostCard(post: videoPost(timerSeconds: null)));
    expect(find.byType(CountdownBurn), findsNothing);
    expect(find.textContaining(' / '), findsOneWidget);
  });

  testWidgets('WP-3: never an ART stamp on a clip', (tester) async {
    await pump(
      tester,
      PostCard(post: videoPost(isHouse: true).copyWith(stamp: 'ART')),
    );
    expect(find.text('ART'), findsNothing);
  });

  testWidgets('WP-3: other stamps still show on a clip', (tester) async {
    await pump(tester, PostCard(post: videoPost()));
    expect(find.text('NO REGRETS'), findsOneWidget);
  });

  testWidgets('a clip that will not load shows the calm placeholder',
      (tester) async {
    platform.failToInitialize = true;
    await pump(tester, PostCard(post: videoPost()));

    expect(find.text(ClipUnavailable.message), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tap on a clip reports the second it landed on',
      (tester) async {
    int? reported;
    var taps = 0;
    await pump(
      tester,
      PostCard(
        post: videoPost(),
        onTap: (atSecond) {
          taps++;
          reported = atSecond;
        },
      ),
    );

    platform.emitPosition(platform.lastPlayerId!, const Duration(seconds: 7));
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.byType(ArenaVideo));
    await tester.pump();

    expect(taps, 1);
    expect(reported, 7);
    // The funny-tap burst still fires over a clip.
    expect(find.text('\u{1F525}'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('a tap on a text post reports no second', (tester) async {
    int? reported = 99;
    await pump(
      tester,
      PostCard(post: textPost(), onTap: (atSecond) => reported = atSecond),
    );

    await tester.tap(find.byType(PostCard));
    await tester.pump();

    expect(reported, isNull);
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('loopVideo/onVideoEnded reach the player', (tester) async {
    platform.duration = const Duration(seconds: 5);
    var ended = 0;

    await pump(
      tester,
      PostCard(
        post: videoPost(),
        loopVideo: false,
        onVideoEnded: () => ended++,
      ),
    );

    platform.emitCompleted(platform.lastPlayerId!);
    await tester.pump();
    await tester.pump();

    expect(ended, 1);
  });
}
