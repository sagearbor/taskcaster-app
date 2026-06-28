import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/service_locator.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import '../cubit/nearby_auto_cast_cubit.dart';
import '../screens/offline_telephone_screens.dart';

/// Home-screen banner that makes offline nearby play **auto-cast**: while the
/// user just sits on the home screen, it passively scans for nearby TaskCaster
/// hosts and, the instant one appears, slides in a one-tap "Join" card — the
/// player never has to hunt for a "Find nearby game" button.
///
/// Owns the [NearbyAutoCastCubit] lifecycle:
///  * scans while mounted + app-foregrounded;
///  * stops on background (battery) and on navigating into the join flow (so the
///    radio is free for that screen's own discovery), restarting on return.
///
/// On unsupported platforms / when permissions aren't yet granted the cubit
/// stays quietly idle and this renders nothing — no nag, no crash.
class NearbyAutoCastBanner extends StatefulWidget {
  const NearbyAutoCastBanner({super.key});

  @override
  State<NearbyAutoCastBanner> createState() => _NearbyAutoCastBannerState();
}

class _NearbyAutoCastBannerState extends State<NearbyAutoCastBanner>
    with WidgetsBindingObserver {
  late final NearbyAutoCastCubit _cubit;

  /// Name we'll join under, resolved from the signed-in user (fallback below).
  String _joinName = 'Player';

  @override
  void initState() {
    super.initState();
    _cubit = NearbyAutoCastCubit();
    WidgetsBinding.instance.addObserver(this);
    _resolveJoinName();
    _cubit.start();
  }

  Future<void> _resolveJoinName() async {
    try {
      final user = await sl<AuthRepository>().getCurrentUser();
      final name = user?.displayName.trim() ?? '';
      if (mounted && name.isNotEmpty) setState(() => _joinName = name);
    } catch (_) {/* fall back to 'Player' */}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _cubit.start();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _cubit.stop();
        break;
    }
  }

  Future<void> _join(AutoCastGameAvailable available) async {
    // Free the radio for the join screen's own discovery, then hand off the
    // host's advertised name so it auto-connects with no extra tap.
    await _cubit.stop();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OfflineJoinScreen(
          displayName: _joinName,
          autoJoinEndpointName: available.endpointName,
        ),
      ),
    );
    // Back on home: resume passively scanning for the next game.
    if (mounted) _cubit.start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _cubit,
      child: BlocBuilder<NearbyAutoCastCubit, NearbyAutoCastState>(
        builder: (context, state) {
          if (state is! AutoCastGameAvailable) {
            return const SizedBox.shrink();
          }
          return _Banner(
            label: state.label.bannerText,
            onJoin: () => _join(state),
          );
        },
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final String label;
  final VoidCallback onJoin;
  const _Banner({required this.label, required this.onJoin});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Card(
        elevation: 3,
        child: InkWell(
          onTap: onJoin,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(
                colors: [Color(0xFF059669), Color(0xFF10B981)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.wifi_tethering,
                      size: 26, color: Colors.white),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '🎮 Nearby game found',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$label · tap to join',
                        style: const TextStyle(
                            fontSize: 13, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                const _JoinPill(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _JoinPill extends StatelessWidget {
  const _JoinPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Text(
        'Join',
        style: TextStyle(
          color: Color(0xFF059669),
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
    );
  }
}
