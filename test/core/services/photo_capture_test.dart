import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/services/photo/photo_capture.dart';

void main() {
  group('FakePhotoCapture', () {
    test('hands back the bytes it was built with', () async {
      final bytes = Uint8List.fromList(const [1, 2, 3]);
      final capture = FakePhotoCapture(bytes);
      expect(await capture.pick(fromCamera: true), bytes);
    });

    test('returns null when there are no bytes — the player cancelled',
        () async {
      expect(await FakePhotoCapture().pick(fromCamera: false), isNull);
    });

    test('records how it was called', () async {
      final capture = FakePhotoCapture(Uint8List(1));
      await capture.pick(fromCamera: true);
      await capture.pick(fromCamera: false);
      expect(capture.calls, [true, false]);
    });
  });

  group('ImagePickerPhotoCapture', () {
    test('caps photos at the documented size and quality', () {
      expect(ImagePickerPhotoCapture.maxEdge, 720);
      expect(ImagePickerPhotoCapture.quality, 70);
    });

    test('is a PhotoCapture', () {
      expect(ImagePickerPhotoCapture(), isA<PhotoCapture>());
    });
  });
}
