import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/services/sfx/game_sfx.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/ar_fx.dart';
import '../../data/repositories/clue_hunt_repository.dart';
import '../../domain/entities/clue_hunt_session.dart';
import '../bloc/clue_hunt_bloc.dart';
import '../widgets/clue_hider_view.dart';
import '../widgets/clue_scoreboard.dart';
import '../widgets/clue_seeker_view.dart';

/// The shared Clue Hunt game screen, used by both the host and every seeker. It
/// renders one of the lifecycle phases from the authoritative session — lobby,
/// the live hunt (hider vs. seeker view chosen by whether YOU are this round's
/// hider), the round result and the winner ceremony — and routes actions through
/// the [ClueHuntBloc]. The offline host/join screens own the [repository]
/// lifecycle; this screen only subscribes.
class ClueHuntSessionScreen extends StatelessWidget {
  final ClueHuntRepository repository;
  final String selfId;

  const ClueHuntSessionScreen({
    super.key,
    required this.repository,
    required this.selfId,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          ClueHuntBloc(repository: repository)..add(const ClueSubscribed()),
      child: _ClueView(
        isHost: repository.isHost,
        selfId: selfId,
        repository: repository,
      ),
    );
  }
}

class _ClueView extends StatelessWidget {
  final bool isHost;
  final String selfId;
  final ClueHuntRepository repository;

  const _ClueView({
    required this.isHost,
    required this.selfId,
    required this.repository,
  });

  @override
  Widget build(BuildContext context) {
    final sfx = sl<GameSfx>();
    return BlocBuilder<ClueHuntBloc, ClueHuntState>(
      builder: (context, state) {
        final session = state.session;
        if (session == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        switch (session.phase) {
          case CluePhase.lobby:
            return _LobbyScaffold(
                isHost: isHost, selfId: selfId, session: session);
          case CluePhase.hiding:
          case CluePhase.seeking:
            return _HuntScaffold(
              session: session,
              selfId: selfId,
              repository: repository,
              sfx: sfx,
            );
          case CluePhase.roundResult:
            return _RoundResultScaffold(
                isHost: isHost, selfId: selfId, session: session);
          case CluePhase.gameOver:
            return _GameOverScaffold(
                isHost: isHost, selfId: selfId, session: session);
        }
      },
    );
  }
}

// ---- Lobby -----------------------------------------------------------------

class _LobbyScaffold extends StatelessWidget {
  final bool isHost;
  final String selfId;
  final ClueHuntSession session;

  const _LobbyScaffold(
      {required this.isHost, required this.selfId, required this.session});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enoughPlayers = session.players.length >= 2;
    return Scaffold(
      appBar: AppBar(title: const Text('Clue Hunt — Lobby')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: Text('🔍', style: TextStyle(fontSize: 48))),
            const SizedBox(height: 6),
            Text('Clue Hunt',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(
              isHost
                  ? 'Gather everyone, then start. You hide a real object first; '
                      'the rest hunt while you drive the warmer/colder meter. '
                      'Then the role rotates. ${session.totalRounds} rounds.'
                  : "You're in! When the host starts, one person hides a real "
                      'object and everyone else hunts. Watch the meter.',
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
                          child: Text(p.name.isNotEmpty
                              ? p.name[0].toUpperCase()
                              : '?'),
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
                onPressed: enoughPlayers
                    ? () => context
                        .read<ClueHuntBloc>()
                        .add(const ClueGameStarted())
                    : null,
                icon: const Icon(Icons.play_arrow),
                label: Text(enoughPlayers
                    ? 'Start Clue Hunt (you hide first)'
                    : 'Waiting for players to join…'),
              )
            else
              Center(
                child: Text('Waiting for the host to start…',
                    style: theme.textTheme.bodyMedium),
              ),
          ],
        ),
      ),
    );
  }
}

// ---- Live hunt (hiding + seeking) ------------------------------------------

class _HuntScaffold extends StatelessWidget {
  final ClueHuntSession session;
  final String selfId;
  final ClueHuntRepository repository;
  final GameSfx sfx;

  const _HuntScaffold({
    required this.session,
    required this.selfId,
    required this.repository,
    required this.sfx,
  });

