import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:taskcaster_app/core/di/service_locator.dart';
import 'package:taskcaster_app/core/models/submission.dart';
import 'package:taskcaster_app/features/arena/data/repositories/mock_montage_repository.dart';
import 'package:taskcaster_app/features/arena/domain/models/feed_post.dart';
import 'package:taskcaster_app/features/arena/domain/models/montage.dart';
import 'package:taskcaster_app/features/arena/domain/repositories/feed_repository.dart';
import 'package:taskcaster_app/features/arena/domain/repositories/montage_repository.dart';
import 'package:taskcaster_app/features/arena/presentation/screens/watch_together_screen.dart';
import 'package:taskcaster_app/features/arena/presentation/widgets/arena_video.dart';

import '../../../../helpers/fake_video_player_platform.dart';

class MockFeedRepository extends Mock implements FeedRepository {}

FeedPost clipPost(String id, String name) => FeedPost(
      id: id,
      gameId: 'game-1',
      taskId: 'starter-01',
      taskTitle: 'Egg on a spoon, to the far wall and back',
      userId: 'user-$id',
      displayName: name,
      mediaType: SubmissionMediaType.video,
      videoUrl: 'https://cdn.test/$id.mp4',
      timerSeconds: 30,
      clockOffsetSeconds: 0,
      caption: 'Done in 12 s',
      createdAt: DateTime.utc(2026, 9, 12),
    );

FeedPost textPost(String id, String name) => FeedPost(
      id: id,
      gameId: 'game-1',
      taskId: 'starter-01',
      taskTitle: 'Egg on a spoon, to the far wall and back',
      userId: 'user-$id',
      displayName: name,
      mediaType: SubmissionMediaType.text,
      text: 'A very sad potato.',
      createdAt: DateTime.utc(2026, 9, 12),
    );

void main() {
  late MockFeedRepository feedRepository;
  late MockMontageRepository montageRepository;
  late StreamController<List<FeedPost>> posts;
  late FakeVideoPlayerPlatform platform;

  setUp(() async {
    await sl.reset();
    platform = FakeVideoPlayerPlatform.install();
    feedRepository = MockFeedRepository();
    montageRepository = MockMontageRepository();
    sl.registerLazySingleton<FeedRepository>(() => feedRepository);
    sl.registerLazySingleton<MontageRepository>(() => montageRepository);

    posts = StreamController<List<FeedPost>>.broadcast();
    when(() => feedRepository.watchPostsForTask(
          gameId: any(named: 'gameId'),
          taskId: any(named: 'taskId'),
        )).thenAnswer((_) => posts.stream);
    when(() => feedRepository.tapPost(
          any(),
          taps: any(named: 'taps'),
          atSecond: any(named: 'atSecond'),
        )).thenAnswer((_) async {});
  });

  tearDown(() async {
    await posts.close();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: WatchTogetherScreen(
          gameId: 'game-1',
          taskId: 'starter-01',
          taskTitle: 'Egg on a spoon, to the far wall and back',
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a clip entry plays and advances when it ends, not after 6 s',
      (tester) async {
    await pumpScreen(tester);
    posts.add([clipPost('p1', 'Greg'), clipPost('p2', 'Sophie')]);
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.byType(ArenaVideo), findsOneWidget);
    expect(find.text('Greg'), findsOneWidget);

    // Six seconds of slideshow beat must NOT move a clip along.
    await tester.pump(const Duration(seconds: 7));
    expect(find.text('Greg'), findsOneWidget);

    // Reaching the end of the clip does.
    platform.emitCompleted(platform.lastPlayerId!);
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('Sophie'), findsOneWidget);
  });

  testWidgets('a clip that cannot load advances instead of stalling',
      (tester) async {
    platform.failToInitialize = true;
    await pumpScreen(tester);
    posts.add([clipPost('p1', 'Greg'), textPost('p2', 'Sophie')]);
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('Sophie'), findsOneWidget);
  });

  testWidgets('a text entry still runs on the fixed 6 s beat', (tester) async {
    await pumpScreen(tester);
    posts.add([textPost('p1', 'Greg'), textPost('p2', 'Sophie')]);
    await tester.pump();

    expect(find.text('Greg'), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
    expect(find.text('Sophie'), findsOneWidget);
  });

  testWidgets('with no montage the run ends on the results card',
      (tester) async {
    await pumpScreen(tester);
    posts.add([textPost('p1', 'Greg')]);
    await tester.pump();

    await tester.tap(find.text('Next'));
    await tester.pump();

    expect(find.byKey(const Key('watch-together-results')), findsOneWidget);
    expect(find.byKey(const Key('watch-together-finale')), findsNothing);
  });

  testWidgets('a ready montage plays as the finale after the last entry',
      (tester) async {
    montageRepository.seed(const Montage(
      gameId: 'game-1',
      taskId: 'starter-01',
      finaleUrl: 'https://cdn.test/finale.mp4',
      status: MontageStatus.ready,
    ));

    await pumpScreen(tester);
    posts.add([textPost('p1', 'Greg')]);
    await tester.pump();

    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('watch-together-finale')), findsOneWidget);
    expect(find.byType(ArenaVideo), findsOneWidget);
    expect(find.byKey(const Key('watch-together-results')), findsNothing);

    // The finale itself hands over to the results card when it ends.
    platform.emitCompleted(platform.lastPlayerId!);
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('watch-together-results')), findsOneWidget);
  });

  testWidgets('a pending montage is skipped entirely', (tester) async {
    montageRepository.seed(const Montage(
      gameId: 'game-1',
      taskId: 'starter-01',
      status: MontageStatus.pending,
    ));

    await pumpScreen(tester);
    posts.add([textPost('p1', 'Greg')]);
    await tester.pump();

    await tester.tap(find.text('Next'));
    await tester.pump();

    expect(find.byKey(const Key('watch-together-results')), findsOneWidget);
  });

  testWidgets('a tap on a clip carries the second it landed on',
      (tester) async {
    await pumpScreen(tester);
    posts.add([clipPost('p1', 'Greg')]);
    await tester.pump();
    await tester.pump();
    await tester.pump();

    platform.emitPosition(platform.lastPlayerId!, const Duration(seconds: 9));
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.byType(ArenaVideo));
    await tester.pump();

    verify(() => feedRepository.tapPost('p1', atSecond: 9)).called(1);
    await tester.pump(const Duration(milliseconds: 500));
  });
}
