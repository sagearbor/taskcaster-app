import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/services/sfx/game_sfx.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/repositories/clue_hunt_repository.dart';
import '../../domain/clue_heat.dart';
import '../../domain/entities/clue_hunt_session.dart';

/// The seeker's screen while a hunt is live: a big geiger heat meter driven by
/// the heat the hider broadcasts (ticking + haptics scale with heat, reusing the
/// Treasure Hunt feel) and one huge "Found it!" button. When a claim is pending
/// the button becomes a status — either "waiting for the hider" (mine) or
/// "someone's checking a find" (another seeker's).
class ClueSeekerView extends StatefulWidget {
  final ClueHuntRepository repository;
  final ClueHuntSession session;
  final String selfId;
  final GameSfx sfx;

  const ClueSeekerView({
    super.key,
    required this.repository,
    required this.session,
    required this.selfId,
    required this.sfx,
  });

  @override
  State<ClueSeekerView> createState() => _ClueSeekerViewState();
}

class _ClueSeekerViewState extends State<ClueSeekerView> {
  StreamSubscription<double>? _heatSub;
  late final GeigerTicker _ticker;
  double _heat = 0.0;

  @override
  void initState() {
    super.initState();
    _heat = widget.repository.heat;
    _ticker = GeigerTicker(onTick: _onTick)..start(_heat);
    _heatSub = widget.repository.watchHeat().listen(_onHeat);
  }

  @override
  void dispose() {
    _heatSub?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  void _onHeat(double heat) {
    if (!mounted) return;
    setState(() => _heat = heat);
    // Re-arm rather than reschedule from scratch: a stream of updates at steady
    // heat keeps ticking instead of forever pushing the next tick out of reach.
    _ticker.setHeat(heat);
  }

  void _onTick() {
    if (!mounted) return;
    widget.sfx.tick();
    switch (ClueHeat.bandForHeat(_heat)) {
      case HeatBand.hot:
        HapticFeedback.heavyImpact();
        break;
      case HeatBand.warm:
        HapticFeedback.mediumImpact();
        break;
      case HeatBand.cold:
        HapticFeedback.lightImpact();
        break;
      case HeatBand.silent:
        break;
    }
  }

  String get _heatLabel {
    switch (ClueHeat.bandForHeat(_heat)) {
      case HeatBand.hot:
        return _heat > 0.85 ? 'BOILING! 🔥' : 'HOT!';
      case HeatBand.warm:
        return 'Warm';
      case HeatBand.cold:
        return 'Cold';
      case HeatBand.silent:
        return 'Freezing';
    }
  }

  Color get _heatColor {
    // Blue (cold) → gold → coral (hot).
    if (_heat < 0.5) {
      return Color.lerp(
          const Color(0xFF2563EB), AppTheme.gold, (_heat / 0.5).clamp(0, 1))!;
    }
    return Color.lerp(
        AppTheme.gold, AppTheme.coral, ((_heat - 0.5) / 0.5).clamp(0, 1))!;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = widget.session;
    final pendingBy = session.pendingClaimBy;
    final iAmClaiming = pendingBy == widget.selfId;
    final someoneElseClaiming = pendingBy != null && !iAmClaiming;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Round ${session.roundNumber} of ${session.totalRounds}',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: AppTheme.inkSoft)),
            const SizedBox(height: 2),
            Text(
              '${session.hider?.name ?? 'The hider'} can see you — get warmer!',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Expanded(child: _HeatMeter(heat: _heat, color: _heatColor)),
            const SizedBox(height: 8),
            Text(
              _heatLabel,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: _heatColor,
              ),
            ),
            const SizedBox(height: 16),
            if (iAmClaiming)
              _ClaimStatus(
                icon: Icons.hourglass_top,
                color: AppTheme.gold,
                text:
                    'You claimed the find!\nWaiting for ${session.hider?.name ?? 'the hider'} to confirm…',
              )
            else if (someoneElseClaiming)
              _ClaimStatus(
                icon: Icons.pan_tool_alt,
                color: AppTheme.inkSoft,
                text:
                    '${session.pendingClaimant?.name ?? 'Someone'} is checking a find…',
              )
            else
              SizedBox(
                height: 84,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.coral,
                    textStyle: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w900),
                  ),
                  onPressed: _onFound,
                  icon: const Text('🙌', style: TextStyle(fontSize: 28)),
                  label: const Text('Found it!'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _onFound() {
    HapticFeedback.heavyImpact();
    widget.repository.claimFound();
  }
}

/// The vertical thermometer. Fills from the bottom in proportion to heat, with a
/// soft glow so a hot meter reads at a glance across a garden.
class _HeatMeter extends StatelessWidget {
  final double heat;
  final Color color;
  const _HeatMeter({required this.heat, required this.color});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Center(
          child: AspectRatio(
            aspectRatio: 0.5,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.06),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: color.withOpacity(0.4), width: 3),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  AnimatedFractionallySizedBox(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    widthFactor: 1,
                    heightFactor: heat.clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [color, color.withOpacity(0.7)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: color.withOpacity(0.6),
                            blurRadius: 24,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Icon(Icons.local_fire_department,
                          color: Colors.white70, size: 28),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ClaimStatus extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _ClaimStatus(
      {required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 84,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Flexible(
            child: Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.bold, height: 1.2)),
          ),
        ],
      ),
    );
  }
}
