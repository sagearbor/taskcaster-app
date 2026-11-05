import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/models/submission.dart';
import 'package:taskcaster_app/features/arena/data/datasources/firestore_feed_data_source.dart';
import 'package:taskcaster_app/features/arena/data/repositories/feed_repository_impl.dart';
import 'package:taskcaster_app/features/arena/domain/models/feed_post.dart';

FeedPost makePost({
  String id = '',
  String userId = 'user-1',
  String taskId = 'starter-01-v2',
  int minutesOld = 0,
  int gradeCount = 0,
}) {
  return FeedPost(
    id: id,
    gameId: 'game-1',
    taskId: taskId,
    taskTitle: 'Task $taskId',
    userId: userId,
    displayName: userId,
    mediaType: SubmissionMediaType.text,
    text: 'An attempt',
    createdAt: DateTime.parse('2026-09-12T12:00:00.000Z')
        .subtract(Duration(minutes: minutesOld)),
    gradeCount: gradeCount,
  );
}

void main() {
  late FakeFirebaseFirestore firestore;
  late FirestoreFeedDataSource source;
  late FeedRepositoryImpl repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    source = FirestoreFeedDataSource(firestore: firestore);
    repo = FeedRepositoryImpl(source);
  });

  test('createPost writes to feed_posts and returns the document id',
      () async {
    final id = await repo.createPost(makePost());
    final doc = await firestore.collection('feed_posts').doc(id).get();
    expect(doc.exists, isTrue);
    // The id lives on the document, not inside it.
    expect(doc.data()!.containsKey('id'), isFalse);
    expect(doc.data()!['taskId'], 'starter-01-v2');
    expect((await repo.watchPost(id).first)!.id, id);
  });

  test('gradePost writes a grade doc and moves the counters atomically',
      () async {
    final id = await repo.createPost(makePost(userId: 'other'));
    await repo.gradePost(postId: id, graderId: 'me', score: 4);

    final grade = await firestore
        .collection('feed_posts')
        .doc(id)
        .collection('grades')
        .doc('me')
        .get();
    expect(grade.exists, isTrue);
    expect(grade.data()!['score'], 4);

    final post = await repo.watchPost(id).first;
    expect(post!.gradeCount, 1);
    expect(post.gradeSum, 4);
    expect(post.graderIds, ['me']);
  });

  test('gradePost refuses a second grade from the same user', () async {
    final id = await repo.createPost(makePost(userId: 'other'));
    await repo.gradePost(postId: id, graderId: 'me', score: 4);
    await expectLater(
      repo.gradePost(postId: id, graderId: 'me', score: 1),
      throwsA(isA<StateError>()),
    );
    expect((await repo.watchPost(id).first)!.gradeCount, 1);
  });

  test('gradePost refuses your own post', () async {
    final id = await repo.createPost(makePost(userId: 'me'));
    await expectLater(
      repo.gradePost(postId: id, graderId: 'me', score: 5),
      throwsA(isA<StateError>()),
    );
  });

  test('gradePost refuses a post that does not exist', () async {
    await expectLater(
      repo.gradePost(postId: 'nope', graderId: 'me', score: 5),
      throwsA(isA<StateError>()),
    );
  });

  test('tapPost increments the counter', () async {
    final id = await repo.createPost(makePost(userId: 'other'));
    await repo.tapPost(id, taps: 3);
    expect((await repo.watchPost(id).first)!.tapCount, 3);
  });

  test('tapPost with a second bumps tapCount and that bucket together',
      () async {
    final id = await repo.createPost(makePost(userId: 'other'));

    await repo.tapPost(id, atSecond: 4);
    await repo.tapPost(id, taps: 2, atSecond: 4);
    await repo.tapPost(id, atSecond: 11);

    final post = (await repo.watchPost(id).first)!;
    expect(post.tapCount, 4);
    // The dotted field path writes into the nested map without rewriting it.
    expect(post.tapSeconds, {'4': 3, '11': 1});
  });

  test('tapPost without a second leaves the histogram alone', () async {
    final id = await repo.createPost(makePost(userId: 'other'));
    await repo.tapPost(id, atSecond: 2);
    await repo.tapPost(id);

    final post = (await repo.watchPost(id).first)!;
    expect(post.tapCount, 2);
    expect(post.tapSeconds, {'2': 1});
  });

  test('gradedCountBy counts via the graderIds array', () async {
    final a = await repo.createPost(makePost(id: 'a', userId: 'other'));
    await repo.createPost(makePost(id: 'b', userId: 'other'));
    await repo.gradePost(postId: a, graderId: 'me', score: 3);

    expect(await repo.gradedCountBy('me'), 1);
    expect(await repo.gradedCountBy('nobody'), 0);
  });

  test('boostPostsOf only touches the poster\'s hungry posts', () async {
    await repo.createPost(makePost(id: 'hungry', userId: 'me'));
    await repo.createPost(makePost(id: 'fed', userId: 'me', gradeCount: 3));
    await repo.createPost(makePost(id: 'theirs', userId: 'other'));

    await repo.boostPostsOf('me');

    expect((await repo.watchPost('hungry').first)!.boosted, isTrue);
    expect((await repo.watchPost('fed').first)!.boosted, isFalse);
    expect((await repo.watchPost('theirs').first)!.boosted, isFalse);
  });

  test('watchUnlockedTaskIds reads the user\'s own posts', () async {
    await repo.createPost(makePost(userId: 'me', taskId: 'starter-01-v2'));
    await repo.createPost(makePost(userId: 'me', taskId: 'starter-04'));
    await repo.createPost(makePost(userId: 'other', taskId: 'starter-09-v2'));

    expect(
      await repo.watchUnlockedTaskIds('me').first,
      {'starter-01-v2', 'starter-04'},
    );
  });

  test('ensureHouseEntries is a no-op on Firestore (Admin SDK seeds them)',
      () async {
    await repo.ensureHouseEntries();
    final docs = await firestore.collection('feed_posts').get();
    expect(docs.docs, isEmpty);
  });

  test('createPost stamps createdAt with the server clock, not the device',
      () async {
    final id = await repo.createPost(makePost(minutesOld: 60 * 24 * 365));
    final raw =
        (await firestore.collection('feed_posts').doc(id).get()).data()!;
    expect(raw['createdAt'], isA<Timestamp>());
    final post = (await repo.watchPost(id).first)!;
    expect(
      DateTime.now().difference(post.createdAt).inMinutes.abs(),
      lessThan(5),
    );
  });

  /// Writes a raw document, bypassing createPost (and its server timestamp).
  Future<void> putRaw(String id, Map<String, dynamic> overrides) {
    return firestore.collection('feed_posts').doc(id).set({
      ...makePost(userId: 'other').toMap()..remove('id'),
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 9, 1)),
      ...overrides,
    });
  }

  test('a legacy ISO-string createdAt still reads', () async {
    await putRaw('legacy', {'createdAt': '2026-09-01T10:00:00.000Z'});
    final post = (await repo.watchPost('legacy').first)!;
    expect(post.createdAt, DateTime.parse('2026-09-01T10:00:00.000Z'));
  });

  test('tapPost names the bucket it moves in lastTapSecond', () async {
    final id = await repo.createPost(makePost(userId: 'other'));
    await repo.tapPost(id, atSecond: 6);
    final raw =
        (await firestore.collection('feed_posts').doc(id).get()).data()!;
    expect(raw['lastTapSecond'], '6');
    expect(raw['tapSeconds'], {'6': 1});
  });

  test('the queue is gated, filtered and ordered off a real query', () async {
    await putRaw('mine', {'userId': 'me'});
    await putRaw('locked', {'taskId': 'starter-09-v2'});
    await putRaw('older',
        {'createdAt': Timestamp.fromDate(DateTime.utc(2026, 9, 1, 10))});
    await putRaw('newer',
        {'createdAt': Timestamp.fromDate(DateTime.utc(2026, 9, 1, 11))});

    final queue = await repo
        .watchQueue(viewerId: 'me', unlockedTaskIds: const {'starter-01-v2'})
        .first;
    expect(queue.map((p) => p.id), ['newer', 'older']);
  });

  test('a malformed post does not break the queue stream', () async {
    await putRaw('good', {});
    // The ordered-by fields stay well-typed here only because
    // fake_cloud_firestore throws comparing mixed types in orderBy (real
    // Firestore orders by type instead); everything else is junk.
    await putRaw('bad', {
      'graderIds': 'not-a-list',
      'tapSeconds': ['nope'],
      'tapCount': 'lots',
      'displayName': 42,
      'isHouse': 'yes',
      'mediaType': 7,
    });

    final queue = await repo
        .watchQueue(viewerId: 'me', unlockedTaskIds: const {'starter-01-v2'})
        .first;
    expect(queue.map((p) => p.id), containsAll(['good', 'bad']));
  });

  test('a post with a junk createdAt / counters still reads', () async {
    await putRaw('bad', {
      'createdAt': 12.5, // neither Timestamp nor ISO string
      'gradeCount': 'three',
      'gradeSum': null,
    });
    final post = (await repo.watchPost('bad').first)!;
    expect(post.createdAt, FeedPost.unknownCreatedAt);
    expect(post.gradeCount, 0);
    expect(post.gradeSum, 0);
  });

  test('40 posts, newest 30 graded: the 10 older ungraded ones still show',
      () async {
    final start = DateTime.utc(2026, 9, 1);
    for (var i = 0; i < 40; i++) {
      final graded = i >= 10; // p10..p39 are the newest 30
      await putRaw('p$i', {
        'userId': 'author-$i',
        'createdAt': Timestamp.fromDate(start.add(Duration(minutes: i))),
        'gradeCount': graded ? 1 : 0,
        'gradeSum': graded ? 3 : 0,
        'graderIds': graded ? ['someone-else'] : <String>[],
      });
    }

    final queue = await repo
        .watchQueue(viewerId: 'me', unlockedTaskIds: const {'starter-01-v2'})
        .first;
    // Ungraded first, so the 10 old ungraded entries lead the queue.
    expect(queue.take(10).map((p) => p.id).toSet(),
        {for (var i = 0; i < 10; i++) 'p$i'});
  });

  test('the queue pages past the viewer\'s own posts to fill up', () async {
    final start = DateTime.utc(2026, 9, 1);
    // p3..p7: the viewer's own (newest); p0..p2: other people's (oldest).
    for (var i = 0; i < 8; i++) {
      await putRaw('p$i', {
        'userId': i < 3 ? 'other' : 'me',
        'createdAt': Timestamp.fromDate(start.add(Duration(minutes: i))),
      });
    }
    final queue = await repo
        .watchQueue(
          viewerId: 'me',
          unlockedTaskIds: const {'starter-01-v2'},
          limit: 3,
        )
        .first;
    expect(queue.map((p) => p.id), ['p2', 'p1', 'p0']);
  });

  test('the queue covers more than 10 unlocked tasks (whereIn chunks)',
      () async {
    final tasks = [for (var i = 0; i < 23; i++) 'task-$i'];
    for (final t in tasks) {
      await putRaw('post-$t', {'taskId': t});
    }
    final queue = await repo
        .watchQueue(viewerId: 'me', unlockedTaskIds: tasks.toSet(), limit: 50)
        .first;
    expect(queue.length, 23);
  });

  test('Watch together reads only the one game\'s entries for the task',
      () async {
    await putRaw('g1', {'gameId': 'game-1'});
    await putRaw('g2', {'gameId': 'game-2'});
    final posts = await repo
        .watchPostsForTask(gameId: 'game-1', taskId: 'starter-01-v2')
        .first;
    expect(posts.map((p) => p.id), ['g1']);
  });
}
