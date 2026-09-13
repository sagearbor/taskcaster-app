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

  testWidgets('the countdown is drawn over a player clip', (tester) async {
    await pump(tester, PostCard(post: videoPost(clockOffsetSeconds: 12)));
    expect(find.byType(CountdownBurn), findsOneWidget);
    expect(find.text('0:18'), findsOneWidget);
  });

  testWidgets('a house clip gets no overlay — it is burned in',
      (tester) async {
    await pump(tester, PostCard(post: videoPost(isHouse: true)));
    expect(find.byType(CountdownBurn), findsNothing);
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
