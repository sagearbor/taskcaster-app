import 'dart:typed_data';

import 'package:equatable/equatable.dart';

import '../../../../core/services/video/video_capture.dart';

abstract class TaskExecutionEvent extends Equatable {
  const TaskExecutionEvent();

  @override
  List<Object?> get props => [];
}

class LoadTask extends TaskExecutionEvent {
  final String gameId;
  final int taskIndex;
  final String userId;

  const LoadTask({
    required this.gameId,
    required this.taskIndex,
    required this.userId,
  });

  @override
  List<Object> get props => [gameId, taskIndex, userId];
}

class StartTask extends TaskExecutionEvent {
  final String gameId;
  final int taskIndex;
  final String userId;

  const StartTask({
    required this.gameId,
    required this.taskIndex,
    required this.userId,
  });

  @override
  List<Object> get props => [gameId, taskIndex, userId];
}

/// Hand in an attempt.
///
/// Exactly one of [video], [photoBytes], [text] and [videoUrl] is normally
/// set; the medium is inferred in that order (clip, photo, text, then link),
/// and the stamp and caption are computed by `AutoEdit` — the UI never
/// supplies them.
class SubmitTask extends TaskExecutionEvent {
  final String gameId;
  final int taskIndex;
  final String userId;

  /// The legacy "paste a link" path. Still supported, never required.
  final String? videoUrl;

  /// A JPEG, already downscaled by `PhotoCapture` (<= 720 px, quality ~70).
  final Uint8List? photoBytes;

  /// A text entry.
  final String? text;

  /// An in-app clip, already recorded and auto-trimmed by the recorder's
  /// `maxDuration`. Uploaded to Firebase Storage before the post is written.
  final PickedVideo? video;

  /// Seconds already burned on the TASK clock when the recorder opened —
  /// captured by the screen at the moment of the "Film it" tap. Stored on the
  /// post so playback (and a later server-side splice) can draw the task
  /// countdown over the clip.
  final int? clockOffsetSeconds;

  /// Post this attempt to the Arena. Also requires the game's
  /// `settings.shareToArena`.
  final bool shareToArena;

  /// Name shown on the Arena post.
  final String displayName;

  const SubmitTask({
    required this.gameId,
    required this.taskIndex,
    required this.userId,
    this.videoUrl,
    this.photoBytes,
    this.text,
    this.video,
    this.clockOffsetSeconds,
    this.shareToArena = true,
    this.displayName = '',
  });

  @override
  List<Object?> get props => [
        gameId,
        taskIndex,
        userId,
        videoUrl,
        photoBytes,
        text,
        video,
        clockOffsetSeconds,
        shareToArena,
        displayName,
      ];
}

class SkipTask extends TaskExecutionEvent {
  final String gameId;
  final int taskIndex;
  final String userId;

  const SkipTask({
    required this.gameId,
    required this.taskIndex,
    required this.userId,
  });

  @override
  List<Object> get props => [gameId, taskIndex, userId];
}