  @override
  Widget build(BuildContext context) {
    final iAmHider = session.hiderId == selfId;
    final title = iAmHider ? 'Clue Hunt — Hider' : 'Clue Hunt — Seeker';
    return Scaffold(
      appBar: AppBar(title: Text(title), automaticallyImplyLeading: false),
      body: iAmHider
          ? ClueHiderView(repository: repository, session: session)
          : _seekerBody(),
    );
  }

  Widget _seekerBody() {
    // While the hider is still hiding, seekers wait; the meter goes live only
    // once the hunt begins.
    if (session.phase == CluePhase.hiding) {
      return _WaitingToHide(session: session);
    }
    return ClueSeekerView(
      repository: repository,
      session: session,
      selfId: selfId,
      sfx: sfx,
    );
  }
}

class _WaitingToHide extends StatelessWidget {
  final ClueHuntSession session;
  const _WaitingToHide({required this.session});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🫥', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            Text('${session.hider?.name ?? 'The hider'} is hiding the object…',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Get ready to hunt. The heat meter goes live any second.',
                textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 24),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

// ---- Round result ----------------------------------------------------------

class _RoundResultScaffold extends StatelessWidget {
  final bool isHost;
  final String selfId;
  final ClueHuntSession session;

  const _RoundResultScaffold(
      {required this.isHost, required this.selfId, required this.session});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final finder = session.lastFinder;
    final award = session.lastAward ?? 0;
    final isLastRound = session.roundNumber >= session.totalRounds;
    return Scaffold(
      appBar: AppBar(
          title: const Text('Clue Hunt — Round over'),
          automaticallyImplyLeading: false),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            const Center(child: Text('🎉', style: TextStyle(fontSize: 48))),
            const SizedBox(height: 8),
            Text(
              finder == null
                  ? 'Round ${session.roundNumber} done!'
                  : '${finder.name} found it! +$award',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Text('Standings',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: ClueScoreboard(session: session, selfId: selfId),
              ),
            ),
            if (isHost)
              FilledButton.icon(
                onPressed: () =>
                    context.read<ClueHuntBloc>().add(const ClueNextRound()),
                icon: Icon(isLastRound ? Icons.emoji_events : Icons.skip_next),
                label: Text(isLastRound ? 'See the winner' : 'Next round'),
              )
            else
              Center(
                child: Text('Waiting for the host to continue…',
                    style: theme.textTheme.bodyMedium),
              ),
          ],
        ),
      ),
    );
  }
}

// ---- Game over (winner ceremony) -------------------------------------------

class _GameOverScaffold extends StatefulWidget {
  final bool isHost;
  final String selfId;
  final ClueHuntSession session;

  const _GameOverScaffold(
      {required this.isHost, required this.selfId, required this.session});

  @override
  State<_GameOverScaffold> createState() => _GameOverScaffoldState();
}

class _GameOverScaffoldState extends State<_GameOverScaffold>
    with SingleTickerProviderStateMixin {
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
    final session = widget.session;
    final winner =
        session.leaderboard.isNotEmpty ? session.leaderboard.first : null;
    final trophyIn = _slice(0.0, 0.55, curve: Curves.elasticOut);
    final winnerIn = _slice(0.2, 0.6);
    final standingsIn = _slice(0.45, 1.0);
    return Scaffold(
      appBar: AppBar(
          title: const Text('Clue Hunt — Winner'),
          automaticallyImplyLeading: false),
      body: Stack(
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
                    child: const Text('🏆', style: TextStyle(fontSize: 56)),
                  ),
                ),
                const SizedBox(height: 6),
                FadeTransition(
                  opacity: winnerIn,
                  child: Text(
                    winner == null
                        ? 'Game over!'
                        : '${winner.name} wins with ${winner.totalScore}!',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: FadeTransition(
                    opacity: standingsIn,
                    child: SingleChildScrollView(
                      child:
                          ClueScoreboard(session: session, selfId: widget.selfId),
                    ),
                  ),
                ),
                if (widget.isHost)
                  FilledButton.icon(
                    onPressed: () =>
                        context.read<ClueHuntBloc>().add(const CluePlayAgain()),
                    icon: const Icon(Icons.replay),
                    label: const Text('Play again'),
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
          const Positioned.fill(child: ConfettiBurst()),
        ],
      ),
    );
  }
}
