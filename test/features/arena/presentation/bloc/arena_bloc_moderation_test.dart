import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/models/submission.dart';
import 'package:taskcaster_app/core/services/moderation/moderation_service.dart';
import 'package:taskcaster_app/features/arena/data/datasources/mock_feed_data_source.dart';
import 'package:taskcaster_app/features/arena/data/repositories/feed_repository_impl.dart';
import 'package:taskcaster_app/features/arena/domain/models/feed_post.dart';
import 'package:taskcaster_app/features/arena/presentation/bloc/arena_bloc.dart';
import 'package:taskcaster_app/features/arena/presentation/bloc/arena_event.dart';
import 'package:taskcaster_app/features/arena/presentation/bloc/arena_state.dart';

const me = 'me';

/// An account whose profile doc hasn't answered yet (slow network).
class _SlowStore extends InMemoryModerationStore {
  @override
  Stream<List<String>> watchBlocked(String uid) => const Stream.empty();
}

FeedPost post({
  required String id,
  String userId = 'other',
  String? displayName,
  String taskId = 'starter-01',
  int minutesOld = 0,
  bool isHouse = false,
}) {
  return FeedPost(
    id: id,
    gameId: 'game-1',
    taskId: taskId,
    taskTitle: 'Task $taskId',
    rubric: 'Grade it.',
    userId: userId,
    displayName: displayName ?? userId,
    mediaType: SubmissionMediaType.text,
    text: 'An attempt',
    isHouse: isHouse,
    createdAt: DateTime.parse('2026-09-12T12:00:00.000Z')
        .subtract(Duration(minutes: minutesOld)),
  );
}

