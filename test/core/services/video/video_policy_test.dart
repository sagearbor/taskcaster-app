import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/services/video/video_policy.dart';

void main() {
  group('VideoPolicy.clipCapSeconds', () {
    test('is the task timer when shorter than the absolute cap', () {
      expect(VideoPolicy.clipCapSeconds(20), 20);
    });
    test('is the absolute cap when the timer is longer', () {
      expect(VideoPolicy.clipCapSeconds(180), VideoPolicy.maxClipSeconds);
    });
    test('is the absolute cap for no timer', () {
      expect(VideoPolicy.clipCapSeconds(null), VideoPolicy.maxClipSeconds);
      expect(VideoPolicy.clipCapSeconds(0), VideoPolicy.maxClipSeconds);
      expect(VideoPolicy.clipCapSeconds(-5), VideoPolicy.maxClipSeconds);
    });
    test('equal timer and cap gives the cap', () {
      expect(VideoPolicy.clipCapSeconds(30), 30);
    });
  });

  group('VideoPolicy.trimmedEndSeconds', () {
    test('trims to the cap', () {
      expect(VideoPolicy.trimmedEndSeconds(47.5, 30), 30.0);
    });
    test('keeps shorter clips whole', () {
      expect(VideoPolicy.trimmedEndSeconds(12.25, 30), 12.25);
    });
    test('unknown duration is null, negative is zero', () {
      expect(VideoPolicy.trimmedEndSeconds(null, 30), isNull);
      expect(VideoPolicy.trimmedEndSeconds(double.nan, 30), isNull);
      expect(VideoPolicy.trimmedEndSeconds(-1, 30), 0);
    });
  });

  group('VideoPolicy upload cap', () {
    test('accepts under the cap, refuses over and empty', () {
      expect(VideoPolicy.fitsUploadCap(1), isTrue);
      expect(VideoPolicy.fitsUploadCap(VideoPolicy.maxUploadBytes), isTrue);
      expect(VideoPolicy.fitsUploadCap(VideoPolicy.maxUploadBytes + 1), isFalse);
      expect(VideoPolicy.fitsUploadCap(0), isFalse);
    });
    test('rejectReason explains size and empty, null when fine', () {
      expect(VideoPolicy.rejectReason(bytes: 5 * 1024 * 1024), isNull);
      expect(VideoPolicy.rejectReason(bytes: 0), contains('empty'));
      expect(VideoPolicy.rejectReason(bytes: VideoPolicy.maxUploadBytes + 1),
          contains('32 MB'));
    });
  });

  group('VideoPolicy storage path', () {
    final when = DateTime.utc(2026, 9, 12, 3, 4, 5);
    test('dayKey is yyyyMMdd in UTC', () {
      expect(VideoPolicy.dayKey(when), '20260912');
      // 23:30 in UTC-4 is 03:30 next day UTC.
      expect(
        VideoPolicy.dayKey(DateTime.parse('2026-09-12T23:30:00-04:00')),
        '20260913',
      );
      expect(VideoPolicy.dayKey(DateTime.utc(2026, 1, 5)), '20260105');
    });
    test('builds submissions/{uid}/{day}/{slot}', () {
      expect(
        VideoPolicy.storagePath(userId: 'u1', when: when, slot: 3),
        'submissions/u1/20260912/3',
      );
    });
    test('slots outside 0..9 and empty uid throw', () {
      expect(() => VideoPolicy.storagePath(userId: 'u1', when: when, slot: 10),
          throwsArgumentError);
      expect(() => VideoPolicy.storagePath(userId: 'u1', when: when, slot: -1),
          throwsArgumentError);
      expect(() => VideoPolicy.storagePath(userId: '', when: when, slot: 0),
          throwsArgumentError);
    });
    test('isValidSlot matches maxUploadsPerDay', () {
      expect(VideoPolicy.isValidSlot(0), isTrue);
      expect(VideoPolicy.isValidSlot(VideoPolicy.maxUploadsPerDay - 1), isTrue);
      expect(VideoPolicy.isValidSlot(VideoPolicy.maxUploadsPerDay), isFalse);
    });
  });

  group('VideoPolicy.tapBucket', () {
    test('floors to the second and clamps to 0..cap', () {
      expect(VideoPolicy.tapBucket(3.9, 30), 3);
      expect(VideoPolicy.tapBucket(-2, 30), 0);
      expect(VideoPolicy.tapBucket(double.nan, 30), 0);
      expect(VideoPolicy.tapBucket(99, 30), 30);
    });
  });
}
