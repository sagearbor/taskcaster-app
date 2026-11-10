import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:taskcaster_app/core/di/service_locator.dart';
import 'package:taskcaster_app/core/models/game.dart';
import 'package:taskcaster_app/core/models/game_settings.dart';
import 'package:taskcaster_app/core/models/submission.dart';
import 'package:taskcaster_app/core/services/share/share_service.dart';
import 'package:taskcaster_app/core/services/sfx/game_sfx.dart';
import 'package:taskcaster_app/features/arena/domain/models/feed_post.dart';
import 'package:taskcaster_app/features/arena/domain/repositories/feed_repository.dart';
import 'package:taskcaster_app/features/games/domain/house_reactions.dart';
import 'package:taskcaster_app/features/games/domain/repositories/game_repository.dart';
import 'package:taskcaster_app/features/games/presentation/screens/game_detail_screen.dart';
import 'package:taskcaster_app/features/games/presentation/screens/posted_screen.dart';
import 'package:taskcaster_app/features/games/presentation/widgets/stamp_sticker.dart';
import 'package:taskcaster_app/features/tasks/data/datasources/starter_pack_data.dart';

class MockGameRepository extends Mock implements GameRepository {}

class MockFeedRepository extends Mock implements FeedRepository {}

class RecordingSfx implements GameSfx {
  final List<String> calls = [];
  @override
  void pop({double pitch = 1.0}) => calls.add('pop');
  @override
  void boom() => calls.add('boom');
  @override
  void tick() => calls.add('tick');
  @override
  void go() => calls.add('go');
  @override
  void fanfare() => calls.add('fanfare');
  @override
  void whoosh() => calls.add('whoosh');
  @override
  void sizzle() => calls.add('sizzle');
}

// A 1x1 transparent PNG.
const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

FeedPost _post({
  String id = 'mine',
  String taskId = 'starter-03',
  SubmissionMediaType mediaType = SubmissionMediaType.text,
  String? photoData,
  String? text = 'The lamp is now The Understudy.',
  String? stamp = Stamps.technically,
}) =>
    FeedPost(
      id: id,
      gameId: 'g1',
      taskId: taskId,
      taskTitle: 'Rename a household object',
      userId: 'me',
      displayName: 'Me',
      mediaType: mediaType,
      photoData: photoData,
      text: text,
      createdAt: DateTime.utc(2026, 11, 9),
      elapsedSeconds: 50,
      stamp: stamp,
    );

FeedPost _other(String id, {String userId = 'house', String taskId = 'starter-03'}) =>
    FeedPost(
      id: id,
      gameId: 'house',
      taskId: taskId,
      taskTitle: 'x',
      userId: userId,
      displayName: "Greg's assistant",
      mediaType: SubmissionMediaType.text,
      text: 'x',
      createdAt: DateTime.utc(2026, 11, 1),
    );

/// The starter game with [postedIndexes] already submitted by `me`.
Game _starter(Set<int> postedIndexes) {
  final tasks = StarterPackData.tasks();
  return Game(
    id: 'g1',
    gameName: StarterPackData.gameName,
    creatorId: 'me',
    judgeId: 'me',
    status: GameStatus.inProgress,
    inviteCode: 'ABC123',
    createdAt: DateTime.utc(2026, 11, 9),
    players: const [],
    settings: const GameSettings(crowdJudged: true),
    gameKind: Game.kindStarter,
    tasks: [
      for (var i = 0; i < tasks.length; i++)
        postedIndexes.contains(i)
            ? tasks[i].copyWith(submissions: [
                Submission(
                  id: 's$i',
                  userId: 'me',
                  score: 0,
                  isJudged: false,
                  submittedAt: DateTime.utc(2026, 11, 9),
                ),
              ])
            : tasks[i],
    ],
  );
}

