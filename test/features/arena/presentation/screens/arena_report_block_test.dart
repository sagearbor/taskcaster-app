import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:taskcaster_app/core/di/service_locator.dart';
import 'package:taskcaster_app/core/models/submission.dart';
import 'package:taskcaster_app/core/models/user.dart';
import 'package:taskcaster_app/core/services/moderation/moderation_service.dart';
import 'package:taskcaster_app/features/arena/data/datasources/mock_feed_data_source.dart';
import 'package:taskcaster_app/features/arena/data/repositories/feed_repository_impl.dart';
import 'package:taskcaster_app/features/arena/data/repositories/mock_montage_repository.dart';
import 'package:taskcaster_app/features/arena/domain/models/feed_post.dart';
import 'package:taskcaster_app/features/arena/domain/repositories/feed_repository.dart';
import 'package:taskcaster_app/features/arena/domain/repositories/montage_repository.dart';
import 'package:taskcaster_app/features/arena/presentation/screens/arena_screen.dart';
import 'package:taskcaster_app/features/arena/presentation/widgets/post_card.dart';
import 'package:taskcaster_app/features/arena/presentation/widgets/post_menu.dart';
import 'package:taskcaster_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:taskcaster_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:taskcaster_app/features/tasks/data/datasources/starter_pack_data.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

const viewer = 'viewer-1';

