import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/models/submission.dart';
import 'package:taskcaster_app/features/arena/domain/models/feed_post.dart';

FeedPost _videoPost() => FeedPost(
      id: 'p1',
      gameId: 'game-1',
      taskId: 'starter-01',
      taskTitle: 'Egg on a spoon, to the far wall and back',
      rubric: 'Distance covered before disaster, then narration.',
      userId: 'user-1',
      displayName: 'Sophie',
      mediaType: SubmissionMediaType.video,
      videoUrl: 'https://cdn.test/clip.mp4',
      videoStoragePath: 'submissions/user-1/20260912/3',
      videoBytes: 4 * 1024 * 1024,
      videoContentType: 'video/quicktime',
      videoDurationSeconds: 18.5,
      clockOffsetSeconds: 7,
      timerSeconds: 30,
      caption: 'Nature documentary · Done in 22 s',
      stamp: 'NO REGRETS',
      createdAt: DateTime.utc(2026, 9, 12, 12),
      elapsedSeconds: 22,
      tapCount: 5,
      tapSeconds: const {'3': 2, '11': 3},
    );

void main() {
  group('FeedPost video fields', () {
    test('round-trip through toMap/fromMap keeps every clip field', () {
      final post = _videoPost();
      final restored = FeedPost.fromMap(post.toMap());

      expect(restored, post);
      expect(restored.mediaType, SubmissionMediaType.video);
      expect(restored.videoUrl, 'https://cdn.test/clip.mp4');
      expect(restored.videoStoragePath, 'submissions/user-1/20260912/3');
      expect(restored.videoBytes, 4 * 1024 * 1024);
      expect(restored.videoContentType, 'video/quicktime');
      expect(restored.videoDurationSeconds, 18.5);
      expect(restored.clockOffsetSeconds, 7);
      expect(restored.timerSeconds, 30);
      expect(restored.tapSeconds, {'3': 2, '11': 3});
    });

    test('a document written before in-app video existed still parses', () {
      final legacy = <String, dynamic>{
        'id': 'old',
        'gameId': 'g',
        'taskId': 't',
        'taskTitle': 'Old task',
        'userId': 'u',
        'displayName': 'Someone',
        'mediaType': 'photo',
        'photoData': 'AAAA',
        'createdAt': '2026-01-01T00:00:00.000Z',
        'tapCount': 2,
      };

      final post = FeedPost.fromMap(legacy);

      expect(post.mediaType, SubmissionMediaType.photo);
      expect(post.tapCount, 2);
      expect(post.tapSeconds, isEmpty);
      expect(post.videoStoragePath, isNull);
      expect(post.videoBytes, isNull);
      expect(post.videoContentType, isNull);
      expect(post.videoDurationSeconds, isNull);
      expect(post.clockOffsetSeconds, isNull);
      expect(post.timerSeconds, isNull);
    });

    test('tapSeconds parses the numeric keys Firestore hands back', () {
      // FieldValue.increment on 'tapSeconds.4' produces a nested map whose
      // values arrive as num, not int.
      final post = FeedPost.fromMap(const {
        'id': 'p',
        'mediaType': 'video',
        'createdAt': '2026-01-01T00:00:00.000Z',
        'tapSeconds': <dynamic, dynamic>{4: 1, '9': 2.0},
      });

      expect(post.tapSeconds, {'4': 1, '9': 2});
    });

    test('copyWith carries the clip fields through', () {
      final post = _videoPost().copyWith(tapCount: 9);
      expect(post.tapCount, 9);
      expect(post.videoStoragePath, 'submissions/user-1/20260912/3');
      expect(post.timerSeconds, 30);
    });

    test('an mp4 link post and a clip differ only by mediaType', () {
      final clip = _videoPost();
      final link = clip.copyWith(mediaType: SubmissionMediaType.link);
      // Both carry the URL in videoUrl; the medium is what distinguishes them.
      expect(link.videoUrl, clip.videoUrl);
      expect(link == clip, isFalse);
    });
  });

  group('Submission video fields', () {
    test('round-trips and defaults to null on an old row', () {
      final submission = Submission(
        id: 's1',
        userId: 'user-1',
        score: 0,
        isJudged: false,
        submittedAt: DateTime.utc(2026, 9, 12),
        mediaType: SubmissionMediaType.video,
        videoUrl: 'https://cdn.test/clip.mp4',
        videoStoragePath: 'submissions/user-1/20260912/0',
        videoBytes: 1024,
        videoContentType: 'video/mp4',
        videoDurationSeconds: 9.25,
        clockOffsetSeconds: 3,
        timerSeconds: 60,
      );

      expect(Submission.fromMap(submission.toMap()), submission);

      final legacy = Submission.fromMap(const {
        'id': 's0',
        'userId': 'u',
        'score': 0,
        'isJudged': false,
        'submittedAt': '2026-01-01T00:00:00.000Z',
      });
      expect(legacy.mediaType, SubmissionMediaType.link);
      expect(legacy.videoStoragePath, isNull);
      expect(legacy.videoBytes, isNull);
      expect(legacy.clockOffsetSeconds, isNull);
      expect(legacy.timerSeconds, isNull);
    });
  });
}
