import 'package:video_player/video_player.dart';

import 'local_video_source_io.dart'
    if (dart.library.html) 'local_video_source_web.dart' as impl;

/// A [VideoPlayerController] for a clip the player just recorded, before it is
/// uploaded — i.e. for the Retake / Post it preview only.
///
/// The picker hands back a filesystem path on iOS/Android and a `blob:` URL on
/// web, and `video_player` wants a different constructor for each; the
/// conditional import picks the right one so neither `dart:io` nor a web-only
/// assumption leaks into the shared code.
VideoPlayerController localVideoController(String source) =>
    impl.localVideoController(source);
