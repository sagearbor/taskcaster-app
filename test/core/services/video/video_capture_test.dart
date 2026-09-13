import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/services/video/video_capture.dart';

void main() {
  group('ImagePickerVideoCapture.contentTypeFor', () {
    test('trusts the picker when it reports a MIME type', () {
      expect(
        ImagePickerVideoCapture.contentTypeFor('video/webm', 'clip.mp4'),
        'video/webm',
      );
    });

    test('infers quicktime from a .mov name', () {
      expect(
        ImagePickerVideoCapture.contentTypeFor(null, 'IMG_0042.MOV'),
        'video/quicktime',
      );
    });

    test('infers webm from a .webm name', () {
      expect(
        ImagePickerVideoCapture.contentTypeFor('', 'recording.webm'),
        'video/webm',
      );
    });

    test('falls back to mp4 for anything else', () {
      expect(ImagePickerVideoCapture.contentTypeFor(null, 'clip.mp4'),
          'video/mp4');
      expect(ImagePickerVideoCapture.contentTypeFor(null, null), 'video/mp4');
      expect(ImagePickerVideoCapture.contentTypeFor('  ', 'no-extension'),
          'video/mp4');
    });
  });

  group('PickedVideo', () {
    test('byteCount is the length of the bytes', () {
      final clip = PickedVideo(
        bytes: Uint8List.fromList(List.filled(2048, 7)),
        contentType: 'video/mp4',
      );
      expect(clip.byteCount, 2048);
    });
  });

  group('FakeVideoCapture', () {
    test('returns what it was built with and records every call', () async {
      final clip = PickedVideo(
        bytes: Uint8List.fromList([1, 2, 3]),
        contentType: 'video/mp4',
        fileName: 'a.mp4',
      );
      final capture = FakeVideoCapture(clip);

      expect(
        await capture.pick(fromCamera: true, maxSeconds: 30),
        same(clip),
      );
      await capture.pick(fromCamera: false, maxSeconds: 12);

      expect(capture.calls.length, 2);
      expect(capture.calls.first.fromCamera, isTrue);
      expect(capture.calls.first.maxSeconds, 30);
      expect(capture.calls.last.fromCamera, isFalse);
      expect(capture.calls.last.maxSeconds, 12);
    });

    test('a cancelled pick is null', () async {
      final capture = FakeVideoCapture();
      expect(await capture.pick(fromCamera: true, maxSeconds: 30), isNull);
      expect(capture.calls, hasLength(1));
    });
  });
}
