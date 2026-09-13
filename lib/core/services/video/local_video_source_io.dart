import 'dart:io';

import 'package:video_player/video_player.dart';

/// iOS / Android / desktop: the picker's `path` is a real file.
VideoPlayerController localVideoController(String source) =>
    VideoPlayerController.file(File(source));
