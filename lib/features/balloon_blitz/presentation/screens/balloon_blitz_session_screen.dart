import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/ar_fx.dart';
import '../../data/repositories/balloon_blitz_repository.dart';
import '../../domain/entities/blitz_session.dart';
import '../bloc/balloon_blitz_bloc.dart';
import '../widgets/blitz_leaderboard.dart';
import '../widgets/blitz_live_rank_strip.dart';
import '../widgets/blitz_play_view.dart';
import '../widgets/blitz_podium.dart';

/// The shared Balloon Blitz game screen, used by both the host and every peer.
/// It renders one of three phases from the authoritative session — lobby,
/// playing (live AR + leaderboard overlay) and results — and routes player
/// actions through the [BalloonBlitzBloc]. The offline host/join screens own the
/// [repository] lifecycle; this screen only subscribes.
class BalloonBlitzSessionScreen extends StatelessWidget {
  final BalloonBlitzRepository repository;
  final String selfId;

  const BalloonBlitzSessionScreen({
    super.key,
    required this.repository,
    required this.selfId,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          BalloonBlitzBloc(repository: repository)..add(const BlitzSubscribed()),
      child: _BlitzView(isHost: repository.isHost, selfId: selfId),
    );
  }
}

class _BlitzView extends StatelessWidget {
  final bool isHost;
  final String selfId;

  const _BlitzView({required this.isHost, required this.selfId});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BalloonBlitzBloc, BalloonBlitzState>(
      // Only rebuild the whole screen when the PHASE changes; score updates
      // within a phase are handled by the inner leaderboard builder so the live
      // AR view (and its controller) is never torn down mid-round.
      buildWhen: (prev, curr) =>
          prev.session?.phase != curr.session?.phase ||
          prev.status != curr.status,
      builder: (context, state) {
        final session = state.session;
        if (session == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        switch (session.phase) {
          case BlitzPhase.lobby:
            return _LobbyScaffold(isHost: isHost, selfId: selfId);
          case BlitzPhase.playing:
            return _PlayingScaffold(isHost: isHost, selfId: selfId);
          case BlitzPhase.results:
            return _ResultsScaffold(isHost: isHost, selfId: selfId);
        }
      },
    );
  }
}

// ---- Lobby ----------------------------------------------------------------

class _LobbyScaffold extends StatelessWidget {
  final bool isHost;
  final String selfId;

