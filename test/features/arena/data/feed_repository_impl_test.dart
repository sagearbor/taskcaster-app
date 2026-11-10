import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/models/submission.dart';
import 'package:taskcaster_app/core/models/task.dart';
import 'package:taskcaster_app/features/arena/data/datasources/mock_feed_data_source.dart';
import 'package:taskcaster_app/features/arena/data/repositories/feed_repository_impl.dart';
import 'package:taskcaster_app/features/arena/domain/models/feed_post.dart';
import 'package:taskcaster_app/features/tasks/data/datasources/daily_task_data.dart';
import 'package:taskcaster_app/features/tasks/data/datasources/starter_pack_data.dart';

FeedPost makePost({
  String id = '',
  String userId = 'user-1',
  String taskId = 'starter-01-v2',
  String gameId = 'game-1',
  int minutesOld = 0,
  int gradeCount = 0,
  int gradeSum = 0,
  int tapCount = 0,
  bool boosted = false,
  bool isHouse = false,
}) {
  return FeedPost(
    id: id,
    gameId: gameId,
    taskId: taskId,
    taskTitle: 'Task $taskId',
    rubric: 'Grade it.',
    userId: userId,
    displayName: userId,
    mediaType: SubmissionMediaType.text,
    text: 'An attempt by $userId',
    createdAt: DateTime.parse('2026-09-12T12:00:00.000Z')
        .subtract(Duration(minutes: minutesOld)),
    gradeCount: gradeCount,
    gradeSum: gradeSum,
    tapCount: tapCount,
    boosted: boosted,
    isHouse: isHouse,
  );
}

