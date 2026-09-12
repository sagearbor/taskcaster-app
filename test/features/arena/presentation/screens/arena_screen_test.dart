import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shimmer/shimmer.dart';
import 'package:taskcaster_app/core/di/service_locator.dart';
import 'package:taskcaster_app/core/models/submission.dart';
import 'package:taskcaster_app/core/models/user.dart';
import 'package:taskcaster_app/features/arena/domain/models/feed_post.dart';
import 'package:taskcaster_app/features/arena/domain/repositories/feed_repository.dart';
import 'package:taskcaster_app/features/arena/presentation/screens/arena_screen.dart';
import 'package:taskcaster_app/features/arena/presentation/widgets/ad_slot_card.dart';
import 'package:taskcaster_app/features/arena/presentation/widgets/grade_bar.dart';
import 'package:taskcaster_app/features/arena/presentation/widgets/post_card.dart';
import 'package:taskcaster_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:taskcaster_app/features/auth/presentation/bloc/auth_bloc.dart';

class MockFeedRepository extends Mock implements FeedRepository {}

class MockAuthRepository extends Mock implements AuthRepository {}

FeedPost _post(String id, {String rubric = 'Emotional truth'}) {
  return FeedPost(
    id: id,
    gameId: 'game-1',
    taskId: 'starter-01',
    taskTitle: 'A vegetable that has just received terrible news',
    rubric: rubric,
    userId: 'other-user',
    displayName: 'Greg',
    mediaType: SubmissionMediaType.text,
    text: 'A very sad potato.',
    caption: 'Done in 12 s',
    stamp: 'NAILED IT',
    createdAt: DateTime(2026, 1, 1),
    elapsedSeconds: 12,
  );
}

