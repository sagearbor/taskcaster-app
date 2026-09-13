import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/services/video/video_policy.dart';
import 'package:taskcaster_app/core/services/video/video_uploader.dart';

FirebaseException _denied([String code = 'unauthorized']) =>
    FirebaseException(plugin: 'firebase_storage', code: code);

void main() {
  final when = DateTime.utc(2026, 9, 12, 14, 30);
  const userId = 'user-1';

  String pathFor(int slot) =>
      VideoPolicy.storagePath(userId: userId, when: when, slot: slot);

  group('FirebaseVideoUploader.uploadToFirstFreeSlot', () {
    test('uses slot 0 when it is free', () async {
      final tried = <String>[];
      final result = await FirebaseVideoUploader.uploadToFirstFreeSlot(
        userId: userId,
        when: when,
        byteCount: 1234,
        attempt: (path) async {
          tried.add(path);
          return 'https://cdn.test/$path';
        },
      );

      expect(tried, [pathFor(0)]);
      expect(result.storagePath, 'submissions/user-1/20260912/0');
      expect(result.downloadUrl, 'https://cdn.test/${pathFor(0)}');
      expect(result.bytes, 1234);
    });

    test('walks past slots the rules refuse (already used today)', () async {
      final tried = <String>[];
      final result = await FirebaseVideoUploader.uploadToFirstFreeSlot(
        userId: userId,
        when: when,
        byteCount: 10,
        attempt: (path) async {
          tried.add(path);
          if (tried.length <= 3) throw _denied();
          return 'https://cdn.test/ok';
        },
      );

      expect(tried, [pathFor(0), pathFor(1), pathFor(2), pathFor(3)]);
      expect(result.storagePath, pathFor(3));
    });

    test("treats 'permission-denied' as a taken slot too", () async {
      var calls = 0;
      final result = await FirebaseVideoUploader.uploadToFirstFreeSlot(
        userId: userId,
        when: when,
        byteCount: 1,
        attempt: (path) async {
          calls++;
          if (calls == 1) throw _denied('permission-denied');
          return 'https://cdn.test/ok';
        },
      );
      expect(calls, 2);
      expect(result.storagePath, pathFor(1));
    });

    test('throws DailyVideoLimitReached once every slot is refused', () async {
      var calls = 0;
      await expectLater(
        FirebaseVideoUploader.uploadToFirstFreeSlot(
          userId: userId,
          when: when,
          byteCount: 1,
          attempt: (_) async {
            calls++;
            throw _denied();
          },
        ),
        throwsA(isA<DailyVideoLimitReached>()),
      );
      // Exactly the daily cap's worth of attempts, no more.
      expect(calls, VideoPolicy.maxUploadsPerDay);
    });

    test('the daily-limit message tells the player what to do instead', () {
      const e = DailyVideoLimitReached();
      expect(e.message, contains('${VideoPolicy.maxUploadsPerDay} clips'));
      expect(e.message, contains('snap a photo'));
      expect(e.toString(), e.message);
    });

    test('a non-denial failure is NOT retried on another slot', () async {
      var calls = 0;
      await expectLater(
        FirebaseVideoUploader.uploadToFirstFreeSlot(
          userId: userId,
          when: when,
          byteCount: 1,
          attempt: (_) async {
            calls++;
            throw FirebaseException(
              plugin: 'firebase_storage',
              code: 'retry-limit-exceeded',
            );
          },
        ),
        throwsA(isA<FirebaseException>()),
      );
      expect(calls, 1);
    });

    test('the path is the UTC day of the upload', () async {
      // 00:30 UTC on the 13th is still "the 12th" locally in the Americas —
      // the bucket path must follow UTC, like the rules do.
      final result = await FirebaseVideoUploader.uploadToFirstFreeSlot(
        userId: userId,
        when: DateTime.utc(2026, 9, 13, 0, 30),
        byteCount: 1,
        attempt: (path) async => 'https://cdn.test/x',
      );
      expect(result.storagePath, 'submissions/user-1/20260913/0');
    });
  });

  group('FakeVideoUploader', () {
    test('emits progress, records the call and returns its result', () async {
      final uploader = FakeVideoUploader();
      final progress = <double>[];

      final result = await uploader.upload(
        userId: 'u',
        bytes: Uint8List.fromList([1, 2, 3]),
        contentType: 'video/mp4',
        when: when,
        metadata: const {'taskId': 'starter-01'},
        onProgress: progress.add,
      );

      expect(progress, [0.25, 0.5, 0.75, 1.0]);
      expect(result.downloadUrl, isNotEmpty);
      expect(uploader.calls.single.userId, 'u');
      expect(uploader.calls.single.bytes, 3);
      expect(uploader.calls.single.metadata, {'taskId': 'starter-01'});
    });

    test('throws what it was configured to throw', () async {
      final uploader = FakeVideoUploader(error: const DailyVideoLimitReached());
      await expectLater(
        uploader.upload(
          userId: 'u',
          bytes: Uint8List.fromList([1]),
          contentType: 'video/mp4',
          when: when,
        ),
        throwsA(isA<DailyVideoLimitReached>()),
      );
    });
  });
}
