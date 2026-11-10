import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taskcaster_app/core/models/game.dart';
import 'package:taskcaster_app/core/models/player_task_status.dart';
import 'package:taskcaster_app/core/theme/app_theme.dart';
import 'package:taskcaster_app/features/arena/domain/models/feed_post.dart';
import 'package:taskcaster_app/features/games/presentation/widgets/starter_recap_view.dart';

import 'starter_recap_fixture.dart';

Widget _app(Widget body, {ThemeData? theme}) => MaterialApp(
      theme: theme ?? AppTheme.lightTheme,
      home: Scaffold(body: body),
    );

Future<void> _phone(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('StarterRecapView.appliesTo', () {
    test('starter and daily games, nothing else', () {
      final g = recapFixture().game;
      expect(StarterRecapView.appliesTo(g), isTrue);
      expect(StarterRecapView.appliesTo(g.copyWith(gameKind: 'daily')),
          isTrue);
      expect(StarterRecapView.appliesTo(g.copyWith(gameKind: Game.kindQuick)),
          isFalse);
    });
  });

  group('RecapEntry.build', () {
    test('matches posts by feedPostId and locks only judged scores', () {
      final f = recapFixture();
      final entries = RecapEntry.build(f.game, recapMe, f.posts);
      expect(entries, hasLength(10));
      expect(entries.where((e) => e.posted), hasLength(7));
      expect(entries[0].post?.id, 'post-0');
      expect(entries[0].lockedScore, 8);
      expect(entries[2].lockedScore, isNull);
      expect(entries[4].gradesToGo, 3);
      expect(entries[9].posted, isFalse);
    });

    test('falls back to game + task id when the submission has no post id',
        () {
      final f = recapFixture(posted: 1);
      final task = f.game.tasks[0];
      final game = f.game.copyWith(tasks: [
        task.copyWith(submissions: [
          task.submissions.first.copyWith(feedPostId: null),
        ]),
        ...f.game.tasks.skip(1),
      ]);
      final entries = RecapEntry.build(game, recapMe, f.posts);
      expect(entries[0].post?.id, 'post-0');
    });
  });

  group('StarterRecapView', () {
    testWidgets('ten tiles, progress, total and grade lines', (tester) async {
      await _phone(tester, const Size(390, 844));
      final f = recapFixture();
      final played = <int>[];
      await tester.pumpWidget(_app(StarterRecapView(
        game: f.game,
        currentUserId: recapMe,
        posts: Stream.value(f.posts),
        onPlayTask: played.add,
        onOpenArena: () {},
        onChallengeFriends: () {},
      )));
      await tester.pumpAndSettle();

      // Not a second "Your First Ten" under the app bar's.
      expect(find.text('YOUR SCORE'), findsOneWidget);
      expect(find.text('YOUR FIRST TEN'), findsNothing);
      expect(find.text('7/10'), findsOneWidget);
      // 8 + 6 + 8 locked by the crowd.
      expect(find.text('22 pts'), findsOneWidget);
      expect(find.textContaining('3 of 10 graded'), findsOneWidget);
      expect(find.text('★ 3.8 · 5 grades'), findsOneWidget);
      expect(find.text('Start task 8'), findsOneWidget);

      // Real thumbnails: the photo bytes and the typed text.
      expect(find.byKey(const Key('recap-photo-0')), findsOneWidget);
      expect(find.byKey(const Key('recap-text-1')), findsOneWidget);
      expect(find.byKey(const Key('recap-locked-0')), findsOneWidget);

      final scroll = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
          find.byKey(const Key('recap-grade-4')), 200,
          scrollable: scroll);
      expect(find.text('3 more grades to go'), findsWidgets);
      await tester.scrollUntilVisible(
          find.byKey(const Key('recap-start-8')), 200,
          scrollable: scroll);
      await tester.drag(scroll, const Offset(0, -150));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('recap-start-8')));
      expect(played, [8]);

      // Never "time to judge" your own entries.
      expect(find.textContaining('JUDGE'), findsNothing);
      expect(find.textContaining('Pick a winner'), findsNothing);
    });

    testWidgets('no celebration until all ten are posted', (tester) async {
      final f = recapFixture();
      await tester.pumpWidget(_app(StarterRecapView(
        game: f.game,
        currentUserId: recapMe,
        posts: Stream.value(f.posts),
      )));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recap-celebration')), findsNothing);
    });

    testWidgets('celebrates all ten exactly once, with confetti',
        (tester) async {
      await _phone(tester, const Size(390, 844));
      final f = recapFixture(posted: 10);
      Widget view() => _app(StarterRecapView(
            key: UniqueKey(),
            game: f.game,
            currentUserId: recapMe,
            posts: Stream.value(f.posts),
          ));

      await tester.pumpWidget(view());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('recap-celebration')), findsOneWidget);
      expect(find.text('You did all ten. The crowd is still grading.'),
          findsOneWidget);
      expect(find.byKey(const Key('recap-confetti')), findsOneWidget);
      await tester.pumpAndSettle();
      // The burst is one-shot.
      expect(find.byKey(const Key('recap-confetti')), findsNothing);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(StarterRecapView.celebratedKey('starter-1')),
          isTrue);

      // Second visit: no banner.
      await tester.pumpWidget(view());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recap-celebration')), findsNothing);
      expect(find.text('10/10'), findsOneWidget);
      // Nothing left to start: the Arena is the one filled button.
      expect(find.byKey(const Key('recap-next')), findsNothing);
    });

    testWidgets('the total updates when a crowd score locks', (tester) async {
      final f = recapFixture();
      final posts = StreamController<List<FeedPost>>.broadcast();
      addTearDown(posts.close);
      Widget view(Game g) => _app(StarterRecapView(
            game: g,
            currentUserId: recapMe,
            posts: posts.stream,
          ));

      await tester.pumpWidget(view(f.game));
      posts.add(f.posts);
      await tester.pumpAndSettle();
      expect(find.text('22 pts'), findsOneWidget);

      // CrowdScoreApplier judges task 3 (index 2) at 8 points.
      final t = f.game.tasks[2];
      final locked = f.game.copyWith(tasks: [
        ...f.game.tasks.take(2),
        t.copyWith(playerStatuses: {
          recapMe: t.playerStatuses[recapMe]!
              .copyWith(state: TaskPlayerState.judged, score: 8),
        }),
        ...f.game.tasks.skip(3),
      ]);
      await tester.pumpWidget(view(locked));
      await tester.pumpAndSettle();
      expect(find.text('30 pts'), findsOneWidget);
      expect(find.textContaining('4 of 10 graded'), findsOneWidget);
    });

    for (final dark in [false, true]) {
      testWidgets('no overflow at 360x640 (${dark ? 'dark' : 'light'})',
          (tester) async {
        await _phone(tester, const Size(360, 640));
        final f = recapFixture(posted: 10);
        await tester.pumpWidget(_app(
          StarterRecapView(
            game: f.game,
            currentUserId: recapMe,
            posts: Stream.value(f.posts),
            onOpenArena: () {},
            onChallengeFriends: () {},
          ),
          theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
        ));
        await tester.pumpAndSettle();
        final scroll = find.byType(Scrollable).first;
        await tester.scrollUntilVisible(
            find.byKey(const Key('recap-challenge')), 300,
            scrollable: scroll);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