  const _LobbyScaffold({required this.isHost, required this.selfId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Balloon Blitz — Lobby')),
      body: BlocBuilder<BalloonBlitzBloc, BalloonBlitzState>(
        builder: (context, state) {
          final session = state.session!;
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('🎈 Balloon Blitz',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(
                  isHost
                      ? 'Wait for the family to join, then start the race. '
                          'Everyone pops their own balloons for '
                          '${session.durationSeconds}s — scores race live.'
                      : 'You\'re in! Pop your own balloons when the host starts '
                          'the race. Highest score wins.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                Text('Players (${session.players.length})',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    children: [
                      for (final p in session.players)
                        Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: AppTheme.violetSoft,
                              child: Text(
                                p.name.isNotEmpty
                                    ? p.name[0].toUpperCase()
                                    : '?',
                              ),
                            ),
                            title: Text(p.name),
                            trailing: p.isHost
                                ? const Icon(Icons.wifi_tethering,
                                    color: AppTheme.gold)
                                : null,
                            subtitle: p.id == selfId ? const Text('You') : null,
                          ),
                        ),
                    ],
                  ),
                ),
                if (isHost)
                  FilledButton.icon(
                    onPressed: () => context
                        .read<BalloonBlitzBloc>()
                        .add(const BlitzRoundStarted()),
                    icon: const Icon(Icons.flag),
                    label: Text(session.players.length < 2
                        ? 'Start race (waiting for players…)'
                        : 'Start race'),
                  )
                else
                  Center(
                    child: Text('Waiting for the host to start…',
                        style: theme.textTheme.bodyMedium),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---- Playing --------------------------------------------------------------

class _PlayingScaffold extends StatelessWidget {
  final bool isHost;
  final String selfId;

  const _PlayingScaffold({required this.isHost, required this.selfId});

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<BalloonBlitzBloc>();
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // The live local AR game — created ONCE for the round (stable key).
          BlitzPlayView(
            key: const ValueKey('blitz-play'),
            // Shared race: the repository IS the ArRaceSync — one balloon set
            // for everyone; the host's pop ledger IS the leaderboard, so no
            // separate score messages exist to get lost.
            race: bloc.repository,
            onFinished: () {
              // The host's local time-up also ends the authoritative round;
              // peers just wait for the host's results broadcast.
              if (isHost) bloc.add(const BlitzRoundEnded());
            },
          ),

          // Live, always-visible ranked strip: top 3 + you (if you're outside
          // the top 3). Thin, translucent, bottom edge — never blocks the AR
          // camera view above it. Updates on every score message.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: BlocBuilder<BalloonBlitzBloc, BalloonBlitzState>(
                    buildWhen: (p, c) => p.session != c.session,
                    builder: (context, state) => BlitzLiveRankStrip(
                      session: state.session!,
                      selfId: selfId,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Results --------------------------------------------------------------

class _ResultsScaffold extends StatefulWidget {
  final bool isHost;
  final String selfId;

  const _ResultsScaffold({required this.isHost, required this.selfId});

  @override
  State<_ResultsScaffold> createState() => _ResultsScaffoldState();
}

class _ResultsScaffoldState extends State<_ResultsScaffold>
    with SingleTickerProviderStateMixin {
  /// One-shot ceremony: trophy punches in, winner line reveals, standings
  /// slide up — all while the shared [ConfettiBurst] rains overhead.
  late final AnimationController _ceremony;

  @override
  void initState() {
    super.initState();
    _ceremony = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..forward();
  }

  @override
  void dispose() {
    _ceremony.dispose();
    super.dispose();
  }

  Animation<double> _slice(double start, double end,
      {Curve curve = Curves.easeOutCubic}) {
    return CurvedAnimation(
      parent: _ceremony,
      curve: Interval(start, end, curve: curve),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isHost = widget.isHost;
    final selfId = widget.selfId;
    final trophyIn = _slice(0.0, 0.4, curve: Curves.elasticOut);
    final winnerIn = _slice(0.1, 0.45);
    // Linear (uncurved) slice so the podium's own internal per-stand
    // staggering — which applies its own Intervals/curves on top — reads
    // cleanly instead of compounding two easing curves.
    final podiumIn = CurvedAnimation(
      parent: _ceremony,
      curve: const Interval(0.3, 0.9, curve: Curves.linear),
    );
    final standingsIn = _slice(0.7, 1.0);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Balloon Blitz — Results'),
        automaticallyImplyLeading: false,
      ),
      body: BlocBuilder<BalloonBlitzBloc, BalloonBlitzState>(
        builder: (context, state) {
          final session = state.session!;
          final winner =
              session.leaderboard.isNotEmpty ? session.leaderboard.first : null;
          return Stack(
            children: [
              Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Center(
                  child: ScaleTransition(
                    scale: trophyIn,
                    child: const Text('🏆', style: TextStyle(fontSize: 48)),
                  ),
                ),
                const SizedBox(height: 4),
                FadeTransition(
                  opacity: winnerIn,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.4),
                      end: Offset.zero,
                    ).animate(winnerIn),
                    child: Text(
                      winner == null
                          ? 'Time!'
                          : '${winner.name} wins with ${winner.liveScore}!',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                BlitzPodium(
                  ranked: session.leaderboard,
                  selfId: selfId,
                  reveal: podiumIn,
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: FadeTransition(
                    opacity: standingsIn,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.15),
                        end: Offset.zero,
                      ).animate(standingsIn),
                      child: SingleChildScrollView(
                        child:
                            BlitzLeaderboard(session: session, selfId: selfId),
                      ),
                    ),
                  ),
                ),
                if (isHost)
                  FilledButton.icon(
                    onPressed: () => context
                        .read<BalloonBlitzBloc>()
                        .add(const BlitzPlayAgainRequested()),
                    icon: const Icon(Icons.replay),
                    label: const Text('Play again'),
                  )
                else
                  Center(
                    child: Text('Waiting for the host to start another race…',
                        style: theme.textTheme.bodyMedium),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.exit_to_app),
                  label: const Text('Leave game'),
                ),
              ],
            ),
              ),

              // Celebration rain over the results (one-shot, self-completing).
              const Positioned.fill(child: ConfettiBurst()),
            ],
          );
        },
      ),
    );
  }
}
