import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/models/submission.dart';
import '../../../../core/models/task.dart';
import '../../../tasks/data/datasources/starter_pack_data.dart';
import '../../domain/models/feed_post.dart';
import '../../domain/repositories/feed_repository.dart';
import '../datasources/feed_remote_data_source.dart';

class FeedRepositoryImpl implements FeedRepository {
  final FeedRemoteDataSource remoteDataSource;

  FeedRepositoryImpl(this.remoteDataSource);

  /// Uid the seeded entries are posted under.
  static const String houseUserId = 'house';

  /// Deterministic document id for a task's house entry, so seeding twice
  /// overwrites rather than duplicates.
  static String houseIdFor(String taskId) => 'house-$taskId';

  /// Posts with this many grades or more are already well fed, so boosting
  /// skips them.
  static const int boostBelowGrades = 3;

  @override
  Future<String> createPost(FeedPost post) {
    final data = post.toMap();
    if (post.id.isEmpty) data.remove('id');
    return remoteDataSource.createPost(data);
  }

  /// The most raw rows per task-id chunk the queue will read while looking
  /// for [limit] postable entries before giving up and showing what it has.
  static const int maxQueueFetch = 300;

  /// Parse rows, dropping (and logging) any that will not parse, so one
  /// malformed document can never error the stream for every viewer.
  static List<FeedPost> parseRows(Iterable<Map<String, dynamic>> rows) {
    final posts = <FeedPost>[];
    for (final row in rows) {
      final post = tryParse(row);
      if (post != null) posts.add(post);
    }
    return posts;
  }

  /// One row, or null when it will not parse.
  static FeedPost? tryParse(Map<String, dynamic> row) {
    try {
      return FeedPost.fromMap(row);
    } catch (e) {
      debugPrint('FeedRepository: skipping unreadable post ${row['id']}: $e');
      return null;
    }
  }

  /// Paged: the server returns the unlocked tasks' posts fewest-grades-first
  /// (so old ungraded entries are never buried under newer graded ones), and
  /// when the own-post/already-graded exclusions leave fewer than [limit]
  /// entries while more rows exist, the read is reopened [limit] rows larger,
  /// up to [maxQueueFetch].
  @override
  Stream<List<FeedPost>> watchQueue({
    required String viewerId,
    required Set<String> unlockedTaskIds,
    int limit = 30,
  }) {
    if (unlockedTaskIds.isEmpty) {
      return Stream.value(const <FeedPost>[]);
    }
    final taskIds = unlockedTaskIds.toList()..sort();

    late final StreamController<List<FeedPost>> controller;
    StreamSubscription<QueuePage>? sub;
    var fetch = limit;

    void open() {
      sub?.cancel();
      sub = remoteDataSource
          .watchQueuePage(taskIds: taskIds, limit: fetch)
          .listen((page) {
        final posts = parseRows(page.rows).where((p) {
          // REVEAL GATING: you only see a task's entries once you've posted
          // yours (the query already filters on taskId; this is a backstop).
          if (!unlockedTaskIds.contains(p.taskId)) return false;
          // Never your own post, never one you've already graded.
          if (p.userId == viewerId) return false;
          if (p.graderIds.contains(viewerId)) return false;
          // A post its owner made private is not the crowd's to grade (the
          // rules refuse a stranger reading it by id).
          if (p.shareable == false) return false;
          return true;
        }).toList()
          ..sort(_queueOrder);

        if (posts.length < limit && page.hasMore && fetch < maxQueueFetch) {
          // Short page with more behind it: read the next page too.
          fetch = (fetch + limit).clamp(0, maxQueueFetch);
          open();
          return;
        }
        controller.add(posts.take(limit).toList());
      }, onError: controller.addError);
    }

    controller = StreamController<List<FeedPost>>(
      onListen: open,
      onCancel: () => sub?.cancel(),
    );
    return controller.stream;
  }

  /// Boosted first, then fewest grades, then most taps, then newest.
  static int _queueOrder(FeedPost a, FeedPost b) {
    if (a.boosted != b.boosted) return a.boosted ? -1 : 1;
    final byGrades = a.gradeCount.compareTo(b.gradeCount);
    if (byGrades != 0) return byGrades;
    final byTaps = b.tapCount.compareTo(a.tapCount);
    if (byTaps != 0) return byTaps;
    return b.createdAt.compareTo(a.createdAt);
  }