/// Report / block in the Arena queue (App Store 1.2).
void main() {
  late MockFeedDataSource source;
  late FeedRepositoryImpl repo;
  late InMemoryModerationStore store;
  late InMemoryModerationCache cache;
  late ModerationService moderation;

  setUp(() {
    source = MockFeedDataSource();
    repo = FeedRepositoryImpl(source);
    store = InMemoryModerationStore();
    cache = InMemoryModerationCache();
    moderation = ModerationService(store: store, cache: cache);
  });

  tearDown(() async {
    source.dispose();
    await moderation.dispose();
  });

  ArenaBloc build() => ArenaBloc(
        feedRepository: repo,
        teaserTaskId: 'starter-01',
        moderation: moderation,
      );

  Future<ArenaLoaded> loaded(ArenaBloc bloc) async {
    final s = bloc.state is ArenaLoaded
        ? bloc.state
        : await bloc.stream.firstWhere((s) => s is ArenaLoaded);
    return s as ArenaLoaded;
  }

  /// The viewer has posted on starter-01, so its queue is open.
  Future<void> seed(List<FeedPost> others) async {
    await repo.createPost(post(id: 'mine', userId: me, minutesOld: 90));
    for (final p in others) {
      await repo.createPost(p);
    }
  }

  List<String> remaining(ArenaLoaded s) =>
      s.queue.skip(s.index).map((p) => p.id).toList();

  test(
      'a blocked author\'s posts never reach the queue (cached block list, '
      'before the account doc loads)', () async {
    moderation = ModerationService(store: _SlowStore(), cache: cache);
    await cache.write(me, const ModerationSnapshot(blocked: {'troll'}));
    await seed([
      post(id: 't1', userId: 'troll', minutesOld: 1),
      post(id: 'ok', userId: 'friend', minutesOld: 2),
      post(id: 't2', userId: 'troll', minutesOld: 3),
    ]);
    final bloc = build()..add(const LoadArena(viewerId: me));
    final s = await loaded(bloc);
    expect(remaining(s), ['ok']);
    await bloc.close();
  });

  test('the account\'s block list (users/{uid}.blockedUids) filters too',
      () async {
    store.blocked[me] = ['troll'];
    await seed([
      post(id: 't1', userId: 'troll'),
      post(id: 'ok', userId: 'friend', minutesOld: 1),
    ]);
    final bloc = build()..add(const LoadArena(viewerId: me));
    await loaded(bloc);
    await Future<void>.delayed(Duration.zero);
    expect(remaining(bloc.state as ArenaLoaded), ['ok']);
    await bloc.close();
  });

  test('reporting the current post hides it and moves to the next', () async {
    await seed([
      post(id: 'bad', userId: 'troll', minutesOld: 1),
      post(id: 'next', userId: 'friend', minutesOld: 2),
    ]);
    final bloc = build()..add(const LoadArena(viewerId: me));
    final first = await loaded(bloc);
    expect(first.current!.id, 'bad');

    await moderation.reportPost(
      post: first.current!,
      reason: ReportReason.inappropriate,
      reporterId: me,
    );
    final after = await bloc.stream
        .firstWhere((s) => s is ArenaLoaded && s.current?.id != 'bad');
    expect((after as ArenaLoaded).current!.id, 'next');
    expect(remaining(after), ['next']);
    expect(store.reports.single['postId'], 'bad');
    await bloc.close();
  });

  test('blocking an author drops every one of their posts from the queue',
      () async {
    await seed([
      post(id: 't1', userId: 'troll', minutesOld: 1),
      post(id: 'ok1', userId: 'friend', minutesOld: 2),
      post(id: 't2', userId: 'troll', minutesOld: 3),
      post(id: 'ok2', userId: 'friend', minutesOld: 4),
    ]);
    final bloc = build()..add(const LoadArena(viewerId: me));
    final first = await loaded(bloc);
    expect(first.current!.id, 't1');

    await moderation.blockAuthorOf(first.current!, uid: me);
    final after = await bloc.stream
        .firstWhere((s) => s is ArenaLoaded && !remaining(s).contains('t1'));
    expect(remaining(after as ArenaLoaded), ['ok1', 'ok2']);
    expect(store.blocked[me], ['troll']);

    // A new post by the blocked author later on stays out as well.
    await repo.createPost(post(id: 't3', userId: 'troll', minutesOld: 0));
    await Future<void>.delayed(Duration.zero);
    expect(remaining(bloc.state as ArenaLoaded), isNot(contains('t3')));
    await bloc.close();
  });

  test('unblocking brings the author\'s posts back', () async {
    await cache.write(me, const ModerationSnapshot(blocked: {'troll'}));
    store.blocked[me] = ['troll'];
    await seed([
      post(id: 't1', userId: 'troll', minutesOld: 1),
      post(id: 'ok', userId: 'friend', minutesOld: 2),
    ]);
    final bloc = build()..add(const LoadArena(viewerId: me));
    expect(remaining(await loaded(bloc)), ['ok']);

    await moderation.unblock('troll', uid: me);
    final after = await bloc.stream
        .firstWhere((s) => s is ArenaLoaded && remaining(s).contains('t1'));
    expect(remaining(after as ArenaLoaded), containsAll(['t1', 'ok']));
    await bloc.close();
  });

  test('blocking the last post\'s author ends the queue, not an error',
      () async {
    await seed([post(id: 't1', userId: 'troll', minutesOld: 1)]);
    final bloc = build()..add(const LoadArena(viewerId: me));
    final first = await loaded(bloc);
    await moderation.blockAuthorOf(first.current!, uid: me);
    final after = await bloc.stream
        .firstWhere((s) => s is ArenaLoaded && s.isDone || s is ArenaEmpty);
    expect(after, anyOf(isA<ArenaEmpty>(), isA<ArenaLoaded>()));
    await bloc.close();
  });

  test('blocking one house persona keeps the other personas in the queue',
      () async {
    await seed([
      post(
          id: 'h1',
          userId: 'house',
          displayName: 'Greg',
          isHouse: true,
          minutesOld: 1),
      post(
          id: 'h2',
          userId: 'house',
          displayName: 'Alex',
          isHouse: true,
          minutesOld: 2),
    ]);
    final bloc = build()..add(const LoadArena(viewerId: me));
    final first = await loaded(bloc);
    final greg = first.queue.firstWhere((p) => p.id == 'h1');
    await moderation.blockAuthorOf(greg, uid: me);
    final after = await bloc.stream
        .firstWhere((s) => s is ArenaLoaded && !remaining(s).contains('h1'));
    expect(remaining(after as ArenaLoaded), ['h2']);
    await bloc.close();
  });

  test('a post the server took down (hidden: true) is skipped', () async {
    await seed([post(id: 'ok', userId: 'friend', minutesOld: 2)]);
    await source.createPost({
      ...post(id: 'down', userId: 'troll', minutesOld: 1).toMap(),
      'hidden': true,
    });
    final bloc = build()..add(const LoadArena(viewerId: me));
    expect(remaining(await loaded(bloc)), ['ok']);
    await bloc.close();
  });

  test('the zero-post tease is filtered too', () async {
    await cache.write(me, const ModerationSnapshot(blocked: {'troll'}));
    store.blocked[me] = ['troll'];
    await repo.createPost(post(id: 't1', userId: 'troll'));
    await repo.createPost(post(id: 'ok', userId: 'friend'));
    final bloc = build()..add(const LoadArena(viewerId: me));
    final tease =
        await bloc.stream.firstWhere((s) => s is ArenaTeaser) as ArenaTeaser;
    expect(tease.posts.map((p) => p.id), ['ok']);

    await moderation.reportPost(
        post: tease.posts.single, reason: ReportReason.spam, reporterId: me);
    final after = await bloc.stream
        .firstWhere((s) => s is ArenaTeaser && s.posts.isEmpty) as ArenaTeaser;
    expect(after.posts, isEmpty);
    await bloc.close();
  });

  test('without a moderation service nothing is filtered (old behaviour)',
      () async {
    await seed([post(id: 't1', userId: 'troll')]);
    final bloc = ArenaBloc(feedRepository: repo, teaserTaskId: 'starter-01')
      ..add(const LoadArena(viewerId: me));
    expect(remaining(await loaded(bloc)), ['t1']);
    await bloc.close();
  });
}
