import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/repositories/clue_hunt_repository.dart';
import '../../domain/entities/clue_hunt_session.dart';

/// The hider's screen. During [CluePhase.hiding] it explains the job and offers
/// one big "Ready — seekers go!" button. During [CluePhase.seeking] it shows the
/// giant warmer/colder slider the hider drags as the human "sensor", plus the
/// pending-claim confirm panel when a seeker taps "Found it!".
class ClueHiderView extends StatefulWidget {
  final ClueHuntRepository repository;
  final ClueHuntSession session;

  const ClueHiderView({
    super.key,
    required this.repository,
    required this.session,
  });

  @override
  State<ClueHiderView> createState() => _ClueHiderViewState();
}

class _ClueHiderViewState extends State<ClueHiderView> {
  double _heat = 0.0;

  @override
  void initState() {
    super.initState();
    _heat = widget.repository.heat;
  }

  @override
  void didUpdateWidget(ClueHiderView old) {
    super.didUpdateWidget(old);
    // On a fresh seek (round rolled over) the repository resets heat to 0.
    if (old.session.roundNumber != widget.session.roundNumber) {
      _heat = 0.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.session.phase) {
      case CluePhase.hiding:
        return _buildHiding(context);
      case CluePhase.seeking:
        return _buildSeeking(context);
      default:
        return const SizedBox.shrink();
    }
  }

  // ---- Hiding ---------------------------------------------------------------

  Widget _buildHiding(BuildContext context) {
    final theme = Theme.of(context);
    final session = widget.session;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Round ${session.roundNumber} of ${session.totalRounds}',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: AppTheme.inkSoft)),
            const SizedBox(height: 8),
            const Center(child: Text('🫥', style: TextStyle(fontSize: 64))),
            const SizedBox(height: 12),
            Text("You're the hider!",
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(
              'Hide a real object — a spoon, a toy, anything. When it\'s hidden, '
              'tap below and the hunt begins. Then watch the seekers and drag the '
              'meter warmer as they get closer, colder as they wander off.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const Spacer(),
            _RosterStrip(session: session),
            const Spacer(),
            SizedBox(
              height: 72,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  textStyle: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w900),
                ),
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  widget.repository.beginSeeking();
                },
                icon: const Icon(Icons.visibility),
                label: const Text("It's hidden — seekers go!"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- Seeking --------------------------------------------------------------

  Widget _buildSeeking(BuildContext context) {
    final theme = Theme.of(context);
    final session = widget.session;
    final pending = session.pendingClaimant;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('You are the sensor',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text('Drag WARMER as seekers close in, COLDER as they drift.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Expanded(child: _WarmColderSlider(
              value: _heat,
              onChanged: (v) {
                setState(() => _heat = v);
                widget.repository.setHeat(v);
              },
            )),
            const SizedBox(height: 12),
            if (pending != null)
              _ConfirmPanel(
                name: pending.name,
                onConfirm: () {
                  HapticFeedback.heavyImpact();
                  widget.repository.confirmFind();
                },
                onReject: () {
                  HapticFeedback.lightImpact();
                  widget.repository.rejectFind();
                },
              )
            else
              Container(
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.violetSoft,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  '${session.seekers.length} '
                  '${session.seekers.length == 1 ? 'seeker is' : 'seekers are'} '
                  'hunting…',
                  style: theme.textTheme.titleMedium,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A tall vertical warmer/colder control. Implemented as a rotated [Slider] with
/// a coloured fill so the hider's thumb position reads like a thermometer.
class _WarmColderSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;
  const _WarmColderSlider({required this.value, required this.onChanged});

  Color get _color {
    if (value < 0.5) {
      return Color.lerp(
          const Color(0xFF2563EB), AppTheme.gold, (value / 0.5).clamp(0, 1))!;
    }
    return Color.lerp(
        AppTheme.gold, AppTheme.coral, ((value - 0.5) / 0.5).clamp(0, 1))!;
  }

  @override
  Widget build(BuildContext context) {
    final color = _color;
    return Row(
      children: [
        // Labels column.
        const Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('🔥 WARMER',
                style: TextStyle(
                    fontWeight: FontWeight.w900, color: AppTheme.coral)),
            Text('❄️ COLDER',
                style: TextStyle(
                    fontWeight: FontWeight.w900, color: Color(0xFF2563EB))),
          ],
        ),
        const SizedBox(width: 8),
        // The fill track + slider.
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  Center(
                    child: Container(
                      width: 64,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(32),
                        border:
                            Border.all(color: color.withOpacity(0.4), width: 3),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: value.clamp(0.0, 1.0),
                          child: Container(color: color.withOpacity(0.85)),
                        ),
                      ),
                    ),
                  ),
                  // A vertical slider driven by rotating a horizontal one.
                  Positioned.fill(
                    child: RotatedBox(
                      quarterTurns: 3,
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 0,
                          activeTrackColor: Colors.transparent,
                          inactiveTrackColor: Colors.transparent,
                          thumbColor: color,
                          overlayColor: color.withOpacity(0.2),
                          thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 22),
                        ),
                        child: Slider(
                          value: value,
                          onChanged: onChanged,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// The confirm/reject panel that pops up when a seeker claims the find.
class _ConfirmPanel extends StatelessWidget {
  final String name;
  final VoidCallback onConfirm;
  final VoidCallback onReject;
  const _ConfirmPanel(
      {required this.name, required this.onConfirm, required this.onReject});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.gold.withOpacity(0.15),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.gold, width: 2),
      ),
      child: Column(
        children: [
          Text('🙌 $name says they grabbed it!',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onReject,
                  child: const Text('Not yet'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.gold),
                  onPressed: onConfirm,
                  child: const Text('Yes — they found it!'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A compact horizontal strip of avatars for the roster in the hiding screen.
class _RosterStrip extends StatelessWidget {
  final ClueHuntSession session;
  const _RosterStrip({required this.session});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      runSpacing: 8,
      children: [
        for (final p in session.players)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                backgroundColor: p.id == session.hiderId
                    ? AppTheme.gold
                    : AppTheme.violetSoft,
                child: Text(p.name.isNotEmpty ? p.name[0].toUpperCase() : '?'),
              ),
              const SizedBox(height: 2),
              SizedBox(
                width: 56,
                child: Text(p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11)),
              ),
            ],
          ),
      ],
    );
  }
}
