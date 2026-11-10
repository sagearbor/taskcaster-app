import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:taskcaster_app/core/di/service_locator.dart';
import 'package:taskcaster_app/core/models/game.dart';
import 'package:taskcaster_app/core/models/submission.dart';
import 'package:taskcaster_app/core/services/share/share_service.dart';
import 'package:taskcaster_app/features/arena/domain/models/feed_post.dart';
import 'package:taskcaster_app/features/arena/domain/repositories/feed_repository.dart';
import 'package:taskcaster_app/features/arena/presentation/widgets/challenge_vs_card.dart';
import 'package:taskcaster_app/features/games/domain/repositories/game_repository.dart';
import 'package:taskcaster_app/features/games/presentation/screens/posted_screen.dart';
import 'package:taskcaster_app/features/games/presentation/widgets/pending_share_gate.dart';

class MockGameRepository extends Mock implements GameRepository {}

class MockFeedRepository extends Mock implements FeedRepository {}

FeedPost textPost(String id, {String userId = 'me', String name = 'Me'}) =>
    FeedPost(
      id: id,
      gameId: 'g1',
      taskId: 'starter-03',
      taskTitle: 'Rename a household object',
      userId: userId,
      displayName: name,
      mediaType: SubmissionMediaType.text,
      text: 'The lamp is now The Understudy.',
      createdAt: DateTime.utc(2026, 11, 5),
      elapsedSeconds: 41,
      stamp: 'ART',
    );

/// WP-09 + fun audit WP-5: "See theirs" is the primary action, sharing is a
/// compact secondary button that still opens the `/c/<postId>` dare link, and
/// a challenge shows both entries side by side.
void main() {
  late MockGameRepository games;
  late MockFeedRepository feed;
  late List<String> shared;
  late InMemoryShareStore store;
  late ShareService shareService;

  setUpAll(() => registerFallbackValue(<String>{}));

  setUp(() async {
    await sl.reset();
    games = MockGameRepository();
    feed = MockFeedRepository();
    shared = [];
    store = InMemoryShareStore();
    shareService = ShareService(
      store: store,
      sheet: (text, {subject}) async => shared.add(text),
      copyToClipboard: (_) async {},
      hasShareSheet: true,
    );
    when(() => games.getGameStream(any()))
        .thenAnswer((_) => Stream<Game?>.value(null));
    when(() => feed.watchPost('mine'))
        .thenAnswer((_) => Stream.value(textPost('mine')));
    when(() => feed.watchQueue(
          viewerId: any(named: 'viewerId'),
          unlockedTaskIds: any(named: 'unlockedTaskIds'),
          limit: any(named: 'limit'),
        )).thenAnswer((_) => Stream.value(const <FeedPost>[]));
    when(() => feed.watchPost('theirs')).thenAnswer((_) =>
        Stream.value(textPost('theirs', userId: 'friend', name: 'Sage Arbor')));
    sl.registerSingleton<GameRepository>(games);
    sl.registerSingleton<FeedRepository>(feed);
  });

  tearDown(() async => sl.reset());

  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: screen));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('See theirs is the primary (filled) action; Share is a compact secondary one',
      (tester) async {
    await pump(
      tester,
      PostedScreen(
        gameId: 'g1',
        taskIndex: 1,
        taskTitle: 'Rename a household object',
        feedPostId: 'mine',
        shareService: shareService,
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    final seeTheirs = find.byKey(const Key('see-theirs-button'));
    expect(tester.widget(seeTheirs), isA<FilledButton>());
    final share = find.byKey(const Key('share-attempt-button'));
    expect(share, findsOneWidget);
    expect(tester.widget(share), isA<OutlinedButton>());
    expect(find.text('Share it'), findsOneWidget);
    // See theirs sits above Share, and Share is narrower than the column.
    expect(tester.getTopLeft(seeTheirs).dy,
        lessThan(tester.getTopLeft(share).dy));
    expect(tester.getSize(share).width,
        lessThan(tester.getSize(seeTheirs).width));

    await tester.ensureVisible(share);
    await tester.tap(share);
    await tester.pump();
    expect(shared.single, contains('https://taskmaster-app-3d480.web.app/c/mine'));
  });

  testWidgets('without an Arena post there is nothing to share: See theirs stays primary',
      (tester) async {
    await pump(
      tester,
      const PostedScreen(gameId: 'g1', taskIndex: 1, taskTitle: 'T'),
    );
    expect(find.byKey(const Key('share-attempt-button')), findsNothing);
    expect(tester.widget(find.byKey(const Key('see-theirs-button'))),
        isA<FilledButton>());
  });

  testWidgets('a challenge shows them vs. you, records the attribution, and offers Send it back',
      (tester) async {
    await pump(
      tester,
      PostedScreen(
        gameId: 'g1',
        taskIndex: 1,
        taskTitle: 'Rename a household object',
        feedPostId: 'mine',
        challengeFromPostId: 'theirs',
        taskId: 'starter-03',
        userId: 'me',
        shareService: shareService,
      ),
    );

    expect(find.byType(ChallengeVsCard), findsOneWidget);
    expect(find.text('You vs. them'), findsOneWidget);
    expect(find.text('Sage'), findsOneWidget, reason: 'first name only');
    expect(find.text('You'), findsOneWidget);
    expect(find.text('Send it back'), findsOneWidget);
    expect(store.attributions['me'],
        {'fromPostId': 'theirs', 'postId': 'mine', 'taskId': 'starter-03'});
  });

  test('resolvePublicTaskId: starter ids, pre-v2 aliases, nothing else', () {
    expect(resolvePublicTaskId('starter-03'), 'starter-03');
    expect(resolvePublicTaskId('starter-09'), 'starter-09-v2');
    expect(resolvePublicTaskId('friend-task'), isNull);
    expect(resolvePublicTaskId('starter-99'), isNull);
  });
}
