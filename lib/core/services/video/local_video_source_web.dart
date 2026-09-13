import 'package:video_player/video_player.dart';

/// Web: the picker's `path` is a `blob:` URL, which `video_player_web` sets
/// straight onto the `<video>` element's `src`.
VideoPlayerController localVideoController(String source) =>
    VideoPlayerController.networkUrl(Uri.parse(source));
