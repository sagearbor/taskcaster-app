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
import 'package:taskcaster_app/features/arena/data/repositories/mock_montage_repository.dart';
import 'package:taskcaster_app/features/arena/domain/repositories/feed_repository.dart';
import 'package:taskcaster_app/features/arena/domain/repositories/montage_repository.dart';
import 'package:taskcaster_app/features/arena/presentation/screens/arena_screen.dart';
import 'package:taskcaster_app/features/arena/presentation/widgets/ad_slot_card.dart';
import 'package:taskcaster_app/features/arena/presentation/widgets/grade_bar.dart';
import 'package:taskcaster_app/features/arena/presentation/widgets/grade_reveal.dart';
import 'package:taskcaster_app/features/arena/presentation/widgets/post_card.dart';
import 'package:taskcaster_app/core/services/sfx/game_sfx.dart';
import 'package:taskcaster_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:taskcaster_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:taskcaster_app/features/tasks/data/datasources/daily_task_data.dart';
import 'package:taskcaster_app/features/tasks/data/datasources/starter_pack_data.dart';

class MockFeedRepository extends Mock implements FeedRepository {}

class MockAuthRepository extends Mock implements AuthRepository {}

FeedPost _post(
  String id, {
  String rubric = 'Emotional truth',
  String taskId = 'starter-01',
  String displayName = 'Greg',
  String text = 'A very sad potato.',
  bool isHouse = false,
  int gradeCount = 0,
  int gradeSum = 0,
}) {
  return FeedPost(
    id: id,
    gameId: 'game-1',
    taskId: taskId,
    taskTitle: 'A vegetable that has just received terrible news',
    rubric: rubric,
    userId: isHouse ? 'house' : 'other-user',
    displayName: isHouse ? StarterPackData.housePosterName : displayName,
    mediaType: SubmissionMediaType.text,
    text: text,
    caption: 'Done in 12 s',
    stamp: 'NAILED IT',
    isHouse: isHouse,
    createdAt: DateTime(2026, 1, 1),
    elapsedSeconds: 12,
    gradeCount: gradeCount,
    gradeSum: gradeSum,
  );
}

class _RecordingSfx implements GameSfx {
  final List<String> calls = [];

