import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import 'video_policy.dart';

/// Where a clip ended up.
class VideoUploadResult {
  /// The https URL the player (and everybody grading them) plays.
  final String downloadUrl;

  /// The bucket object path, `submissions/{uid}/{yyyyMMdd}/{slot}`.
  final String storagePath;

  /// Bytes actually written.
  final int bytes;

  const VideoUploadResult({
    required this.downloadUrl,
    required this.storagePath,
    required this.bytes,
  });
}

/// The player has already used every slot they get today.
///
/// This is a *cost control*, not a failure: the Storage rules refuse the
/// eleventh write of the day, and this is how that refusal reaches the player
/// in words they can act on.
class DailyVideoLimitReached implements Exception {
  final String message;

  const DailyVideoLimitReached([
    this.message = "You've posted ${VideoPolicy.maxUploadsPerDay} clips "
        'today — snap a photo instead.',
  ]);

  @override
  String toString() => message;
}

/// Putting a recorded clip in the bucket.
abstract class VideoUploader {
  /// Uploads [bytes] for [userId] and returns where it landed.
  ///
  /// Throws [DailyVideoLimitReached] when the player has no slot left for the
  /// UTC day [when] falls in. Any other failure surfaces as-is.
  Future<VideoUploadResult> upload({
    required String userId,
    required Uint8List bytes,
    required String contentType,
    required DateTime when,
    Map<String, String>? metadata,
    void Function(double fraction)? onProgress,
  });
}

/// Firebase Storage, one slot at a time.
///
/// The daily cap is enforced by the bucket rules, not by a counter we keep:
/// `submissions/{uid}/{yyyyMMdd}/{slot}` is create-only for slots 0..9, so the
/// first slot that is still free is the one that accepts the write and an
/// already-used slot comes back as `unauthorized`. We simply walk 0..9 until
/// one takes. That means no read-before-write, no counter document to keep in
/// step, and no way for a client bug to exceed the cap.
class FirebaseVideoUploader implements VideoUploader {
  final FirebaseStorage _storage;

  FirebaseVideoUploader({FirebaseStorage? storage})
      : _storage = storage ?? FirebaseStorage.instance;

  /// Error codes Storage uses for "the rules said no" — which, for a
  /// create-only path, means the slot is already taken (or the day is full).
  static const Set<String> deniedCodes = {'unauthorized', 'permission-denied'};

  @override
  Future<VideoUploadResult> upload({
    required String userId,
    required Uint8List bytes,
    required String contentType,
    required DateTime when,
    Map<String, String>? metadata,
    void Function(double fraction)? onProgress,
  }) {
    return uploadToFirstFreeSlot(
      userId: userId,
      when: when,
      byteCount: bytes.length,
      attempt: (path) => _putAt(
        path: path,
        bytes: bytes,
        contentType: contentType,
        metadata: metadata,
        onProgress: onProgress,
      ),
    );
  }

  /// Writes one object and returns its download URL. Throws whatever Storage
  /// throws — [uploadToFirstFreeSlot] is what decides that a denial means
  /// "slot taken" rather than "upload failed".
  Future<String> _putAt({
    required String path,
    required Uint8List bytes,
    required String contentType,
    required Map<String, String>? metadata,
    required void Function(double fraction)? onProgress,
  }) async {
    final ref = _storage.ref(path);
    final task = ref.putData(
      bytes,
      SettableMetadata(contentType: contentType, customMetadata: metadata),
    );

    final progressSub = onProgress == null
        ? null
        : task.snapshotEvents.listen(
            (snapshot) {
              final total = snapshot.totalBytes;
              if (total <= 0) return;
              onProgress((snapshot.bytesTransferred / total).clamp(0.0, 1.0));
            },
            // Failures arrive on the task future below; the progress stream is
            // decoration and must never become an unhandled error.
            onError: (Object _) {},
          );

    try {
      await task;
    } finally {
      await progressSub?.cancel();
    }
    return ref.getDownloadURL();
  }

  /// Walks the day's slots in order and returns the first one that accepts the
  /// write.
  ///
  /// This is the whole daily cap. `submissions/{uid}/{yyyyMMdd}/{slot}` is
  /// create-only in the bucket rules for slots 0..9, so an already-used slot
  /// comes back as a denial rather than an overwrite — which means no
  /// read-before-write, no counter document to keep in step, and no way for a
  /// client bug to exceed the cap. When all ten are denied the player is out
  /// of clips for the day.
  ///
  /// [attempt] writes the object at the given path and returns its download
  /// URL; it is a parameter so this logic can be tested without Firebase.
  @visibleForTesting
  static Future<VideoUploadResult> uploadToFirstFreeSlot({
    required String userId,
    required DateTime when,
    required int byteCount,
    required Future<String> Function(String path) attempt,
  }) async {
    for (var slot = 0; slot < VideoPolicy.maxUploadsPerDay; slot++) {
      final path = VideoPolicy.storagePath(
        userId: userId,
        when: when,
        slot: slot,
      );
      try {
        final url = await attempt(path);
        return VideoUploadResult(
          downloadUrl: url,
          storagePath: path,
          bytes: byteCount,
        );
      } on FirebaseException catch (e) {
        if (deniedCodes.contains(e.code)) {
          debugPrint('FirebaseVideoUploader: slot $slot taken, trying next');
          continue;
        }
        rethrow;
      }
    }

    throw const DailyVideoLimitReached();
  }
}

/// Test / mock-mode double.
///
/// Emits a few progress ticks so an upload UI has something to animate, then
/// either returns [result] or throws [error].
class FakeVideoUploader implements VideoUploader {
  /// What a successful upload returns. Ignored when [error] is set.
  final VideoUploadResult result;

  /// When set, [upload] throws this instead of succeeding.
  final Object? error;

  /// Progress fractions handed to `onProgress` before finishing.
  final List<double> progressTicks;

  /// Every call, oldest first.
  final List<({String userId, int bytes, String contentType, DateTime when, Map<String, String>? metadata})>
      calls = [];

  FakeVideoUploader({
    VideoUploadResult? result,
    this.error,
    this.progressTicks = const [0.25, 0.5, 0.75],
  }) : result = result ??
            const VideoUploadResult(
              downloadUrl: 'https://example.test/clip.mp4',
              storagePath: 'submissions/user-1/20260912/0',
              bytes: 1024,
            );

  @override
  Future<VideoUploadResult> upload({
    required String userId,
    required Uint8List bytes,
    required String contentType,
    required DateTime when,
    Map<String, String>? metadata,
    void Function(double fraction)? onProgress,
  }) async {
    calls.add((
      userId: userId,
      bytes: bytes.length,
      contentType: contentType,
      when: when,
      metadata: metadata,
    ));
    for (final tick in progressTicks) {
      onProgress?.call(tick);
    }
    final failure = error;
    if (failure != null) throw failure;
    onProgress?.call(1);
    return result;
  }
}