  @override
  Stream<List<FeedPost>> watchPostsForTask({
    required String gameId,
    required String taskId,
  }) {
    return remoteDataSource.watchPostsForTask(gameId, taskId).map((rows) {
      final posts = parseRows(rows);
      // Playback order: oldest first, newest last.
      posts.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return posts;
    });
  }

  @override
  Future<void> tapPost(String postId, {int taps = 1, int? atSecond}) =>
      remoteDataSource.tapPost(postId, taps: taps, atSecond: atSecond);

  @override
  Stream<Set<String>> watchUnlockedTaskIds(String userId) {
    // Every submission creates a post, so the user's own posts ARE the record
    // of what they have submitted — no game read needed.
    return remoteDataSource
        .watchPostsByUser(userId)
        .map((rows) => rows
            .map((r) => r['taskId'])
            .whereType<String>()
            .where((id) => id.isNotEmpty)
            .toSet());
  }

  @override
  Future<void> gradePost({
    required String postId,
    required String graderId,
    required int score,
  }) {
    if (score < 1 || score > 5) {
      throw ArgumentError.value(score, 'score', 'Grades run 1..5');
    }
    return remoteDataSource.gradePost(
      postId: postId,
      graderId: graderId,
      score: score,
    );
  }

  @override
  Stream<FeedPost?> watchPost(String postId) {
    return remoteDataSource
        .watchPost(postId)
        .map((row) => row == null ? null : tryParse(row));
  }

  @override
  Stream<List<FeedPost>> watchPostsByUser(String userId) {
    return remoteDataSource.watchPostsByUser(userId).map((rows) {
      final posts = parseRows(rows);
      posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return posts;
    });
  }

  @override
  Future<int> gradedCountBy(String userId) =>
      remoteDataSource.gradedCountBy(userId);

  @override
  Future<void> boostPostsOf(String userId) =>
      remoteDataSource.boostPostsOf(userId, belowGradeCount: boostBelowGrades);

  /// Seeds the in-memory store (mock mode, tests). On Firestore this is a
  /// no-op: house posts are seeded with the Admin SDK
  /// (functions/scripts/seed_house_posts.js).
  @override
  Future<void> ensureHouseEntries() {
    return remoteDataSource.ensureHouseEntries(houseEntryPosts());
  }

  /// The seeded house entries as raw documents, with deterministic ids.
  /// Exposed so tests (and the Firestore source) can assert the exact shape.
  ///
  /// A video task's house entry is a VIDEO post: a short generated clip in the
  /// bucket at `house/<taskId>.mp4`, public-read, with the task countdown
  /// already burned into its pixels (which is why playback skips the overlay
  /// for house entries). Its [FeedPost.text] is kept as the fallback the card
  /// shows if the clip cannot be played. Photo and text tasks keep the text
  /// house entry they have always had.
  static List<Map<String, dynamic>> houseEntryPosts() {
    final tasks = StarterPackData.tasks();
    return [
      for (final task in tasks)
        if (StarterPackData.houseEntries[task.id] != null)
          () {
            final isVideo = task.submissionType == SubmissionType.video;
            return FeedPost(
              id: houseIdFor(task.id),
              gameId: '',
              taskId: task.id,
              taskTitle: task.title,
              rubric: task.rubric,
              userId: houseUserId,
              displayName: StarterPackData.housePosterName,
              mediaType: isVideo
                  ? SubmissionMediaType.video
                  : SubmissionMediaType.text,
              text: StarterPackData.houseEntries[task.id],
              videoUrl: isVideo ? StarterPackData.houseVideoUrl(task.id) : null,
              videoStoragePath:
                  isVideo ? StarterPackData.houseVideoPath(task.id) : null,
              caption: task.twist,
              stamp: Stamps.art,
              isHouse: true,
              // Fixed epoch so the seeds sort last by recency and seeding is
              // byte-for-byte identical every time.
              createdAt: DateTime.utc(2026, 1, 1),
            ).toMap();
          }(),
    ];
  }
}