void main() {
  late MockFeedRepository mockFeedRepository;
  late MockAuthRepository mockAuthRepository;
  late AuthBloc authBloc;
  late StreamController<Set<String>> unlockedController;
  late StreamController<List<FeedPost>> queueController;
  late User testUser;

  setUp(() async {
    await sl.reset();
    mockFeedRepository = MockFeedRepository();
    sl.registerLazySingleton<FeedRepository>(() => mockFeedRepository);

    mockAuthRepository = MockAuthRepository();
    testUser = User(
      id: 'viewer-1',
      displayName: 'Sophie',
      createdAt: DateTime(2026, 1, 1),
    );
    when(() => mockAuthRepository.getCurrentUser())
        .thenAnswer((_) async => testUser);
    authBloc = AuthBloc(authRepository: mockAuthRepository);

    unlockedController = StreamController<Set<String>>.broadcast();
    queueController = StreamController<List<FeedPost>>.broadcast();

    when(() => mockFeedRepository.watchUnlockedTaskIds(any()))
        .thenAnswer((_) => unlockedController.stream);
    when(() => mockFeedRepository.watchQueue(
          viewerId: any(named: 'viewerId'),
          unlockedTaskIds: any(named: 'unlockedTaskIds'),
        )).thenAnswer((_) => queueController.stream);
    when(() => mockFeedRepository.gradedCountBy(any()))
        .thenAnswer((_) async => 0);
    when(() => mockFeedRepository.gradePost(
          postId: any(named: 'postId'),
          graderId: any(named: 'graderId'),
          score: any(named: 'score'),
        )).thenAnswer((_) async {});
    when(() => mockFeedRepository.boostPostsOf(any()))
        .thenAnswer((_) async {});
    when(() => mockFeedRepository.tapPost(any()))
        .thenAnswer((_) async {});
  });

  tearDown(() async {
    await unlockedController.close();
    await queueController.close();
    authBloc.close();
    AdSlotCard.debugAlwaysShow = false;
  });

  // The Arena's loaded body is a scrollable column (a queue, not a fixed
  // page), so the default 800x600 test surface leaves the GradeBar below
  // the visible/tappable area. Use a tall surface by default, matching this
  // repo's convention for list-heavy screens (see settings/delete_account
  // and settings_screen tests); overflow-check tests override the size to
  // the real device dimensions they're probing.
  Future<void> pumpArena(
    WidgetTester tester, {
    Size physicalSize = const Size(800, 2000),
    double devicePixelRatio = 1.0,
  }) async {
    tester.view.physicalSize = physicalSize;
    tester.view.devicePixelRatio = devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.runAsync(() async {
      authBloc.add(AuthCheckRequested());
      await authBloc.stream.firstWhere((s) => s is AuthAuthenticated);
    });
    await tester.pumpWidget(
      BlocProvider<AuthBloc>.value(
        value: authBloc,
        child: const MaterialApp(home: ArenaScreen()),
      ),
    );
  }

  testWidgets('shows a shimmer skeleton while loading', (tester) async {
    await pumpArena(tester);
    await tester.pump();

    expect(find.text('The Arena'), findsOneWidget);
    expect(find.byType(Shimmer), findsOneWidget);
  });

  testWidgets('nothingUnlocked empty state offers "Do a task"',
      (tester) async {
    await pumpArena(tester);
    await tester.pump();
    unlockedController.add(<String>{});
    await tester.pump();
    queueController.add(const []);
    await tester.pump();

    expect(find.text("Post yours to unlock everyone else's"), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Do a task'), findsOneWidget);
  });

  testWidgets('empty-but-unlocked state shows the check-back copy',
      (tester) async {
    await pumpArena(tester);
    await tester.pump();
    unlockedController.add({'starter-01'});
    await tester.pump();
    queueController.add(const []);
    await tester.pump();

    expect(
      find.text('Nothing new to grade right now — check back soon.'),
      findsOneWidget,
    );
  });

  testWidgets('error state shows ErrorView with a retry button',
      (tester) async {
    await pumpArena(tester);
    await tester.pump();
    unlockedController.addError(Exception('offline'));
    await tester.pump();

    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('loaded state shows the post, rubric line and GradeBar',
      (tester) async {
    await pumpArena(tester);
    await tester.pump();
    unlockedController.add({'starter-01'});
    await tester.pump();
    queueController.add([_post('p1')]);
    await tester.pump();

    expect(find.byType(PostCard), findsOneWidget);
    expect(find.text('Grade for: Emotional truth'), findsOneWidget);
    expect(find.byType(GradeBar), findsOneWidget);
    expect(find.text('graded 0'), findsOneWidget);
  });

  testWidgets('grading advances to the next post and updates the counter',
      (tester) async {
    await pumpArena(tester);
    await tester.pump();
    unlockedController.add({'starter-01'});
    await tester.pump();
    queueController.add([_post('p1'), _post('p2')]);
    await tester.pump();

    await tester.tap(find.text('4'));
    await tester.pump();

    expect(find.text('graded 1'), findsOneWidget);
  });

  testWidgets('Skip advances without grading', (tester) async {
    await pumpArena(tester);
    await tester.pump();
    unlockedController.add({'starter-01'});
    await tester.pump();
    queueController.add([_post('p1'), _post('p2')]);
    await tester.pump();

    await tester.tap(find.text('Skip'));
    await tester.pump();

    // Skip does not count as a grade.
    expect(find.text('graded 0'), findsOneWidget);
    verifyNever(() => mockFeedRepository.gradePost(
          postId: any(named: 'postId'),
          graderId: any(named: 'graderId'),
          score: any(named: 'score'),
        ));
  });

  testWidgets('isDone shows the "graded everything" copy with a Back button',
      (tester) async {
    await pumpArena(tester);
    await tester.pump();
    unlockedController.add({'starter-01'});
    await tester.pump();
    queueController.add([_post('p1')]);
    await tester.pump();

    await tester.tap(find.text('Skip'));
    await tester.pump();

    expect(
      find.textContaining("You've graded everything you've unlocked"),
      findsOneWidget,
    );
    expect(find.widgetWithText(OutlinedButton, 'Back'), findsOneWidget);
  });

  testWidgets('shows the ad slot before the 6th post when ads are visible',
      (tester) async {
    AdSlotCard.debugAlwaysShow = true;
    await pumpArena(tester);
    await tester.pump();
    unlockedController.add({'starter-01'});
    await tester.pump();
    queueController.add(List.generate(6, (i) => _post('p$i')));
    await tester.pump();

    // Skip through the first 5 posts (index 0..4) to reach index 5, the
    // 6th post, where the ad cadence hits ((5+1) % 6 == 0).
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.text('Skip'));
      await tester.pump();
    }

    expect(find.byType(AdSlotCard), findsOneWidget);
    expect(find.text('Sponsored'), findsOneWidget);
    expect(find.byType(PostCard), findsNothing);

    await tester.tap(find.text('Continue'));
    await tester.pump();

    expect(find.byType(PostCard), findsOneWidget);
    expect(find.byType(AdSlotCard), findsNothing);
  });

  testWidgets('no ad slot at all when ads are disabled', (tester) async {
    AdSlotCard.debugAlwaysShow = false;
    await pumpArena(tester);
    await tester.pump();
    unlockedController.add({'starter-01'});
    await tester.pump();
    queueController.add(List.generate(6, (i) => _post('p$i')));
    await tester.pump();

    for (var i = 0; i < 5; i++) {
      await tester.tap(find.text('Skip'));
      await tester.pump();
    }

    // Ads are off: straight through to the 6th post, no blank slot either.
    expect(find.byType(PostCard), findsOneWidget);
    expect(find.text('Sponsored'), findsNothing);
  });

  testWidgets('shows the boost snackbar exactly once after 3 grades',
      (tester) async {
    await pumpArena(tester);
    await tester.pump();
    unlockedController.add({'starter-01'});
    await tester.pump();
    queueController.add(List.generate(4, (i) => _post('p$i')));
    await tester.pump();

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('4'));
      await tester.pump();
    }

    expect(find.text('Your posts jumped the queue'), findsOneWidget);
  });

  for (final size in [
    (const Size(390, 844), 3.0, '390x844@3x'),
    (const Size(360, 640), 2.0, '360x640@2x'),
  ]) {
    testWidgets('no overflow at ${size.$3}', (tester) async {
      await pumpArena(
        tester,
        physicalSize: size.$1 * size.$2,
        devicePixelRatio: size.$2,
      );
      await tester.pump();
      unlockedController.add({'starter-01'});
      await tester.pump();
      queueController.add([_post('p1')]);
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  }
}