/// Report / block from the Arena's "⋯" menu (App Store guideline 1.2).
void main() {
  late MockFeedDataSource source;
  late FeedRepositoryImpl repo;
  late InMemoryModerationStore store;
  late ModerationService moderation;
  late AuthBloc authBloc;
  final taskId = StarterPackData.tasks().first.id;

  FeedPost post(
    String id, {
    String userId = 'troll',
    String displayName = 'Trevor',
    String text = 'An attempt',
    int minutesOld = 0,
    bool isHouse = false,
  }) =>
      FeedPost(
        id: id,
        gameId: '',
        taskId: taskId,
        taskTitle: 'Task one',
        rubric: 'Grade it',
        userId: userId,
        displayName: displayName,
        mediaType: SubmissionMediaType.text,
        text: text,
        isHouse: isHouse,
        createdAt:
            DateTime.utc(2026, 11, 1).subtract(Duration(minutes: minutesOld)),
      );

  setUp(() async {
    await sl.reset();
    source = MockFeedDataSource();
    repo = FeedRepositoryImpl(source);
    store = InMemoryModerationStore();
    moderation =
        ModerationService(store: store, cache: InMemoryModerationCache());
    sl.registerLazySingleton<FeedRepository>(() => repo);
    sl.registerLazySingleton<MontageRepository>(() => MockMontageRepository());
    sl.registerLazySingleton<ModerationService>(() => moderation);

    final auth = MockAuthRepository();
    when(() => auth.getCurrentUser()).thenAnswer((_) async => User(
          id: viewer,
          displayName: 'Sophie',
          createdAt: DateTime(2026, 1, 1),
        ));
    authBloc = AuthBloc(authRepository: auth);
  });

  tearDown(() async {
    await authBloc.close();
    source.dispose();
    await sl.reset();
  });

  /// The viewer has posted on task one (so its queue is open) and [others]
  /// are waiting to be graded, newest first.
  Future<void> pumpArena(WidgetTester tester, List<FeedPost> others) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await repo.createPost(post('mine', userId: viewer, minutesOld: 90));
      for (final p in others) {
        await repo.createPost(p);
      }
      authBloc.add(AuthCheckRequested());
      await authBloc.stream.firstWhere((s) => s is AuthAuthenticated);
    });
    await tester.pumpWidget(
      BlocProvider<AuthBloc>.value(
        value: authBloc,
        child: const MaterialApp(home: ArenaScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('post-card-more')));
    await tester.pumpAndSettle();
  }

  testWidgets('every other player\'s post has a ⋯ menu with Report and Block',
      (tester) async {
    await pumpArena(tester, [post('p1', text: 'Trevor attempt')]);

    expect(find.text('Trevor attempt'), findsOneWidget);
    expect(find.byKey(const Key('post-card-more')), findsOneWidget);
    await openMenu(tester);
    expect(find.text('Report post'), findsOneWidget);
    expect(find.text('Block Trevor'), findsOneWidget);
  });

  testWidgets('house persona posts get the menu too', (tester) async {
    await pumpArena(tester, [
      post('h1',
          userId: 'house', displayName: 'Greg', isHouse: true, text: 'House')
    ]);
    expect(find.text('House'), findsOneWidget);
    await openMenu(tester);
    expect(find.text('Block Greg'), findsOneWidget);
  });

  testWidgets('PostCard draws no menu when none is passed (own posts)',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PostCard(post: post('mine', userId: viewer), autoPlay: false),
        ),
      ),
    ));
    expect(find.byKey(const Key('post-card-more')), findsNothing);
  });

  testWidgets(
      'Report: pick a reason, confirm, the post disappears, the report is '
      'written and the 24-hour snackbar shows', (tester) async {
    await pumpArena(tester, [
      post('bad', text: 'Bad attempt', minutesOld: 1),
      post('next',
          userId: 'friend',
          displayName: 'Fran',
          text: 'Fine attempt',
          minutesOld: 2),
    ]);
    expect(find.text('Bad attempt'), findsOneWidget);

    await openMenu(tester);
    await tester.tap(find.text('Report post'));
    await tester.pumpAndSettle();

    // Step 1: the reason picker, with exactly the four reasons.
    expect(find.byKey(const Key('report-reason-dialog')), findsOneWidget);
    for (final label in ['Inappropriate', 'Spam', 'Harassment', 'Other']) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(find.text('Harassment'));
    await tester.pumpAndSettle();

    // Step 2: confirm.
    expect(find.byKey(const Key('report-confirm-dialog')), findsOneWidget);
    expect(store.reports, isEmpty);
    await tester.tap(find.byKey(const Key('report-confirm')));
    await tester.pump();
    await tester.pump();

    expect(find.text(PostMenu.reportThanks), findsOneWidget);
    expect(PostMenu.reportThanks, "Thanks — we'll review it within 24 hours.");
    expect(find.text('Bad attempt'), findsNothing);
    expect(find.text('Fine attempt'), findsOneWidget);
    expect(store.reports, [
      {
        'id': 'bad_$viewer',
        'postId': 'bad',
        'authorId': 'troll',
        'reporterId': viewer,
        'reason': 'harassment',
      },
    ]);
  });

  testWidgets(
      'cancelling the report confirm leaves the post and writes nothing',
      (tester) async {
    await pumpArena(tester, [post('p1', text: 'Trevor attempt')]);
    await openMenu(tester);
    await tester.tap(find.text('Report post'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spam'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Trevor attempt'), findsOneWidget);
    expect(store.reports, isEmpty);
  });

  testWidgets(
      'Block: confirm, and none of that author\'s posts show any more; the '
      'block is saved to the account', (tester) async {
    await pumpArena(tester, [
      post('t1', text: 'Trevor one', minutesOld: 1),
      post('t2', text: 'Trevor two', minutesOld: 2),
      post('ok',
          userId: 'friend',
          displayName: 'Fran',
          text: 'Fran one',
          minutesOld: 3),
    ]);
    expect(find.text('Trevor one'), findsOneWidget);

    await openMenu(tester);
    await tester.tap(find.text('Block Trevor'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('block-confirm-dialog')), findsOneWidget);
    expect(find.text('Block Trevor?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('block-confirm')));
    await tester.pump();
    await tester.pump();

    expect(find.text('Trevor one'), findsNothing);
    expect(find.text('Trevor two'), findsNothing);
    expect(find.text('Fran one'), findsOneWidget);
    expect(find.text('Trevor is blocked.'), findsOneWidget);
    expect(store.blocked[viewer], ['troll']);
  });

  testWidgets('cancelling the block confirm changes nothing', (tester) async {
    await pumpArena(tester, [post('t1', text: 'Trevor one')]);
    await openMenu(tester);
    await tester.tap(find.text('Block Trevor'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Trevor one'), findsOneWidget);
    expect(store.blocked[viewer], isNull);
  });
}
