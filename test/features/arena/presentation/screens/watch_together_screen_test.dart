import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:taskcaster_app/core/di/service_locator.dart';
import 'package:taskcaster_app/core/models/submission.dart';
import 'package:taskcaster_app/features/arena/domain/models/feed_post.dart';
import 'package:taskcaster_app/features/arena/domain/repositories/feed_repository.dart';
import 'package:taskcaster_app/features/arena/presentation/screens/watch_together_screen.dart';
import 'package:taskcaster_app/features/arena/presentation/widgets/post_card.dart';

class MockFeedRepository extends Mock implements FeedRepository {}

FeedPost _post(String id, String name, {int? gradeCount, int gradeSum = 0}) {
  return FeedPost(
    id: id,
    gameId: 'game-1',
    taskId: 'starter-01',
    taskTitle: 'A vegetable that has just received terrible news',
    rubric: 'Emotional truth',
    userId: 'user-$id',
    displayName: name,
    mediaType: SubmissionMediaType.text,
    text: 'A very sad potato.',
    caption: 'Done in 12 s',
    stamp: 'NAILED IT',
    createdAt: DateTime(2026, 1, 1),
    elapsedSeconds: 12,
    gradeCount: gradeCount ?? 0,
    gradeSum: gradeSum,
  );
}

void main() {
  late MockFeedRepository mockFeedRepository;
  late StreamController<List<FeedPost>> postsController;

  setUp(() async {
    await sl.reset();
    mockFeedRepository = MockFeedRepository();
    sl.registerLazySingleton<FeedRepository>(() => mockFeedRepository);

    postsController = StreamController<List<FeedPost>>.broadcast();
    when(() => mockFeedRepository.watchPostsForTask(
          gameId: any(named: 'gameId'),
          taskId: any(named: 'taskId'),
        )).thenAnswer((_) => postsController.stream);
    when(() => mockFeedRepository.tapPost(any())).thenAnswer((_) async {});
  });

  tearDown(() async {
    await postsController.close();
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    Size physicalSize = const Size(400, 900),
    double devicePixelRatio = 1.0,
  }) async {
    tester.view.physicalSize = physicalSize;
    tester.view.devicePixelRatio = devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const WatchTogetherScreen(
                    gameId: 'game-1',
                    taskId: 'starter-01',
                    taskTitle: 'A vegetable that has just received terrible '
                        'news',
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    // NOT pumpAndSettle(): before the posts stream emits, the screen shows
    // an indeterminate CircularProgressIndicator whose animation never
    // settles on its own. A couple of pumps is enough to finish the route
    // transition.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('shows a loading spinner before the first snapshot',
      (tester) async {
    await pumpScreen(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('empty task shows the empty copy with a Done button',
      (tester) async {
    await pumpScreen(tester);
    postsController.add(const []);
    await tester.pump();

    expect(find.text('Nothing posted for this task yet.'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget); // popped back
  });

  testWidgets('shows the first post with a progress indicator',
      (tester) async {
    await pumpScreen(tester);
    postsController.add([_post('p1', 'Greg'), _post('p2', 'Sophie')]);
    await tester.pump();

    expect(find.byType(PostCard), findsOneWidget);
    expect(find.text('Greg'), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('Next advances to the following post', (tester) async {
    await pumpScreen(tester);
    postsController.add([_post('p1', 'Greg'), _post('p2', 'Sophie')]);
    await tester.pump();

    await tester.tap(find.text('Next'));
    await tester.pump();

    expect(find.text('Sophie'), findsOneWidget);
    expect(find.text('2 / 2'), findsOneWidget);
  });

  testWidgets('auto-advances to the next post after ~6 seconds',
      (tester) async {
    await pumpScreen(tester);
    postsController.add([_post('p1', 'Greg'), _post('p2', 'Sophie')]);
    await tester.pump();

    expect(find.text('Greg'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6, milliseconds: 50));

    expect(find.text('Sophie'), findsOneWidget);
  });

  testWidgets('swiping left advances to the next post', (tester) async {
    await pumpScreen(tester);
    postsController.add([_post('p1', 'Greg'), _post('p2', 'Sophie')]);
    await tester.pump();

    await tester.fling(find.byType(PostCard), const Offset(-300, 0), 800);
    await tester.pump();

    expect(find.text('Sophie'), findsOneWidget);
  });

  testWidgets('tapping the screen fires a fire-and-forget funny tap',
      (tester) async {
    await pumpScreen(tester);
    postsController.add([_post('p1', 'Greg')]);
    await tester.pump();

    // Tap somewhere on the slide that is not the Next button or PostCard's
    // own media area, to exercise the screen-level tap handler.
    await tester.tapAt(const Offset(20, 20));
    await tester.pump();

    verify(() => mockFeedRepository.tapPost('p1')).called(1);
    expect(find.text('\u{1F525}'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('\u{1F525}'), findsNothing);
  });

  testWidgets('last card shows results with points/unscored and tap count',
      (tester) async {
    await pumpScreen(tester);
    postsController.add([
      _post('p1', 'Greg', gradeCount: 3, gradeSum: 12), // mean 4 -> 8 pts
      _post('p2', 'Sophie'), // unscored
    ]);
    await tester.pump();

    await tester.tap(find.text('Next')); // -> post 2
    await tester.pump();
    await tester.tap(find.text('Next')); // -> past the end: results
    await tester.pump();

    expect(find.text('Results'), findsOneWidget);
    expect(find.text('Greg'), findsOneWidget);
    expect(find.text('8 pts'), findsOneWidget);
    expect(find.text('Sophie'), findsOneWidget);
    expect(find.text('unscored'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
  });

  for (final size in [
    (const Size(390, 844), 3.0, '390x844@3x'),
    (const Size(360, 640), 2.0, '360x640@2x'),
  ]) {
    testWidgets('no overflow at ${size.$3}', (tester) async {
      await pumpScreen(
        tester,
        physicalSize: size.$1 * size.$2,
        devicePixelRatio: size.$2,
      );
      postsController.add([_post('p1', 'Greg'), _post('p2', 'Sophie')]);
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  }
}