  @override
  void pop({double pitch = 1.0}) => calls.add('pop');
  @override
  void fanfare() => calls.add('fanfare');
  @override
  void boom() => calls.add('boom');
  @override
  void tick() => calls.add('tick');
  @override
  void go() => calls.add('go');
  @override
  void whoosh() => calls.add('whoosh');
  @override
  void sizzle() => calls.add('sizzle');
  @override
  void prime() {}
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
    // Empty by default: no montage exists, so no finale card is ever drawn.
    sl.registerLazySingleton<MontageRepository>(
      () => MockMontageRepository(),
    );

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
    when(() => mockFeedRepository.boostPostsOf(any())).thenAnswer((_) async {});
    when(() => mockFeedRepository.tapPost(
          any(),
          taps: any(named: 'taps'),
          atSecond: any(named: 'atSecond'),
        )).thenAnswer((_) async {});
  });

  tearDown(() async {
    await unlockedController.close();
    await queueController.close();
    authBloc.close();
    AdSlotCard.debugAlwaysShow = false;
    ArenaScreen.debugOpenNextTask = null;
    ArenaScreen.debugChallengeFriends = null;
    ArenaScreen.debugOpenDailyTask = null;
    ArenaScreen.debugClock = null;
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

  testWidgets(
      'zero posts: the tease shows entries, no grade bar, and a Your turn bar',
      (tester) async {
    await pumpArena(tester);
    await tester.pump();
    unlockedController.add(<String>{});
    await tester.pump();
    queueController.add([
      _post('t1', taskId: 'starter-09-v3'),
      _post('t2', taskId: 'starter-09-v3'),
    ]);
    await tester.pump();

    // The tease reads task 1 even though nothing is unlocked...
    verify(() => mockFeedRepository.watchQueue(
          viewerId: 'viewer-1',
          unlockedTaskIds: {'starter-09-v3'},
        )).called(1);
    expect(find.text('How everyone else did on task 1'), findsOneWidget);
    expect(find.byType(PostCard), findsOneWidget);
    expect(find.text('Next (1/2)'), findsOneWidget);
    // ...but grading stays gated.
    expect(find.byType(GradeBar), findsNothing);
    expect(find.text('Grading unlocks when you post yours.'), findsOneWidget);
    expect(find.text('Your turn: 30 s'), findsOneWidget);

    await tester.tap(find.text('Next (1/2)'));
    await tester.pump();
    expect(find.text('Next (2/2)'), findsOneWidget);
  });

  testWidgets('a failed tease read shows the empty tease, not an error page',
      (tester) async {
    await pumpArena(tester);
    await tester.pump();
    unlockedController.add(<String>{});
    await tester.pump();
    queueController.addError(Exception('FAILED_PRECONDITION: needs an index'));
    await tester.pump();

    expect(find.text('Something went wrong'), findsNothing);
    expect(find.text("Post yours to unlock everyone else's"), findsOneWidget);
    expect(find.text('Your turn: 30 s'), findsOneWidget);
  });

  testWidgets('Your turn pops the Arena with yourTurnResult', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      authBloc.add(AuthCheckRequested());
      await authBloc.stream.firstWhere((s) => s is AuthAuthenticated);
    });

    Object? result;
    await tester.pumpWidget(
      BlocProvider<AuthBloc>.value(
        value: authBloc,
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ArenaScreen()),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(seconds: 1));
    unlockedController.add(<String>{});
    await tester.pump();
    queueController.add(const []);
    await tester.pump();

    expect(find.text("Post yours to unlock everyone else's"), findsOneWidget);
    await tester.tap(find.byKey(const Key('arena-your-turn')));
    await tester.pump(const Duration(seconds: 1));

    expect(result, ArenaScreen.yourTurnResult);
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
    expect(find.text('✓ 0 graded'), findsOneWidget);
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

    expect(find.text('✓ 1 graded'), findsOneWidget);
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
    expect(find.text('✓ 0 graded'), findsOneWidget);
    verifyNever(() => mockFeedRepository.gradePost(
          postId: any(named: 'postId'),
          graderId: any(named: 'graderId'),
          score: any(named: 'score'),
        ));
  });

  testWidgets(
      'isDone: the next starter task is the primary button, Back a text link',
      (tester) async {
    var opened = 0;
    ArenaScreen.debugOpenNextTask = (_) async => opened++;
    await pumpArena(tester);
    await tester.pump();
    // Task 1 of the pack (starter-09-v3, 30 s) is done; task 2 is next.
    final pack = StarterPackData.tasks();
    unlockedController.add({pack[0].id});
    await tester.pump();
    queueController.add([_post('p1')]);
    await tester.pump();

    await tester.tap(find.text('Skip'));
    await tester.pump();

    expect(
      find.text("You've graded everything you've unlocked."),
      findsOneWidget,
    );
    expect(find.text('Do the next task to unlock more.'), findsOneWidget);
    expect(
      find.widgetWithText(
          FilledButton, 'Next task — ${pack[1].durationSeconds} s'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextButton, 'Back'), findsOneWidget);

    await tester.tap(find.byKey(const Key('arena-next-up')));
    await tester.pump();
    expect(opened, 1);
  });

  // 19:00 UTC: five hours until the next daily task.
  final dailyNow = DateTime.utc(2026, 11, 9, 19);
  final todaysTask = DailyTaskData.taskFor(dailyNow);

  Future<void> reachAllDonePanel(WidgetTester tester,
      {Set<String> extraUnlocked = const {}}) async {
    ArenaScreen.debugClock = () => dailyNow;
    await pumpArena(tester);
    await tester.pump();
    unlockedController.add({
      for (final t in StarterPackData.tasks()) t.id,
      ...extraUnlocked,
    });
    await tester.pump();
    queueController.add([_post('p1')]);
    await tester.pump();
    await tester.tap(find.text('Skip'));
    await tester.pump();
  }

  testWidgets('all ten done, daily not posted: the primary is today\'s task',
      (tester) async {
    var opened = 0;
    ArenaScreen.debugOpenDailyTask = (_) async => opened++;
    when(() => mockFeedRepository.watchPostsByUser(any()))
        .thenAnswer((_) => Stream.value(const []));
    await reachAllDonePanel(tester);

    expect(find.text("Today's task is waiting. Same one for everyone."),
        findsOneWidget);
    expect(
      find.widgetWithText(
          FilledButton, "Today's task — ${todaysTask.durationSeconds} s"),
      findsOneWidget,
    );
    expect(find.textContaining('Come back tomorrow'), findsNothing);
    await tester.tap(find.byKey(const Key('arena-next-up')));
    await tester.pump();
    expect(opened, 1);
  });

  testWidgets('a daily post from 30 days ago does not count as today',
      (tester) async {
    ArenaScreen.debugOpenDailyTask = (_) async {};
    final old = FeedPost.fromMap({
      ..._post('mine-old', taskId: todaysTask.id).toMap(),
      'userId': 'viewer-1',
      'createdAt': dailyNow.subtract(const Duration(days: 30)).toIso8601String(),
    });
    when(() => mockFeedRepository.watchPostsByUser(any()))
        .thenAnswer((_) => Stream.value([old]));
    await reachAllDonePanel(tester, extraUnlocked: {todaysTask.id});
    await tester.pump();

    expect(find.textContaining("Today's task — "), findsOneWidget);
  });

  testWidgets(
      'all ten done and today\'s task posted: done for today, Challenge friends',
      (tester) async {
    var challenged = 0;
    ArenaScreen.debugChallengeFriends = (_) async => challenged++;
    final mine = FeedPost.fromMap({
      ..._post('mine', taskId: todaysTask.id).toMap(),
      'userId': 'viewer-1',
      'createdAt': dailyNow.subtract(const Duration(hours: 1)).toIso8601String(),
    });
    when(() => mockFeedRepository.watchPostsByUser(any()))
        .thenAnswer((_) => Stream.value([mine]));
    await reachAllDonePanel(tester, extraUnlocked: {todaysTask.id});
    await tester.pump();

    expect(find.text('Done for today · new task in 5 h 0 m'), findsOneWidget);
    expect(
        find.widgetWithText(FilledButton, 'Challenge friends'), findsOneWidget);
    await tester.tap(find.byKey(const Key('arena-next-up')));
    await tester.pump();
    expect(challenged, 1);
  });

  testWidgets('the all-done panel fits 360x640 with no overflow',
      (tester) async {
    when(() => mockFeedRepository.watchPostsByUser(any()))
        .thenAnswer((_) => Stream.value(const []));
    ArenaScreen.debugClock = () => dailyNow;
    await pumpArena(tester, physicalSize: const Size(360, 640));
    await tester.pump();
    unlockedController.add({for (final t in StarterPackData.tasks()) t.id});
    await tester.pump();
    queueController.add(const []);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('arena-next-up')), findsOneWidget);
  });

  testWidgets('empty-but-unlocked is not a dead end either', (tester) async {
    await pumpArena(tester);
    await tester.pump();
    unlockedController.add({StarterPackData.tasks().first.id});
    await tester.pump();
    queueController.add(const []);
    await tester.pump();

    expect(find.byKey(const Key('arena-next-up')), findsOneWidget);
    expect(find.textContaining('Next task — '), findsOneWidget);
  });

  testWidgets('Back on the next-up panel pops the Arena', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      authBloc.add(AuthCheckRequested());
      await authBloc.stream.firstWhere((s) => s is AuthAuthenticated);
    });
    await tester.pumpWidget(
      BlocProvider<AuthBloc>.value(
        value: authBloc,
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ArenaScreen()),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(seconds: 1));
    unlockedController.add({'starter-01'});
    await tester.pump();
    queueController.add(const []);
    await tester.pump();

    await tester.tap(find.widgetWithText(TextButton, 'Back'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(ArenaScreen), findsNothing);
  });

  group('grade reveal', () {
    late _RecordingSfx sfx;

    setUp(() {
      sfx = _RecordingSfx();
      sl.registerLazySingleton<GameSfx>(() => sfx);
    });

    Future<void> loadQueue(WidgetTester tester, List<FeedPost> posts,
        {Size? size, double dpr = 1.0}) async {
      await pumpArena(
        tester,
        physicalSize: size ?? const Size(800, 2000),
        devicePixelRatio: dpr,
      );
      await tester.pump();
      unlockedController.add({'starter-01'});
      await tester.pump();
      queueController.add(posts);
      await tester.pump();
    }

    testWidgets(
        'shows You vs the crowd mean INCLUDING your grade, then advances',
        (tester) async {
      // 11 earlier grades summing 33 (mean 3.0). You give 4:
      // (33 + 4) / 12 = 3.08 -> "3.1", 12 grades, +0.92 -> GENEROUS.
      await loadQueue(tester, [
        _post('p1', gradeCount: 11, gradeSum: 33),
        _post('p2', text: 'Second post'),
      ]);

      await tester.tap(find.text('4'));
      await tester.pump();

      expect(find.byType(GradeRevealOverlay), findsOneWidget);
      expect(find.text('3.1'), findsOneWidget);
      expect(find.text('12 grades'), findsOneWidget);
      expect(find.text(GradeReveal.generous), findsOneWidget);
      expect(find.text(GradeRevealOverlay.skipHint), findsOneWidget);
      // The graded post is still the one on screen.
      expect(find.text('A very sad potato.'), findsOneWidget);
      // ...but the grade is already saved and counted: nobody waits on us.
      expect(find.text('✓ 1 graded'), findsOneWidget);
      verify(() => mockFeedRepository.gradePost(
            postId: 'p1',
            graderId: 'viewer-1',
            score: 4,
          )).called(1);

      await tester.pump(ArenaScreen.revealHold);
      await tester.pump();

      expect(find.byType(GradeRevealOverlay), findsNothing);
      expect(find.text('Second post'), findsOneWidget);
    });

    testWidgets('the reveal fully covers the media: an opaque scrim',
        (tester) async {
      await loadQueue(tester, [_post('p1', gradeCount: 2, gradeSum: 6)]);
      await tester.tap(find.text('4'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final boxes = tester.widgetList<DecoratedBox>(find.descendant(
        of: find.byType(GradeRevealOverlay),
        matching: find.byType(DecoratedBox),
      ));
      final scrim = boxes.first.decoration as BoxDecoration;
      final colors = scrim.gradient?.colors ?? [scrim.color!];
      expect(colors.every((c) => c.alpha == 255), isTrue);
    });

    testWidgets('a tap anywhere skips the wait', (tester) async {
      await loadQueue(tester, [
        _post('p1', gradeCount: 2, gradeSum: 6),
        _post('p2', text: 'Second post'),
      ]);

      await tester.tap(find.text('3'));
      await tester.pump();
      expect(find.byType(GradeRevealOverlay), findsOneWidget);

      // Tapping a chip during the reveal only skips; it does not grade the
      // next post blind.
      await tester.tap(find.text('5'));
      await tester.pump();

      expect(find.byType(GradeRevealOverlay), findsNothing);
      expect(find.text('Second post'), findsOneWidget);
      expect(find.text('✓ 1 graded'), findsOneWidget);
    });

    testWidgets('within 0.5 of the crowd is IN TUNE', (tester) async {
      // (4 + 4) / 2 = 4.0
      await loadQueue(tester, [_post('p1', gradeCount: 1, gradeSum: 4)]);
      await tester.tap(find.text('4'));
      await tester.pump();

      expect(find.text('4.0'), findsOneWidget);
      expect(find.text('2 grades'), findsOneWidget);
      expect(find.text(GradeReveal.inTune), findsOneWidget);
    });

    testWidgets('below the crowd is HARSH', (tester) async {
      // (15 + 1) / 4 = 4.0, you said 1.
      await loadQueue(tester, [_post('p1', gradeCount: 3, gradeSum: 15)]);
      await tester.tap(find.text('1'));
      await tester.pump();

      expect(find.text('4.0'), findsOneWidget);
      expect(find.text(GradeReveal.harsh), findsOneWidget);
    });

    testWidgets('the first grader sets the bar', (tester) async {
      await loadQueue(tester, [_post('p1')]);
      await tester.tap(find.text('2'));
      await tester.pump();

      expect(find.text(GradeReveal.firstGradeLine), findsOneWidget);
      expect(find.text('CROWD'), findsNothing);
      expect(find.text(GradeReveal.inTune), findsNothing);
    });

    testWidgets('after the last post the reveal plays, then the next-up panel',
        (tester) async {
      await loadQueue(tester, [_post('p1', gradeCount: 1, gradeSum: 3)]);
      await tester.tap(find.text('3'));
      await tester.pump();
      expect(find.byType(GradeRevealOverlay), findsOneWidget);

      await tester.pump(ArenaScreen.revealHold);
      await tester.pump();
      expect(find.byKey(const Key('arena-next-up')), findsOneWidget);
    });

    testWidgets('pop on every grade, fanfare when the crowd says 5',
        (tester) async {
      await loadQueue(tester, [
        _post('p1', gradeCount: 1, gradeSum: 2),
        _post('p2', gradeCount: 3, gradeSum: 15),
      ]);

      await tester.tap(find.text('3'));
      await tester.pump();
      expect(sfx.calls, ['pop']);

      await tester.tap(find.text('Skip'), warnIfMissed: false);
      await tester.pump();
      await tester.tap(find.text('5'));
      await tester.pump();
      expect(sfx.calls, ['pop', 'pop', 'fanfare']);
    });

    for (final size in [
      (const Size(390, 844), 3.0, '390x844@3x'),
      (const Size(360, 640), 2.0, '360x640@2x'),
    ]) {
      testWidgets('reveal has no overflow at ${size.$3}', (tester) async {
        await loadQueue(
          tester,
          [_post('p1', gradeCount: 11, gradeSum: 33)],
          size: size.$1 * size.$2,
          dpr: size.$2,
        );
        await tester.ensureVisible(find.text('4'));
        await tester.pump();
        await tester.tap(find.text('4'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        expect(find.byType(GradeRevealOverlay), findsOneWidget);

        await tester.pump(ArenaScreen.revealHold);
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('arena-next-up')), findsOneWidget);
      });
    }
  });

  group('tease header', () {
    Future<void> tease(WidgetTester tester, List<FeedPost> posts) async {
      await pumpArena(tester);
      await tester.pump();
      unlockedController.add(<String>{});
      await tester.pump();
      queueController.add(posts);
      await tester.pump();
    }

    testWidgets('only the house entry: name the robot, not everyone',
        (tester) async {
      await tease(tester, [
        _post('h1', taskId: 'starter-09-v3', isHouse: true),
      ]);
      expect(find.text("How Greg's assistant did on task 1"), findsOneWidget);
      expect(find.text('How everyone else did on task 1'), findsNothing);
    });

    testWidgets('one player plus the house names both', (tester) async {
      await tease(tester, [
        _post('p1', taskId: 'starter-09-v3', displayName: 'Sophie'),
        _post('h1', taskId: 'starter-09-v3', isHouse: true),
      ]);
      expect(find.text("How Sophie and Greg's assistant did on task 1"),
          findsOneWidget);
    });

    testWidgets('two or more players: everyone else', (tester) async {
      await tease(tester, [
        _post('p1', taskId: 'starter-09-v3'),
        _post('p2', taskId: 'starter-09-v3'),
        _post('h1', taskId: 'starter-09-v3', isHouse: true),
      ]);
      expect(find.text('How everyone else did on task 1'), findsOneWidget);
    });
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
      // Skip the grade reveal (any tap does it).
      await tester.tap(find.byKey(const Key('arena-reveal-skip')));
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
