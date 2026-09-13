import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/services/video/local_video_source.dart';
import '../../../../core/services/video/video_capture.dart';
import '../../../../core/services/video/video_policy.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../arena/presentation/widgets/countdown_burn.dart';

/// The clip the player just filmed, before they tap Post it.
///
/// Muted, looping, and cut at `VideoPolicy.clipCapSeconds` — which is the
/// ONLY trimming the app does and the only preview control there is. There is
/// deliberately no scrubber, no in/out handles and no caption field: the
/// player's two choices are Retake and Post it.
class ClipPreview extends StatefulWidget {
  final PickedVideo clip;

  /// The task's own timer, for the countdown overlay.
  final int? timerSeconds;

  /// Seconds already spent on the task clock when the recorder opened.
  final int? clockOffsetSeconds;

  const ClipPreview({
    super.key,
    required this.clip,
    this.timerSeconds,
    this.clockOffsetSeconds,
  });

  @override
  State<ClipPreview> createState() => _ClipPreviewState();
}

class _ClipPreviewState extends State<ClipPreview> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _failed = false;
  double _position = 0;

  double get _capSeconds =>
      VideoPolicy.clipCapSeconds(widget.timerSeconds).toDouble();

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final source = widget.clip.sourcePath;
    if (source == null || source.isEmpty) {
      setState(() => _failed = true);
      return;
    }
    final controller = localVideoController(source);
    _controller = controller;
    controller.addListener(_onTick);
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await controller.setVolume(0);
      await controller.setLooping(false);
      await controller.play();
      setState(() => _ready = true);
    } catch (e) {
      debugPrint('ClipPreview could not open the clip: $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  void _onTick() {
    final controller = _controller;
    if (controller == null || !mounted) return;
    final value = controller.value;
    if (value.hasError) {
      setState(() => _failed = true);
      return;
    }
    if (!value.isInitialized) return;

    final position = value.position.inMilliseconds / 1000;
    if ((position - _position).abs() >= 0.05) {
      setState(() => _position = position);
    }

    final ranOut =
        value.duration > Duration.zero && value.position >= value.duration;
    if (position >= _capSeconds || ranOut) {
      // Auto-trim: loop the first `cap` seconds, which is exactly what the
      // Arena will play back.
      controller.seekTo(Duration.zero);
      controller.play();
      setState(() => _position = 0);
    }
  }

  @override
  void dispose() {
    final controller = _controller;
    _controller = null;
    controller?.removeListener(_onTick);
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_failed || !_ready || controller == null) {
      return Container(
        decoration: const BoxDecoration(gradient: AppTheme.heroGradient),
        alignment: Alignment.center,
        child: _failed
            ? const Text(
                'Clip ready to post',
                style: TextStyle(
                  fontFamily: 'Fredoka',
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                  color: Colors.white,
                ),
              )
            : const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: Colors.black,
          child: FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: controller.value.size.width,
              height: controller.value.size.height,
              child: VideoPlayer(controller),
            ),
          ),
        ),
        Positioned(
          bottom: 10,
          right: 10,
          child: CountdownBurn(
            timerSeconds: widget.timerSeconds,
            clockOffsetSeconds: widget.clockOffsetSeconds,
            positionSeconds: _position,
          ),
        ),
      ],
    );
  }
}