void main() {
  late MockGameRepository games;
  late MockFeedRepository feed;
  late RecordingSfx sfx;

  setUpAll(() => registerFallbackValue(<String>{}));

  setUp(() async {
    await sl.reset();
    games = MockGameRepository();
    feed = MockFeedRepository();
    sfx = RecordingSfx();
    when(() => games.getGameStream(any()))
        .thenAnswer((_) => Stream<Game?>.value(null));
    when(() => feed.watchQueue(
          viewerId: any(named: 'viewerId'),
          unlockedTaskIds: any(named: 'unlockedTaskIds'),
          limit: any(named: 'limit'),
        )).thenAnswer((_) => Stream.value(const <FeedPost>[]));
    sl.registerSingleton<GameRepository>(games);
    sl.registerSingleton<FeedRepository>(feed);
    sl.registerSingleton<GameSfx>(sfx);
  });

  tearDown(() async => sl.reset());

  ShareService shareService() => ShareService(
        store: InMemoryShareStore(),
        sheet: (text, {subject}) async {},
        copyToClipboard: (_) async {},
        hasShareSheet: true,
      );

  Future<void> pump(
    WidgetTester tester,
    Widget screen, {
    Size size = const Size(390, 844),
    bool reduceMotion = false,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: reduceMotion
          ? Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: screen,
              ),
            )
          : screen,
    ));
    await tester.pump();
    await tester.pump();
  }

  PostedScreen screen({
    int taskIndex = 1,
    String taskId = 'starter-03',
    String? feedPostId = 'mine',
  }) =>
      PostedScreen(
        gameId: 'g1',
        taskIndex: taskIndex,
        taskTitle: 'Rename a household object',
        feedPostId: feedPostId,
        taskId: taskId,
        userId: 'me',
        shareService: shareService(),
      );

  double stampOpacity(WidgetTester tester) => tester
      .widget<Opacity>(find
          .ancestor(
              of: find.byType(StampSticker), matching: find.byType(Opacity))
          .first)
      .opacity;

  testWidgets('a text entry shows as a polaroid with the stamp and the house line',
      (tester) async {
    when(() => feed.watchPost('mine')).thenAnswer((_) => Stream.value(_post()));
    await pump(tester, screen());

    expect(find.byKey(const Key('posted-polaroid')), findsOneWidget);
    expect(find.byKey(const Key('polaroid-text')), findsOneWidget);
    expect(find.text('The lamp is now The Understudy.'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text(Stamps.technically), findsOneWidget);
    final line = HouseReactions.pick(
        postId: 'mine', stamp: Stamps.technically, taskId: 'starter-03');
    final reaction = find.byKey(const Key('house-reaction'));
    expect(reaction, findsOneWidget);
    final rich = tester.widget<RichText>(
        find.descendant(of: reaction, matching: find.byType(RichText)));
    expect(rich.text.toPlainText(), "Greg's assistant: $line");
  });

  testWidgets('a photo entry shows the photo in the polaroid', (tester) async {
    when(() => feed.watchPost('mine')).thenAnswer((_) => Stream.value(_post(
        mediaType: SubmissionMediaType.photo, photoData: _png, text: null)));
    await pump(tester, screen());
    expect(find.byKey(const Key('polaroid-photo')), findsOneWidget);
  });

  testWidgets('a video entry without a poster frame shows the clip tile',
      (tester) async {
    when(() => feed.watchPost('mine')).thenAnswer((_) =>
        Stream.value(_post(mediaType: SubmissionMediaType.video, text: null)));
    await pump(tester, screen());
    expect(find.byKey(const Key('polaroid-video')), findsOneWidget);
    expect(find.text('Your clip'), findsOneWidget);
  });

  testWidgets('the stamp slams in after a delay, with a thunk and a haptic',
      (tester) async {
    final haptics = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        haptics.add(call.arguments as String);
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    when(() => feed.watchPost('mine')).thenAnswer((_) => Stream.value(_post()));
    await pump(tester, screen());

    // Before the delay: the stamp is invisible and nothing has landed.
    expect(stampOpacity(tester), 0);
    expect(sfx.calls, isEmpty);

    await tester.pump(PostedScreen.slamDelay);
    await tester.pump(const Duration(milliseconds: 100));
    // Mid-drop: visible, still oversized.
    final midScale = tester
        .widget<Transform>(find
            .ancestor(
                of: find.byType(StampSticker),
                matching: find.byType(Transform))
            .first)
        .transform
        .getMaxScaleOnAxis();
    expect(midScale, greaterThan(1.2));

    await tester.pump(PostedScreen.slamDuration);
    expect(stampOpacity(tester), 1);
    expect(sfx.calls, ['pop']);
    expect(haptics, contains('HapticFeedbackType.heavyImpact'));
  });

  testWidgets('reduced motion: the stamp and line are there at once',
      (tester) async {
    when(() => feed.watchPost('mine')).thenAnswer((_) => Stream.value(_post()));
    await pump(tester, screen(), reduceMotion: true);
    expect(stampOpacity(tester), 1);
    final fade = tester.widget<FadeTransition>(find
        .ancestor(
            of: find.byKey(const Key('house-reaction')),
            matching: find.byType(FadeTransition))
        .first);
    expect(fade.opacity.value, 1);
    expect(sfx.calls, ['pop']);
  });

  testWidgets('See theirs is primary and counts what is waiting for this task',
      (tester) async {
    when(() => feed.watchPost('mine')).thenAnswer((_) => Stream.value(_post()));
    when(() => feed.watchQueue(
          viewerId: 'me',
          unlockedTaskIds: {'starter-03'},
          limit: any(named: 'limit'),
        )).thenAnswer((_) => Stream.value([
          _other('h1'),
          _other('a'),
          _other('b', userId: 'friend'),
          _other('other-task', taskId: 'starter-04'),
        ]));
    await pump(tester, screen());
    expect(find.text('See theirs (3 waiting)'), findsOneWidget);
    expect(tester.widget(find.byKey(const Key('see-theirs-button'))),
        isA<FilledButton>());
  });

  testWidgets('starter progress: dots, count, and Next skips posted tasks',
      (tester) async {
    when(() => feed.watchPost('mine')).thenAnswer((_) => Stream.value(_post()));
    // Tasks 0, 1 and 3 posted earlier; this is task 2.
    when(() => games.getGameStream('g1'))
        .thenAnswer((_) => Stream.value(_starter({0, 1, 3})));
    await pump(tester, screen(taskIndex: 2, taskId: 'starter-04'));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byKey(const Key('starter-progress')), findsOneWidget);
    expect(find.text('4 of 10'), findsOneWidget);
    final next = StarterPackData.tasks()[4];
    expect(find.text('Next task — ${next.durationSeconds} s'), findsOneWidget);
    expect(find.byKey(const Key('posted-confetti')), findsNothing);
  });

  testWidgets('a friend game shows no progress strip', (tester) async {
    when(() => feed.watchPost('mine')).thenAnswer((_) => Stream.value(_post()));
    await pump(tester, screen());
    expect(find.byKey(const Key('starter-progress')), findsNothing);
    expect(find.text('Back home'), findsOneWidget);
  });

  testWidgets('the tenth post celebrates and opens the First Ten',
      (tester) async {
    when(() => feed.watchPost('mine'))
        .thenAnswer((_) => Stream.value(_post(taskId: 'starter-08-v2')));
    when(() => games.getGameStream('g1')).thenAnswer(
        (_) => Stream.value(_starter({0, 1, 2, 3, 4, 5, 6, 7, 8})));
    await pump(tester, screen(taskIndex: 9, taskId: 'starter-08-v2'));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('10 of 10'), findsOneWidget);
    expect(find.byKey(const Key('posted-confetti')), findsOneWidget);
    expect(sfx.calls, contains('fanfare'));

    final firstTen = find.text('See your First Ten');
    expect(firstTen, findsOneWidget);
    await tester.ensureVisible(firstTen);
    // The game screen needs blocs and repositories this test does not
    // provide; that it is the route that opened is what matters here, so its
    // build errors are muted for these two frames.
    final original = FlutterError.onError;
    FlutterError.onError = (_) {};
    try {
      await tester.tap(firstTen);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(PostedScreen), findsNothing);
      final detail = find.byType(GameDetailScreen);
      expect(detail, findsOneWidget);
      expect(tester.widget<GameDetailScreen>(detail).gameId, 'g1');
      // Tear the half-built screen down while errors are still muted.
      await tester.pumpWidget(const SizedBox());
    } finally {
      FlutterError.onError = original;
    }
  });

  for (final brightness in Brightness.values) {
    testWidgets('no overflow at 360x640 ($brightness), with the buttons reachable',
        (tester) async {
      when(() => feed.watchPost('mine'))
          .thenAnswer((_) => Stream.value(_post(text: 'A' * 400)));
      when(() => games.getGameStream('g1'))
          .thenAnswer((_) => Stream.value(_starter({0, 1})));
      await pump(tester, screen(taskIndex: 2, taskId: 'starter-04'),
          size: const Size(360, 640), brightness: brightness);
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
      // The primary action is on the first screen.
      final seeTheirs =
          tester.getBottomLeft(find.byKey(const Key('see-theirs-button')));
      expect(seeTheirs.dy, lessThanOrEqualTo(640));
    });
  }
}
