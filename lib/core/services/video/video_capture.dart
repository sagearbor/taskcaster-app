import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

/// A clip the player just recorded (or picked), ready to upload.
///
/// The bytes are whatever the OS recorder produced — we never re-encode on the
/// client. `VideoPolicy.maxUploadBytes` is the control that keeps that honest,
/// and the recorder's own `maxDuration` is the auto-trim: there is no trim UI
/// anywhere in the app.
class PickedVideo {
  final Uint8List bytes;

  /// MIME type to store the object as, e.g. `video/mp4`.
  final String contentType;

  /// The picker's file name, when it gave us one. Diagnostics only.
  final String? fileName;

  /// Where the picker put the clip: a filesystem path on iOS/Android, a
  /// `blob:` URL on web. Used ONLY to play the local preview before posting
  /// (see `localVideoController`); the upload always goes from [bytes].
  final String? sourcePath;

  const PickedVideo({
    required this.bytes,
    required this.contentType,
    this.fileName,
    this.sourcePath,
  });

  int get byteCount => bytes.length;
}

/// Recording a clip for an Arena post.
///
/// Returns null when the player backs out, the camera is missing, or the
/// permission is denied — all the same thing as far as the flow cares.
///
/// This and [PhotoCapture] are the ONLY files that call into `image_picker`,
/// which keeps the plugin's web/native surface in one well-understood place.
abstract class VideoCapture {
  /// [maxSeconds] is handed straight to the recorder as its `maxDuration`:
  /// that IS the auto-trim, done before a byte is uploaded.
  Future<PickedVideo?> pick({
    required bool fromCamera,
    required int maxSeconds,
  });
}

/// The real thing, on every platform image_picker supports.
class ImagePickerVideoCapture implements VideoCapture {
  final ImagePicker _picker;

  ImagePickerVideoCapture({ImagePicker? picker})
      : _picker = picker ?? ImagePicker();

  /// What we store a clip as when nothing better is known.
  static const String defaultContentType = 'video/mp4';

  @override
  Future<PickedVideo?> pick({
    required bool fromCamera,
    required int maxSeconds,
  }) async {
    try {
      final file = await _picker.pickVideo(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        maxDuration: Duration(seconds: maxSeconds),
        preferredCameraDevice: CameraDevice.rear,
      );
      if (file == null) return null;
      final bytes = await file.readAsBytes();
      return PickedVideo(
        bytes: bytes,
        contentType: contentTypeFor(file.mimeType, file.name),
        fileName: file.name,
        sourcePath: file.path,
      );
    } catch (e) {
      // A missing camera, a denied permission or a cancelled picker are all
      // "no clip this time" as far as the player is concerned.
      debugPrint('ImagePickerVideoCapture.pick failed: $e');
      return null;
    }
  }

  /// The MIME type to upload with: what the picker reported, else inferred
  /// from the extension, else [defaultContentType]. Storage rules only require
  /// `video/*`, so a wrong-but-plausible guess still uploads.
  @visibleForTesting
  static String contentTypeFor(String? mimeType, String? fileName) {
    final reported = mimeType?.trim() ?? '';
    if (reported.isNotEmpty) return reported;

    final name = (fileName ?? '').toLowerCase();
    if (name.endsWith('.mov')) return 'video/quicktime';
    if (name.endsWith('.webm')) return 'video/webm';
    return defaultContentType;
  }
}

/// Test / mock-mode double. Hands back whatever it was built with (null = the
/// player cancelled), and records how it was called.
class FakeVideoCapture implements VideoCapture {
  final PickedVideo? video;

  /// Every `(fromCamera, maxSeconds)` pair [pick] has been called with,
  /// oldest first.
  final List<({bool fromCamera, int maxSeconds})> calls = [];

  FakeVideoCapture([this.video]);

  @override
  Future<PickedVideo?> pick({
    required bool fromCamera,
    required int maxSeconds,
  }) async {
    calls.add((fromCamera: fromCamera, maxSeconds: maxSeconds));
    return video;
  }
}
