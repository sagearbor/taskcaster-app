import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/models/submission.dart';
import 'package:taskcaster_app/features/arena/data/datasources/firestore_feed_data_source.dart';
import 'package:taskcaster_app/features/arena/data/repositories/feed_repository_impl.dart';
import 'package:taskcaster_app/features/arena/domain/models/feed_post.dart';
import 'package:taskcaster_app/features/tasks/data/datasources/starter_pack_data.dart';

FeedPost makePost({
  String id = '',
  String userId = 'user-1',
  String taskId = 'starter-01',
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
    expect(doc.data()!['taskId'], 'starter-01');
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
    await repo.createPost(makePost(userId: 'me', taskId: 'starter-01'));
    await repo.createPost(makePost(userId: 'me', taskId: 'starter-04'));
    await repo.createPost(makePost(userId: 'other', taskId: 'starter-09'));

    expect(
      await repo.watchUnlockedTaskIds('me').first,
      {'starter-01', 'starter-04'},
    );
  });

  test('ensureHouseEntries seeds deterministic ids and is idempotent',
      () async {
    await repo.ensureHouseEntries();
    final first = await firestore.collection('feed_posts').get();
    expect(first.docs.length, StarterPackData.houseEntries.length);
    expect(
      first.docs.map((d) => d.id),
      contains('house-starter-01'),
    );

    await repo.ensureHouseEntries();
    final second = await firestore.collection('feed_posts').get();
    expect(second.docs.length, first.docs.length);
  });

  test('re-seeding keeps grades the crowd has already given', () async {
    await repo.ensureHouseEntries();
    await repo.gradePost(
        postId: 'house-starter-01', graderId: 'me', score: 5);

    await repo.ensureHouseEntries();

    final post = await repo.watchPost('house-starter-01').first;
    expect(post!.gradeCount, 1);
    expect(post.gradeSum, 5);
    expect(post.graderIds, ['me']);
  });

  test('the queue is gated, filtered and ordered off a real query', () async {
    await repo.createPost(makePost(id: 'mine', userId: 'me'));
    await repo.createPost(
        makePost(id: 'locked', userId: 'other', taskId: 'starter-09'));
    await repo.createPost(
        makePost(id: 'newer', userId: 'other', minutesOld: 1));
    await repo.createPost(
        makePost(id: 'older', userId: 'other', minutesOld: 30));

    final queue = await repo
        .watchQueue(viewerId: 'me', unlockedTaskIds: const {'starter-01'})
        .first;
    expect(queue.map((p) => p.id), ['newer', 'older']);
  });
}
