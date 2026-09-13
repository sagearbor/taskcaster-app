import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/services/video/video_policy.dart';
import '../../../../core/theme/app_theme.dart';
import 'countdown_burn.dart';

/// Playback for an in-app clip, everywhere one is shown.
///
/// What this widget IS responsible for:
///  * **Auto-trim on playback.** The post does not know the task timer, so the
///    end is `VideoPolicy.trimmedEndSeconds(duration, maxClipSeconds)` —
///    playback loops back to 0 the moment it reaches that. This is the whole
///    "trimming" story: there is no trim screen anywhere in the app.
///  * **Autoplay muted.** Browsers refuse to autoplay a clip with sound, so
///    every clip starts muted and a tap toggles it. That also keeps a scrolling
///    Arena quiet.
///  * **The task countdown**, via [CountdownBurn], except on house entries
///    which have it burned into the pixels already.
///  * **Never showing an error.** A source that will not load (an old post, a
///    transient network failure) renders a calm placeholder.
///
/// [ArenaVideoState.currentPositionSeconds] is exposed so a caller can turn a
/// viewer tap into `VideoPolicy.tapBucket(position, cap)`.
class ArenaVideo extends StatefulWidget {
  /// The clip's https download URL.
  final String? url;

  /// The clip's duration, when the post knows it. Null plays to the cap.
  final double? durationSeconds;

  /// Task clock metadata for the countdown overlay.
  final int? timerSeconds;
  final int? clockOffsetSeconds;
  final bool isLate;

  /// House clips (and server-rendered montages) already have the countdown
  /// burned in — do not draw a second one.
  final bool burnedIn;

  /// Start playing as soon as the clip is ready. Muted regardless.
  final bool autoPlay;

  /// Loop back to the start at the cap. Watch together turns this off so it
  /// can advance to the next entry instead.
  final bool loop;

  /// Fired once playback first reaches the cap/end, and also when the source
  /// fails to load — Watch together uses it to move on either way.
  final VoidCallback? onEnded;

  const ArenaVideo({
    super.key,
    required this.url,
    this.durationSeconds,
    this.timerSeconds,
    this.clockOffsetSeconds,
    this.isLate = false,
    this.burnedIn = false,
    this.autoPlay = true,
    this.loop = true,
    this.onEnded,
  });

  @override
  State<ArenaVideo> createState() => ArenaVideoState();
}

class ArenaVideoState extends State<ArenaVideo> {
  VideoPlayerController? _controller;
  bool _failed = false;
  bool _ready = false;
  bool _muted = true;
  bool _endedReported = false;
  double _position = 0;

  /// Where playback is, in seconds. 0 before the clip is ready. Callers turn
  /// this into a tap bucket with `VideoPolicy.tapBucket(position, cap)`.
  double get currentPositionSeconds => _position;

  /// The playback end: the clip's own duration, auto-trimmed to the absolute
  /// clip cap. Falls back to the cap when the duration is unknown.
  double get capSeconds {
    var duration = widget.durationSeconds;
    if (duration == null) {
      final known = _controller?.value.duration;
      if (known != null && known > Duration.zero) {
        duration = known.inMilliseconds / 1000;
      }
    }
    return VideoPolicy.trimmedEndSeconds(
          duration,
          VideoPolicy.maxClipSeconds,
        ) ??
        VideoPolicy.maxClipSeconds.toDouble();
  }

