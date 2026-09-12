import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/models/submission.dart';
import 'package:taskcaster_app/features/arena/data/datasources/mock_feed_data_source.dart';
import 'package:taskcaster_app/features/arena/data/repositories/feed_repository_impl.dart';
import 'package:taskcaster_app/features/arena/domain/models/feed_post.dart';
import 'package:taskcaster_app/features/arena/presentation/bloc/arena_bloc.dart';
import 'package:taskcaster_app/features/arena/presentation/bloc/arena_event.dart';
import 'package:taskcaster_app/features/arena/presentation/bloc/arena_state.dart';

const me = 'me';

FeedPost post({
  required String id,
  String userId = 'other',
  String taskId = 'starter-01',
  int minutesOld = 0,
}) {
  return FeedPost(
    id: id,
    gameId: 'game-1',
    taskId: taskId,
    taskTitle: 'Task $taskId',
    rubric: 'Grade it.',
    userId: userId,
    displayName: userId,
    mediaType: SubmissionMediaType.text,
    text: 'An attempt',
    createdAt: DateTime.parse('2026-09-12T12:00:00.000Z')
        .subtract(Duration(minutes: minutesOld)),
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

  /// A viewer who has unlocked starter-01 (they posted there) plus [others]
  /// waiting to be graded.
  Future<void> seedUnlockedWith(int others) async {
    await repo.createPost(post(id: 'mine', userId: me, minutesOld: 90));
    for (var i = 0; i < others; i++) {
      await repo.createPost(post(id: 'p$i', userId: 'user-$i', minutesOld: i));
    }
  }

  group('LoadArena', () {
    blocTest<ArenaBloc, ArenaState>(
      'a viewer who has posted nothing gets ArenaEmpty(nothingUnlocked: true)',
      build: () => ArenaBloc(feedRepository: repo),
      act: (bloc) => bloc.add(const LoadArena(viewerId: me)),
      expect: () => [
        const ArenaLoading(),
        const ArenaEmpty(nothingUnlocked: true),
      ],
    );

    blocTest<ArenaBloc, ArenaState>(
      'a viewer who has unlocked a task but has nothing left to grade gets '
      'ArenaEmpty(nothingUnlocked: false)',
      setUp: () async {
        await repo.createPost(post(id: 'mine', userId: me));
      },
      build: () => ArenaBloc(feedRepository: repo),
      act: (bloc) => bloc.add(const LoadArena(viewerId: me)),
      expect: () => [
        const ArenaLoading(),
        const ArenaEmpty(nothingUnlocked: false),
      ],
    );

    blocTest<ArenaBloc, ArenaState>(
      'loads the gated, ordered queue',
      setUp: () => seedUnlockedWith(3),
      build: () => ArenaBloc(feedRepository: repo),
      act: (bloc) => bloc.add(const LoadArena(viewerId: me)),
      verify: (bloc) {
        final state = bloc.state as ArenaLoaded;
        expect(state.index, 0);
        expect(state.queue.map((p) => p.id), ['p0', 'p1', 'p2']);
        expect(state.current!.id, 'p0');
        expect(state.isDone, isFalse);
        expect(state.gradedThisSession, 0);
      },
    );

    blocTest<ArenaBloc, ArenaState>(
      'never queues the viewer\'s own post',
      setUp: () => seedUnlockedWith(1),
      build: () => ArenaBloc(feedRepository: repo),
      act: (bloc) => bloc.add(const LoadArena(viewerId: me)),
      verify: (bloc) {
        final state = bloc.state as ArenaLoaded;
        expect(state.queue.every((p) => p.userId != me), isTrue);
      },
    );

    blocTest<ArenaBloc, ArenaState>(
      'only shows posts for tasks the viewer has unlocked',
      setUp: () async {
        await repo.createPost(post(id: 'mine', userId: me));
        await repo.createPost(post(id: 'visible', userId: 'a'));
        await repo
            .createPost(post(id: 'locked', userId: 'b', taskId: 'starter-09'));
      },
      build: () => ArenaBloc(feedRepository: repo),
      act: (bloc) => bloc.add(const LoadArena(viewerId: me)),
      verify: (bloc) {
        final state = bloc.state as ArenaLoaded;
        expect(state.queue.map((p) => p.id), ['visible']);
      },
    );

    blocTest<ArenaBloc, ArenaState>(
      'starts from the viewer\'s all-time grade count',
      setUp: () async {
        await seedUnlockedWith(2);
        await repo.gradePost(postId: 'p0', graderId: me, score: 4);
      },
      build: () => ArenaBloc(feedRepository: repo),
      act: (bloc) => bloc.add(const LoadArena(viewerId: me)),
      verify: (bloc) {
        final state = bloc.state as ArenaLoaded;
        expect(state.totalGradedByMe, 1);
        expect(state.gradedThisSession, 0);
        // The post they already graded is gone from the queue.
        expect(state.queue.map((p) => p.id), ['p1']);
      },
    );
  });

  group('GradeCurrent', () {
    blocTest<ArenaBloc, ArenaState>(
      'records the grade and advances',
      setUp: () => seedUnlockedWith(3),
      build: () => ArenaBloc(feedRepository: repo),
      act: (bloc) async {
        bloc.add(const LoadArena(viewerId: me));
        await Future<void>.delayed(Duration.zero);
        bloc.add(const GradeCurrent(score: 5));
      },
      wait: const Duration(milliseconds: 50),
      verify: (bloc) async {
        final state = bloc.state as ArenaLoaded;
        expect(state.index, 1);
        expect(state.gradedThisSession, 1);
        expect(state.totalGradedByMe, 1);
        expect(state.current!.id, 'p1');

        final graded = await repo.watchPost('p0').first;
        expect(graded!.gradeCount, 1);
        expect(graded.gradeSum, 5);
      },
    );

    blocTest<ArenaBloc, ArenaState>(
      'keeps index stable across the live re-emit the grade itself causes',
      setUp: () => seedUnlockedWith(3),
      build: () => ArenaBloc(feedRepository: repo),
      act: (bloc) async {
        bloc.add(const LoadArena(viewerId: me));
        await Future<void>.delayed(Duration.zero);
        bloc.add(const GradeCurrent(score: 3));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      },
      wait: const Duration(milliseconds: 50),
      verify: (bloc) {
        final state = bloc.state as ArenaLoaded;
        // p0 stays pinned at the front even though the query no longer
        // returns it, so index 1 still means "the second post".
        expect(state.queue.first.id, 'p0');
        expect(state.index, 1);
        expect(state.current!.id, 'p1');
      },
    );

    blocTest<ArenaBloc, ArenaState>(
      'advances past a post the store rejects instead of getting stuck',
      setUp: () async {
        await seedUnlockedWith(2);
        // Somebody else's session already graded p0 as us.
        await repo.gradePost(postId: 'p0', graderId: 'ghost', score: 2);
      },
      build: () => ArenaBloc(feedRepository: repo),
      act: (bloc) async {
        bloc.add(const LoadArena(viewerId: me));
        await Future<void>.delayed(Duration.zero);
        // Grade twice in a row: the second grade for the same post would be
        // rejected, and the queue must still move on.
        bloc.add(const GradeCurrent(score: 4));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const GradeCurrent(score: 4));
      },
      wait: const Duration(milliseconds: 60),
      verify: (bloc) {
        final state = bloc.state as ArenaLoaded;
        expect(state.index, 2);
        expect(state.isDone, isTrue);
        expect(state.current, isNull);
      },
    );

    blocTest<ArenaBloc, ArenaState>(
      'boosts the viewer\'s own posts once they have graded three',
      setUp: () => seedUnlockedWith(3),
      build: () => ArenaBloc(feedRepository: repo),
      act: (bloc) async {
        bloc.add(const LoadArena(viewerId: me));
        await Future<void>.delayed(Duration.zero);
        for (var i = 0; i < 3; i++) {
          bloc.add(const GradeCurrent(score: 4));
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      },
      wait: const Duration(milliseconds: 80),
      verify: (bloc) async {
        final state = bloc.state as ArenaLoaded;
        expect(state.gradedThisSession, 3);
        expect(state.justEarnedBoost, isTrue);
        expect((await repo.watchPost('mine').first)!.boosted, isTrue);
      },
    );

    blocTest<ArenaBloc, ArenaState>(
      'does not boost before the third grade',
      setUp: () => seedUnlockedWith(3),
      build: () => ArenaBloc(feedRepository: repo),
      act: (bloc) async {
        bloc.add(const LoadArena(viewerId: me));
        await Future<void>.delayed(Duration.zero);
        bloc.add(const GradeCurrent(score: 4));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const GradeCurrent(score: 4));
      },
      wait: const Duration(milliseconds: 60),
      verify: (bloc) async {
        expect((bloc.state as ArenaLoaded).justEarnedBoost, isFalse);
        expect((await repo.watchPost('mine').first)!.boosted, isFalse);
      },
    );

    blocTest<ArenaBloc, ArenaState>(
      'is ignored once the queue is done',
      setUp: () => seedUnlockedWith(1),
      build: () => ArenaBloc(feedRepository: repo),
      act: (bloc) async {
        bloc.add(const LoadArena(viewerId: me));
        await Future<void>.delayed(Duration.zero);
        bloc.add(const GradeCurrent(score: 4));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const GradeCurrent(score: 4));
      },
      wait: const Duration(milliseconds: 60),
      verify: (bloc) {
        final state = bloc.state as ArenaLoaded;
        expect(state.index, 1);
        expect(state.gradedThisSession, 1);
      },
    );
  });

  group('SkipCurrent', () {
    blocTest<ArenaBloc, ArenaState>(
      'advances without grading anything',
      setUp: () => seedUnlockedWith(2),
      build: () => ArenaBloc(feedRepository: repo),
      act: (bloc) async {
        bloc.add(const LoadArena(viewerId: me));
        await Future<void>.delayed(Duration.zero);
        bloc.add(const SkipCurrent());
      },
      wait: const Duration(milliseconds: 40),
      verify: (bloc) async {
        final state = bloc.state as ArenaLoaded;
        expect(state.index, 1);
        expect(state.gradedThisSession, 0);
        expect((await repo.watchPost('p0').first)!.gradeCount, 0);
      },
    );
  });

  group('TapCurrent', () {
    blocTest<ArenaBloc, ArenaState>(
      'increments the current post\'s taps without moving the queue',
      setUp: () => seedUnlockedWith(2),
      build: () => ArenaBloc(feedRepository: repo),
      act: (bloc) async {
        bloc.add(const LoadArena(viewerId: me));
        await Future<void>.delayed(Duration.zero);
        bloc.add(const TapCurrent());
      },
      wait: const Duration(milliseconds: 40),
      verify: (bloc) async {
        expect((bloc.state as ArenaLoaded).index, 0);
        expect((await repo.watchPost('p0').first)!.tapCount, 1);
      },
    );
  });

  group('ArenaLoaded', () {
    test('adEvery is the documented cadence', () {
      expect(ArenaLoaded.adEvery, 6);
    });

    test('isDone / current track the index', () {
      final queue = [post(id: 'a'), post(id: 'b')];
      const base = ArenaLoaded(
        queue: [],
        index: 0,
        gradedThisSession: 0,
        totalGradedByMe: 0,
      );
      expect(base.copyWith(queue: queue).current!.id, 'a');
      expect(base.copyWith(queue: queue, index: 1).current!.id, 'b');
      expect(base.copyWith(queue: queue, index: 2).current, isNull);
      expect(base.copyWith(queue: queue, index: 2).isDone, isTrue);
    });

    test('justEarnedBoost fires on exactly the third grade of a session', () {
      const base = ArenaLoaded(
        queue: [],
        index: 0,
        gradedThisSession: 0,
        totalGradedByMe: 0,
      );
      expect(base.copyWith(gradedThisSession: 2).justEarnedBoost, isFalse);
      expect(base.copyWith(gradedThisSession: 3).justEarnedBoost, isTrue);
      expect(base.copyWith(gradedThisSession: 4).justEarnedBoost, isFalse);
    });
  });
}
