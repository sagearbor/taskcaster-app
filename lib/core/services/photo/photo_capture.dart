import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

/// Grabbing a photo for an Arena post.
///
/// The result is already downscaled and re-encoded so it can be stored inline
/// (base64) in the post document: JPEG, <= 720 px on the long edge, quality
/// ~70, which lands around 60-150 KB. Returns null when the player backs out.
///
/// This is the ONLY file in the app that imports `image_picker`, which keeps
/// the plugin's web/native surface in one well-understood place.
abstract class PhotoCapture {
  Future<Uint8List?> pick({required bool fromCamera});
}

/// The real thing, on every platform image_picker supports.
class ImagePickerPhotoCapture implements PhotoCapture {
  final ImagePicker _picker;

  ImagePickerPhotoCapture({ImagePicker? picker})
      : _picker = picker ?? ImagePicker();

  /// Long-edge cap, in pixels.
  static const double maxEdge = 720;

  /// JPEG quality (0-100).
  static const int quality = 70;

  @override
  Future<Uint8List?> pick({required bool fromCamera}) async {
    try {
      final file = await _picker.pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        maxWidth: maxEdge,
        maxHeight: maxEdge,
        imageQuality: quality,
      );
      if (file == null) return null;
      return await file.readAsBytes();
    } catch (e) {
      // A missing camera, a denied permission or a cancelled picker are all
      // "no photo this time" as far as the player is concerned.
      debugPrint('ImagePickerPhotoCapture.pick failed: $e');
      return null;
    }
  }
}

/// Test / mock-mode double. Hands back whatever bytes it was built with (null
/// = the player cancelled), and records how it was called.
class FakePhotoCapture implements PhotoCapture {
  final Uint8List? bytes;

  /// Every `fromCamera` value [pick] has been called with, oldest first.
  final List<bool> calls = <bool>[];

  FakePhotoCapture([this.bytes]);

  @override
  Future<Uint8List?> pick({required bool fromCamera}) async {
    calls.add(fromCamera);
    return bytes;
  }
}