  /// True when the clip could not be loaded — the calm placeholder is showing.
  bool get hasFailed => _failed;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void didUpdateWidget(covariant ArenaVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _disposeController();
      setState(() {
        _failed = false;
        _ready = false;
        _endedReported = false;
        _position = 0;
      });
      _open();
    }
  }

  Future<void> _open() async {
    final url = widget.url;
    if (url == null || url.isEmpty) {
      _fail();
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) {
      _fail();
      return;
    }

    final controller = VideoPlayerController.networkUrl(uri);
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
      if (widget.autoPlay) await controller.play();
      setState(() => _ready = true);
    } catch (e) {
      // Deliberately never an error UI: a clip that will not load is a calm
      // placeholder, not a red box in the middle of the Arena.
      debugPrint('ArenaVideo could not load $url: $e');
      _fail();
    }
  }

  void _fail() {
    if (!mounted) {
      _failed = true;
      return;
    }
    setState(() => _failed = true);
    _reportEnded();
  }

  void _reportEnded() {
    if (_endedReported) return;
    _endedReported = true;
    widget.onEnded?.call();
  }

  void _onTick() {
    final controller = _controller;
    if (controller == null || !mounted) return;
    final value = controller.value;
    if (value.hasError) {
      _fail();
      return;
    }
    if (!value.isInitialized) return;

    final position = value.position.inMilliseconds / 1000;
    if ((position - _position).abs() >= 0.05) {
      setState(() => _position = position);
    }

    final end = capSeconds;
    final ranOut = value.duration > Duration.zero &&
        value.position >= value.duration;
    if (position < end && !ranOut) return;

    if (widget.loop) {
      // THE auto-trim: playback never runs past the cap, it starts again.
      controller.seekTo(Duration.zero);
      if (widget.autoPlay) controller.play();
      setState(() => _position = 0);
      _endedReported = false;
    } else {
      controller.pause();
      _reportEnded();
    }
  }

  Future<void> _toggleSound() async {
    final controller = _controller;
    if (controller == null || !_ready) return;
    final next = !_muted;
    setState(() => _muted = next);
    await controller.setVolume(next ? 0 : 1);
  }

  void _disposeController() {
    final controller = _controller;
    _controller = null;
    controller?.removeListener(_onTick);
    controller?.dispose();
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return const ClipUnavailable();

    final controller = _controller;
    if (!_ready || controller == null) {
      return Container(
        decoration: const BoxDecoration(gradient: AppTheme.heroGradient),
        alignment: Alignment.center,
        child: const SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
      );
    }

    final showCountdown = !widget.burnedIn &&
        CountdownBurn.label(
              timerSeconds: widget.timerSeconds,
              clockOffsetSeconds: widget.clockOffsetSeconds,
              positionSeconds: _position,
              isLate: widget.isLate,
            ) !=
            null;

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
          left: 10,
          child: _SoundToggle(muted: _muted, onPressed: _toggleSound),
        ),
        Positioned(
          bottom: 10,
          right: 10,
          // House and montage clips carry the clock in their pixels; a clip
          // with no task timer has no clock to draw. Either way the viewer
          // still gets a position readout.
          child: showCountdown
              ? CountdownBurn(
                  timerSeconds: widget.timerSeconds,
                  clockOffsetSeconds: widget.clockOffsetSeconds,
                  positionSeconds: _position,
                  isLate: widget.isLate,
                )
              : _PositionPill(position: _position, end: capSeconds),
        ),
      ],
    );
  }
}

/// The calm stand-in for a clip that will not play. Never an error message:
/// the Arena is a place to laugh, not to debug.
class ClipUnavailable extends StatelessWidget {
  const ClipUnavailable({super.key});

  static const String message = "This clip isn't available";

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppTheme.heroGradient),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.movie_outlined, color: Colors.white70, size: 40),
          SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Fredoka',
              fontWeight: FontWeight.w600,
              fontSize: 18,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _SoundToggle extends StatelessWidget {
  final bool muted;
  final VoidCallback onPressed;

  const _SoundToggle({required this.muted, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: muted ? 'Sound off' : 'Sound on',
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.55),
            shape: BoxShape.circle,
          ),
          child: Icon(
            muted ? Icons.volume_off : Icons.volume_up,
            size: 18,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

/// Position/duration readout for clips that carry their own burned-in clock.
class _PositionPill extends StatelessWidget {
  final double position;
  final double end;

  const _PositionPill({required this.position, required this.end});

  static String _fmt(double seconds) {
    final whole = seconds.isNaN || seconds < 0 ? 0 : seconds.floor();
    return '${whole ~/ 60}:${(whole % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '${_fmt(position)} / ${_fmt(end)}',
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          height: 1.2,
        ),
      ),
    );
  }
}
