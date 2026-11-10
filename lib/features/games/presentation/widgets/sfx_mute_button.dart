import 'package:flutter/material.dart';

import '../../../../core/services/sfx/game_sfx.dart';

/// A small speaker in the app bar that mutes every game sound. The choice is
/// remembered (`sfx_muted` in SharedPreferences) and honoured app-wide by
/// [GameSfx.muted].
class SfxMuteButton extends StatefulWidget {
  const SfxMuteButton({super.key});

  @override
  State<SfxMuteButton> createState() => _SfxMuteButtonState();
}

class _SfxMuteButtonState extends State<SfxMuteButton> {
  @override
  void initState() {
    super.initState();
    GameSfx.loadMutePreference();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: GameSfx.muted,
      builder: (context, muted, _) => IconButton(
        key: const Key('sfx-mute-toggle'),
        tooltip: muted ? 'Sound off. Tap for sound' : 'Sound on. Tap to mute',
        iconSize: 22,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        icon: Icon(
          muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
        ),
        onPressed: () => GameSfx.setMuted(!muted),
      ),
    );
  }
}
