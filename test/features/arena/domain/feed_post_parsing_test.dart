import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/models/submission.dart';
import 'package:taskcaster_app/features/arena/data/repositories/feed_repository_impl.dart';
import 'package:taskcaster_app/features/arena/domain/models/feed_post.dart';

/// FeedPost.fromMap must never throw on a bad document: one malformed post
/// would otherwise error the Arena stream for every viewer.
void main() {
  group('FeedPost.fromMap createdAt', () {
    final when = DateTime.utc(2026, 11, 5, 12, 30);

    test('reads a Firestore Timestamp (what new posts carry)', () {
      final p = FeedPost.fromMap({'createdAt': Timestamp.fromDate(when)});
      expect(p.createdAt.toUtc(), when);
    });

    test('reads a legacy ISO-8601 string', () {
      final p = FeedPost.fromMap({'createdAt': when.toIso8601String()});
      expect(p.createdAt, when);
    });

    test('reads a DateTime and epoch millis', () {
      expect(FeedPost.fromMap({'createdAt': when}).createdAt, when);
      expect(
        FeedPost.fromMap({'createdAt': when.millisecondsSinceEpoch})
            .createdAt
            .toUtc(),
        when,
      );
    });

    test('missing, pending (null), unparseable or wrong-typed -> epoch', () {
      for (final v in [null, 'not a date', 12.5, true, const <String>[]]) {
        expect(
          FeedPost.fromMap({'createdAt': v}).createdAt,
          FeedPost.unknownCreatedAt,
          reason: '$v',
        );
      }
    });
  });

  group('FeedPost.fromMap is defensive', () {
    test('a document of junk parses to defaults instead of throwing', () {
      final p = FeedPost.fromMap(const {
        'id': 7,
        'gameId': ['x'],
        'taskId': null,
        'userId': {'a': 1},
        'displayName': 42,
        'mediaType': 3,
        'photoData': 1,
        'isLate': 'yes',
        'isHouse': 1,
        'gradeCount': 'three',
        'gradeSum': <String, dynamic>{},
        'boosted': 'true',
        'tapCount': 'lots',
        'tapSeconds': ['nope'],
        'graderIds': 'me',
        'elapsedSeconds': 'ten',
        'videoDurationSeconds': 'long',
        'videoBytes': 'big',
      });
      expect(p.id, '');
      expect(p.gameId, '');
      expect(p.userId, '');
      expect(p.displayName, '');
      expect(p.mediaType, SubmissionMediaType.link);
      expect(p.photoData, isNull);
      expect(p.isLate, isFalse);
      expect(p.isHouse, isFalse);
      expect(p.gradeCount, 0);
      expect(p.gradeSum, 0);
      expect(p.boosted, isFalse);
      expect(p.tapCount, 0);
      expect(p.tapSeconds, isEmpty);
      expect(p.graderIds, isEmpty);
      expect(p.elapsedSeconds, isNull);
      expect(p.videoDurationSeconds, isNull);
      expect(p.videoBytes, isNull);
    });

    test('numbers stored as doubles are read as ints', () {
      final p = FeedPost.fromMap(const {
        'gradeCount': 2.0,
        'gradeSum': 7.0,
        'tapCount': 3.0,
        'elapsedSeconds': 41.0,
        'timerSeconds': 60.0,
        'clockOffsetSeconds': 4.0,
        'tapSeconds': {'3': 2.0, 4: 1, 'junk': 'x'},
      });
      expect(p.gradeCount, 2);
      expect(p.gradeSum, 7);
      expect(p.tapCount, 3);
      expect(p.elapsedSeconds, 41);
      expect(p.timerSeconds, 60);
      expect(p.clockOffsetSeconds, 4);
      expect(p.tapSeconds, {'3': 2, '4': 1});
    });

    test('graderIds keeps only the string entries', () {
      final p = FeedPost.fromMap(const {
        'graderIds': ['a', 3, null, 'b'],
      });
      expect(p.graderIds, ['a', 'b']);
    });
  });

  test('FeedRepositoryImpl.parseRows keeps every parseable row', () {
    final posts = FeedRepositoryImpl.parseRows([
      {'id': 'a', 'createdAt': '2026-01-01T00:00:00Z'},
      {'id': 'b', 'createdAt': 99.9, 'gradeCount': 'x'},
    ]);
    expect(posts.map((p) => p.id), ['a', 'b']);
  });
}