void main() {
  late MockFeedDataSource source;
  late FeedRepositoryImpl repo;

  setUp(() {
    source = MockFeedDataSource();
    repo = FeedRepositoryImpl(source);
  });

  tearDown(() => source.dispose());

  group('createPost', () {
    test('assigns an id when the post has none', () async {
      final id = await repo.createPost(makePost());
      expect(id, isNotEmpty);
      final stored = await repo.watchPost(id).first;
      expect(stored, isNotNull);
      expect(stored!.id, id);
      expect(stored.text, 'An attempt by user-1');
    });

    test('honours an id the caller supplies', () async {
      final id = await repo.createPost(makePost(id: 'chosen-id'));
      expect(id, 'chosen-id');
    });

    test('watchPost is null for an id that was never written', () async {
      expect(await repo.watchPost('nope').first, isNull);
    });
  });

  group('watchQueue reveal gating', () {
    test('shows nothing at all until the viewer has unlocked a task', () async {
      await repo.createPost(makePost(userId: 'other'));
      final queue = await repo
          .watchQueue(viewerId: 'me', unlockedTaskIds: const {})
          .first;
      expect(queue, isEmpty);
    });

    test('shows only posts for tasks the viewer has unlocked', () async {
      await repo.createPost(makePost(userId: 'other', taskId: 'starter-01-v2'));
      await repo.createPost(makePost(userId: 'other', taskId: 'starter-02-v2'));

      final queue = await repo
          .watchQueue(viewerId: 'me', unlockedTaskIds: const {'starter-01-v2'})
          .first;
      expect(queue.map((p) => p.taskId), ['starter-01-v2']);
    });

    test('never shows the viewer their own post', () async {
      await repo.createPost(makePost(userId: 'me'));
      await repo.createPost(makePost(userId: 'other'));

      final queue = await repo
          .watchQueue(viewerId: 'me', unlockedTaskIds: const {'starter-01-v2'})
          .first;
      expect(queue.map((p) => p.userId), ['other']);
    });

    test('never shows a post its owner made private', () async {
      await repo.createPost(makePost(userId: 'shy').copyWith(shareable: false));
      await repo.createPost(makePost(userId: 'other'));

      final queue = await repo
          .watchQueue(viewerId: 'me', unlockedTaskIds: const {'starter-01-v2'})
          .first;
      expect(queue.map((p) => p.userId), ['other']);
    });

    test('drops a post as soon as the viewer grades it', () async {
      final id = await repo.createPost(makePost(userId: 'other'));
      expect(
        (await repo
                .watchQueue(viewerId: 'me', unlockedTaskIds: const {'starter-01-v2'})
                .first)
            .length,
        1,
      );

      await repo.gradePost(postId: id, graderId: 'me', score: 4);

      expect(
        await repo
            .watchQueue(viewerId: 'me', unlockedTaskIds: const {'starter-01-v2'})
            .first,
        isEmpty,
      );
    });

    test('includes house entries like any other post', () async {
      await repo.createPost(
        makePost(userId: 'house', isHouse: true),
      );
      final queue = await repo
          .watchQueue(viewerId: 'me', unlockedTaskIds: const {'starter-01-v2'})
          .first;
      expect(queue.single.isHouse, isTrue);
    });

    test('respects the limit', () async {
      for (var i = 0; i < 5; i++) {
        await repo.createPost(makePost(userId: 'other-$i', minutesOld: i));
      }
      final queue = await repo
          .watchQueue(
            viewerId: 'me',
            unlockedTaskIds: const {'starter-01-v2'},
            limit: 3,
          )
          .first;
      expect(queue.length, 3);
    });
  });

  group('watchQueue paging', () {
    test('40 posts where the newest 30 are graded: the 10 older ungraded show',
        () async {
      for (var i = 0; i < 40; i++) {
        final graded = i < 30; // minutesOld 0..29 are the newest 30
        await repo.createPost(makePost(
          id: 'p$i',
          userId: 'author-$i',
          minutesOld: i,
          gradeCount: graded ? 1 : 0,
          gradeSum: graded ? 3 : 0,
        ));
      }
      final queue = await repo
          .watchQueue(viewerId: 'me', unlockedTaskIds: const {'starter-01-v2'})
          .first;
      expect(queue.take(10).map((p) => p.id).toSet(),
          {for (var i = 30; i < 40; i++) 'p$i'});
    });

    test('pages past posts the viewer already graded', () async {
      // 5 newest already graded by the viewer, 2 older ones not.
      for (var i = 0; i < 7; i++) {
        final id = await repo.createPost(
            makePost(id: 'p$i', userId: 'author-$i', minutesOld: i));
        if (i < 5) await repo.gradePost(postId: id, graderId: 'me', score: 3);
      }
      // The graded ones now have gradeCount 1 and sink; make the ungraded
      // ones the ones a 2-row page must still find.
      final queue = await repo
          .watchQueue(
            viewerId: 'me',
            unlockedTaskIds: const {'starter-01-v2'},
            limit: 2,
          )
          .first;
      expect(queue.map((p) => p.id), ['p5', 'p6']);
    });

    test('pages past the viewer\'s own ungraded posts', () async {
      for (var i = 0; i < 6; i++) {
        await repo.createPost(makePost(
            id: 'p$i', userId: i < 4 ? 'me' : 'other-$i', minutesOld: i));
      }
      final queue = await repo
          .watchQueue(
            viewerId: 'me',
            unlockedTaskIds: const {'starter-01-v2'},
            limit: 2,
          )
          .first;
      expect(queue.map((p) => p.id), ['p4', 'p5']);
    });

    test('skips a row that cannot be parsed instead of erroring', () async {
      await repo.createPost(makePost(id: 'good', userId: 'other'));
      await source.createPost({
        'id': 'junk',
        'taskId': 'starter-01-v2',
        'userId': 'other',
        'createdAt': 3.14,
        'gradeCount': 'many',
        'graderIds': 'x',
      });
      final queue = await repo
          .watchQueue(viewerId: 'me', unlockedTaskIds: const {'starter-01-v2'})
          .first;
      expect(queue.map((p) => p.id), containsAll(['good', 'junk']));
    });
  });

  group('watchQueue ordering', () {
    test('boosted first, then fewest grades, then taps, then newest', () async {
      // Deliberately inserted in the wrong order.
      await repo.createPost(makePost(
          id: 'old-ungraded', userId: 'a', minutesOld: 60));
      await repo.createPost(makePost(
          id: 'new-ungraded', userId: 'b', minutesOld: 1));
      await repo.createPost(makePost(
          id: 'tapped-ungraded', userId: 'c', minutesOld: 60, tapCount: 9));
      await repo.createPost(makePost(
          id: 'graded-twice', userId: 'd', minutesOld: 0, gradeCount: 2,
          gradeSum: 6));
      await repo.createPost(makePost(
          id: 'graded-once', userId: 'e', minutesOld: 0, gradeCount: 1,
          gradeSum: 3));
      await repo.createPost(makePost(
          id: 'boosted', userId: 'f', minutesOld: 90, gradeCount: 2,
          gradeSum: 4, boosted: true));

      final queue = await repo
          .watchQueue(viewerId: 'me', unlockedTaskIds: const {'starter-01-v2'})
          .first;

      expect(queue.map((p) => p.id), [
        'boosted', // boosted wins outright, even old and twice-graded
        'tapped-ungraded', // 0 grades, most taps
        'new-ungraded', // 0 grades, no taps, newest
        'old-ungraded',
        'graded-once',
        'graded-twice',
      ]);
    });
  });

  group('gradePost', () {
    test('records the grade and moves both counters', () async {
      final id = await repo.createPost(makePost(userId: 'other'));
      await repo.gradePost(postId: id, graderId: 'me', score: 4);

      final post = await repo.watchPost(id).first;
      expect(post!.gradeCount, 1);
      expect(post.gradeSum, 4);
      expect(post.graderIds, ['me']);
      expect(post.crowdPoints, 8);
    });

    test('a second grade from the same user throws StateError', () async {
      final id = await repo.createPost(makePost(userId: 'other'));
      await repo.gradePost(postId: id, graderId: 'me', score: 4);
      expect(
        () => repo.gradePost(postId: id, graderId: 'me', score: 1),
        throwsA(isA<StateError>()),
      );
    });

    test('two different graders both count', () async {
      final id = await repo.createPost(makePost(userId: 'other'));
      await repo.gradePost(postId: id, graderId: 'me', score: 4);
      await repo.gradePost(postId: id, graderId: 'you', score: 2);

      final post = await repo.watchPost(id).first;
      expect(post!.gradeCount, 2);
      expect(post.gradeSum, 6);
    });

    test('grading your own post throws StateError', () async {
      final id = await repo.createPost(makePost(userId: 'me'));
      expect(
        () => repo.gradePost(postId: id, graderId: 'me', score: 5),
        throwsA(isA<StateError>()),
      );
    });

    test('grading a post that does not exist throws StateError', () async {
      expect(
        () => repo.gradePost(postId: 'nope', graderId: 'me', score: 5),
        throwsA(isA<StateError>()),
      );
    });

    test('a score outside 1..5 is rejected before it reaches the store',
        () async {
      final id = await repo.createPost(makePost(userId: 'other'));
      expect(
        () => repo.gradePost(postId: id, graderId: 'me', score: 0),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => repo.gradePost(postId: id, graderId: 'me', score: 6),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('tapPost', () {
    test('increments the tap counter', () async {
      final id = await repo.createPost(makePost(userId: 'other'));
      await repo.tapPost(id);
      await repo.tapPost(id, taps: 2);
      expect((await repo.watchPost(id).first)!.tapCount, 3);
    });

    test('tapping a missing post is harmless', () async {
      await repo.tapPost('nope');
    });

    test("three taps earn the DON'T ASK stamp", () async {
      final id = await repo.createPost(makePost(userId: 'other'));
      await repo.tapPost(id, taps: 3);
      expect((await repo.watchPost(id).first)!.displayStamp, Stamps.dontAsk);
    });
  });

  group('gradedCountBy', () {
    test('counts the posts a user has graded', () async {
      final a = await repo.createPost(makePost(id: 'a', userId: 'other'));
      final b = await repo.createPost(makePost(id: 'b', userId: 'other'));
      await repo.createPost(makePost(id: 'c', userId: 'other'));

      expect(await repo.gradedCountBy('me'), 0);
      await repo.gradePost(postId: a, graderId: 'me', score: 3);
      await repo.gradePost(postId: b, graderId: 'me', score: 3);
      expect(await repo.gradedCountBy('me'), 2);
      expect(await repo.gradedCountBy('someone-else'), 0);
    });
  });

  group('boostPostsOf', () {
    test('boosts only the poster\'s still-hungry posts', () async {
      await repo.createPost(makePost(id: 'mine-hungry', userId: 'me'));
      await repo.createPost(makePost(
          id: 'mine-fed', userId: 'me', gradeCount: 3, gradeSum: 9));
      await repo.createPost(makePost(id: 'theirs', userId: 'other'));

      await repo.boostPostsOf('me');

      expect((await repo.watchPost('mine-hungry').first)!.boosted, isTrue);
      expect((await repo.watchPost('mine-fed').first)!.boosted, isFalse);
      expect((await repo.watchPost('theirs').first)!.boosted, isFalse);
    });
  });

  group('watchUnlockedTaskIds', () {
    test('is empty for someone who has never posted', () async {
      expect(await repo.watchUnlockedTaskIds('me').first, isEmpty);
    });

    test('is the set of task ids the user has posted to', () async {
      await repo.createPost(makePost(userId: 'me', taskId: 'starter-01-v2'));
      await repo.createPost(makePost(userId: 'me', taskId: 'starter-02-v2'));
      await repo.createPost(makePost(userId: 'me', taskId: 'starter-02-v2'));
      await repo.createPost(makePost(userId: 'other', taskId: 'starter-07'));

      expect(
        await repo.watchUnlockedTaskIds('me').first,
        {'starter-01-v2', 'starter-02-v2'},
      );
    });

    test('re-emits when the user posts again', () async {
      final seen = <Set<String>>[];
      final sub = repo.watchUnlockedTaskIds('me').listen(seen.add);
      await Future<void>.delayed(Duration.zero);

      await repo.createPost(makePost(userId: 'me', taskId: 'starter-01-v2'));
      await Future<void>.delayed(Duration.zero);

      await sub.cancel();
      expect(seen.first, isEmpty);
      expect(seen.last, {'starter-01-v2'});
    });
  });

  group('watchPostsForTask / watchPostsByUser', () {
    test('playback order for one task is oldest first', () async {
      await repo.createPost(makePost(id: 'newest', userId: 'a', minutesOld: 1));
      await repo.createPost(makePost(id: 'oldest', userId: 'b', minutesOld: 90));
      await repo.createPost(
          makePost(id: 'other-task', userId: 'c', taskId: 'starter-02-v2'));

      final posts = await repo
          .watchPostsForTask(gameId: 'game-1', taskId: 'starter-01-v2')
          .first;
      expect(posts.map((p) => p.id), ['oldest', 'newest']);
    });

    test('one task in another game is not included', () async {
      await repo.createPost(makePost(id: 'ours', userId: 'a'));
      await repo
          .createPost(makePost(id: 'theirs', userId: 'b', gameId: 'game-2'));

      final posts = await repo
          .watchPostsForTask(gameId: 'game-1', taskId: 'starter-01-v2')
          .first;
      expect(posts.map((p) => p.id), ['ours']);
    });

    test('a user\'s own posts come back newest first', () async {
      await repo.createPost(makePost(id: 'old', userId: 'me', minutesOld: 90));
      await repo.createPost(makePost(id: 'new', userId: 'me', minutesOld: 1));
      await repo.createPost(makePost(id: 'nope', userId: 'other'));

      final posts = await repo.watchPostsByUser('me').first;
      expect(posts.map((p) => p.id), ['new', 'old']);
    });
  });

  group('ensureHouseEntries', () {
    test('seeds four entries per starter task, posted by the house', () async {
      await repo.ensureHouseEntries();

      final seeded = source.posts;
      expect(
          seeded.length,
          StarterPackData.houseEntries.length * 4 +
              DailyTaskData.houseEntries.length * 2);
      for (final row in seeded) {
        expect(row['isHouse'], isTrue);
        expect(row['userId'], FeedRepositoryImpl.houseUserId);
        expect(row['photoData'], isNull);
        // Text is kept on every entry: it is the caption/fallback a video
        // house entry shows if its clip cannot be played.
        expect(row['text'], isNotEmpty);
      }
      for (final task in StarterPackData.tasks()) {
        final rows = seeded.where((r) => r['taskId'] == task.id).toList();
        expect(rows.map((r) => r['id']), [
          'house-${task.id}',
          'house-${task.id}-1',
          'house-${task.id}-2',
          'house-${task.id}-3',
        ]);
        expect(rows.map((r) => r['displayName']), [
          StarterPackData.housePosterName,
          StarterPackData.auntPam,
          StarterPackData.theIntern,
          StarterPackData.daveFromAccounts,
        ]);
        expect(rows.map((r) => r['stamp']).toSet().length, 4, reason: task.id);
      }
    });

    test('every daily task gets two text entries: the house, then a persona',
        () async {
      await repo.ensureHouseEntries();
      const personas = [
        StarterPackData.auntPam,
        StarterPackData.theIntern,
        StarterPackData.daveFromAccounts,
      ];
      for (final (i, task) in DailyTaskData.tasks().indexed) {
        final rows =
            source.posts.where((r) => r['taskId'] == task.id).toList();
        expect(rows.map((r) => r['id']),
            ['house-${task.id}', 'house-${task.id}-1'],
            reason: task.id);
        expect(rows.map((r) => r['displayName']),
            [StarterPackData.housePosterName, personas[i % 3]],
            reason: task.id);
        for (final r in rows) {
          expect(r['mediaType'], SubmissionMediaType.text.name,
              reason: r['id'] as String);
          expect(r['videoUrl'], isNull);
          expect(r['caption'], task.twist);
        }
      }
    });

    test('houseIdFor keeps the legacy id for entry 0', () {
      expect(FeedRepositoryImpl.houseIdFor('starter-07'), 'house-starter-07');
      expect(FeedRepositoryImpl.houseIdFor('starter-07', 0), 'house-starter-07');
      expect(
          FeedRepositoryImpl.houseIdFor('starter-07', 2), 'house-starter-07-2');
    });

    test('each entry wears its own stamp, and no video is stamped ART',
        () async {
      await repo.ensureHouseEntries();
      for (final row in source.posts) {
        final post = FeedPost.fromMap(row);
        final entry = (StarterPackData.houseEntries[post.taskId] ??
                DailyTaskData.houseEntries[post.taskId]!)
            .firstWhere((e) => e.text == post.text);
        expect(post.stamp, entry.stamp, reason: post.id);
        if (post.mediaType == SubmissionMediaType.video) {
          expect(post.stamp, isNot(Stamps.art), reason: post.id);
        }
      }
    });

    test('entries start with their seeded crowd grade', () async {
      await repo.ensureHouseEntries();
      final post = await repo.watchPost('house-starter-07-3').first;
      final dave = StarterPackData.houseEntries['starter-07']![3];
      expect(post!.displayName, StarterPackData.daveFromAccounts);
      expect(post.gradeCount, dave.gradeCount);
      expect(post.gradeSum, dave.gradeSum);
      expect(post.meanGrade, closeTo(dave.meanGrade, 1e-9));
    });

    test('video starter tasks get VIDEO house entries at house/<taskId>.mp4',
        () async {
      await repo.ensureHouseEntries();

      final byId = {for (final row in source.posts) row['id']: row};
      final videoTasks = StarterPackData.tasks()
          .where((t) => t.submissionType == SubmissionType.video);
      expect(videoTasks, isNotEmpty);

      for (final task in videoTasks) {
        final row = byId['house-${task.id}']!;
        expect(row['mediaType'], SubmissionMediaType.video.name, reason: task.id);
        expect(row['displayName'], StarterPackData.housePosterName);
        expect(row['videoStoragePath'], 'house/${task.id}.mp4');
        expect(row['videoUrl'], StarterPackData.houseVideoUrl(task.id));
        // The personas' takes on a video task are text posts: only entry 0
        // has a clip.
        for (var n = 1; n <= 3; n++) {
          final persona = byId['house-${task.id}-$n']!;
          expect(persona['mediaType'], SubmissionMediaType.text.name);
          expect(persona['videoUrl'], isNull);
          expect(persona['videoStoragePath'], isNull);
        }
      }
    });

    test('photo and text starter tasks keep TEXT house entries', () async {
      await repo.ensureHouseEntries();

      for (final row in source.posts) {
        // Daily entries are all text; the next test covers them.
        if ((row['taskId'] as String).startsWith('daily-')) continue;
        final task =
            StarterPackData.tasks().firstWhere((t) => t.id == row['taskId']);
        if (task.submissionType == SubmissionType.video) continue;
        expect(row['mediaType'], SubmissionMediaType.text.name, reason: task.id);
        expect(row['videoUrl'], isNull, reason: task.id);
        expect(row['videoStoragePath'], isNull, reason: task.id);
      }
    });

    test('re-seeding updates a house entry whose medium changed', () async {
      // A doc seeded by an older build: text, no clip.
      await source.ensureHouseEntries([
        {
          'id': 'house-starter-01-v2',
          'taskId': 'starter-01-v2',
          'mediaType': SubmissionMediaType.text.name,
          'text': 'old copy',
          'isHouse': true,
          'userId': FeedRepositoryImpl.houseUserId,
        }
      ]);

      await repo.ensureHouseEntries();

      final row =
          source.posts.firstWhere((p) => p['id'] == 'house-starter-01-v2');
      expect(row['mediaType'], SubmissionMediaType.video.name);
      expect(row['videoUrl'], StarterPackData.houseVideoUrl('starter-01-v2'));
      expect(row['text'], isNot('old copy'));
    });

    test('is idempotent — running it twice does not duplicate anything',
        () async {
      await repo.ensureHouseEntries();
      final first = source.posts.length;
      await repo.ensureHouseEntries();
      expect(source.posts.length, first);
    });

    test('re-seeding keeps the grades the crowd has already given', () async {
      await repo.ensureHouseEntries();
      const id = 'house-starter-01-v2';
      final seed = StarterPackData.houseEntries['starter-01-v2']!.first;
      await repo.gradePost(postId: id, graderId: 'me', score: 5);

      await repo.ensureHouseEntries();

      final post = await repo.watchPost(id).first;
      expect(post!.gradeCount, seed.gradeCount + 1);
      expect(post.gradeSum, seed.gradeSum + 5);
      expect(post.graderIds, ['me']);
    });

    test('seeded entries are visible in the queue once a task is unlocked',
        () async {
      await repo.ensureHouseEntries();
      final queue = await repo
          .watchQueue(viewerId: 'me', unlockedTaskIds: const {'starter-07'})
          .first;
      expect(queue.map((p) => p.taskId).toSet(), {'starter-07'});
      expect(queue.map((p) => p.displayName).toSet(), {
        StarterPackData.housePosterName,
        StarterPackData.auntPam,
        StarterPackData.theIntern,
        StarterPackData.daveFromAccounts,
      });
    });
  });
}
