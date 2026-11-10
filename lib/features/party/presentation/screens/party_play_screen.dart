import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/services/sfx/game_sfx.dart';
import '../../../../core/widgets/ar_fx.dart';
import '../../domain/party_game.dart';
import '../../domain/party_tasks.dart';
import '../widgets/party_stage.dart';

enum _Phase {
  handoff,
  handoffDone,
  intro,
  clock,
  twist,
  judge,
  scores,
  missionReveal,
  champion,
}

/// In-person party mode: one phone is the host. It hands out secret
/// missions privately, reads each task in big type, runs the clock, takes
/// the room's verdict and keeps score, then crowns a champion.
///
/// Everything is local state ([PartyGame]); nothing touches Firestore.
class PartyPlayScreen extends StatefulWidget {
  final List<String> players;
  final int taskCount;
  final bool withMissions;

  /// Seeded in tests so the pack and missions are deterministic.
  final Random? random;

  const PartyPlayScreen({
    super.key,
    required this.players,
    required this.taskCount,
    this.withMissions = true,
    this.random,
  });

  @override
  State<PartyPlayScreen> createState() => _PartyPlayScreenState();
}

class _PartyPlayScreenState extends State<PartyPlayScreen> {
  late PartyGame _game;
  late _Phase _phase;

  // Mission hand-out / reveal.
  int _missionIdx = 0;
  bool _missionShown = false;
  int _revealIdx = 0;

  // Clock.
  bool _twistPart = false;
  int _turn = 0;
  int _remaining = 0;
  bool _running = false;
  bool _timeUp = false;
  Timer? _timer;

  // Judging.
  final List<int> _ranking = [];
  PartyTaskResult? _lastResult;

  GameSfx get _sfx =>
      sl.isRegistered<GameSfx>() ? sl<GameSfx>() : const SilentGameSfx();

  @override
  void initState() {
    super.initState();
    _newGame();
  }

  void _newGame() {
    _game = PartyGame.start(
      players: widget.players,
      taskCount: widget.taskCount,
      withMissions: widget.withMissions,
      random: widget.random,
    );
    _phase = _game.hasMissions ? _Phase.handoff : _Phase.intro;
    _missionIdx = 0;
    _missionShown = false;
    _revealIdx = 0;
    _lastResult = null;
    _ranking.clear();
    _resetClock(twist: false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  PartyTask get _task => _game.currentTask!;
  List<String> get _players => _game.players;

  bool get _clockPerPlayer =>
      _twistPart ? _task.twistPerPlayer : _task.perPlayer;
  int get _clockSeconds => _twistPart ? _task.twistSeconds : _task.seconds;

  // ---------------------------------------------------------------- clock --

  void _resetClock({required bool twist}) {
    _timer?.cancel();
    _twistPart = twist;
    _turn = 0;
    _running = false;
    _timeUp = false;
    _remaining = _game.currentTask == null ? 0 : _clockSeconds;
  }

  void _startClock() {
    HapticFeedback.mediumImpact();
    _sfx
      ..prime()
      ..go();
    _timer?.cancel();
    setState(() {
      _phase = _Phase.clock;
      _running = true;
      _timeUp = false;
      _remaining = _clockSeconds;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (!mounted) return;
    setState(() => _remaining = max(0, _remaining - 1));
    if (_remaining == 0) {
      _endClock();
    } else if (_remaining <= 5) {
      _sfx.tick();
    }
  }

  void _endClock() {
    _timer?.cancel();
    HapticFeedback.heavyImpact();
    _sfx.fanfare();
    setState(() {
      _running = false;
      _timeUp = true;
    });
  }

  void _afterClock() {
    if (_clockPerPlayer && _turn < _players.length - 1) {
      setState(() {
        _turn++;
        _running = false;
        _timeUp = false;
        _remaining = _clockSeconds;
      });
    } else if (_task.hasTwist && !_twistPart) {
      _sfx.whoosh();
      setState(() {
        _resetClock(twist: true);
        _phase = _Phase.twist;
      });
    } else {
      setState(() {
        _ranking.clear();
        _phase = _Phase.judge;
      });
    }
  }

  // -------------------------------------------------------------- judging --

  void _tapRank(int player) {
    if (_ranking.contains(player)) return;
    HapticFeedback.selectionClick();
    setState(() {
      _ranking.add(player);
      // The last one standing places itself.
      if (_ranking.length == _players.length - 1) {
        _ranking.add(List<int>.generate(_players.length, (i) => i)
            .firstWhere((p) => !_ranking.contains(p)));
      }
    });
  }

  void _lockIn(List<int> ranking) {
    _sfx.pop();
    setState(() {
      _lastResult = _game.scoreCurrentTask(ranking);
      _phase = _Phase.scores;
    });
  }

  void _afterScores() {
    setState(() {
      if (!_game.allTasksScored) {
        _resetClock(twist: false);
        _phase = _Phase.intro;
      } else if (_game.hasMissions) {
        _revealIdx = 0;
        _phase = _Phase.missionReveal;
      } else {
        _crown();
      }
    });
  }

  void _crown() {
    _phase = _Phase.champion;
    _sfx.fanfare();
    HapticFeedback.heavyImpact();
  }

  void _missionVerdict(bool done) {
    if (done) _sfx.pop();
    setState(() {
      _game.setMissionOutcome(_revealIdx, done);
      if (_revealIdx < _players.length - 1) {
        _revealIdx++;
      } else {
        _crown();
      }
    });
  }

  // ---------------------------------------------------------------- leave --

  Future<void> _confirmLeave() async {
    if (_phase == _Phase.champion) {
      Navigator.of(context).pop();
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave the party?'),
        content: const Text('The scores go with you. Nobody will know who '
            'won. Everybody will suspect.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Stay')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Leave')),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.of(context).pop();
  }

  // ---------------------------------------------------------------- build --

  String get _taskHeader =>
      'TASK ${_game.currentTaskIndex + 1} OF ${_game.tasks.length}';

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) _confirmLeave();
      },
      child: switch (_phase) {
        _Phase.handoff => _missionShown ? _buildMission() : _buildPass(),
        _Phase.handoffDone => _buildHandoffDone(),
        _Phase.intro => _buildIntro(),
        _Phase.clock => _buildClock(),
        _Phase.twist => _buildTwist(),
        _Phase.judge => _buildJudge(),
        _Phase.scores => _buildScores(),
        _Phase.missionReveal => _buildMissionReveal(),
        _Phase.champion => _buildChampion(),
      },
    );
  }

  Widget _buildPass() {
    final name = _players[_missionIdx];
    return PartyStage(
      key: ValueKey('pass-$_missionIdx'),
      centerBody: true,
      header: 'SECRET MISSIONS',
      onClose: _confirmLeave,
      body: Column(
        children: [
          const SizedBox(height: 24),
          const Icon(Icons.visibility_off_rounded,
              size: 72, color: PartyColors.gold),
          const SizedBox(height: 24),
          Text('Pass the phone to', style: partyBody(20, PartyColors.muted)),
          const SizedBox(height: 8),
          Text(name,
              textAlign: TextAlign.center, style: partyTitle(48)),
          const SizedBox(height: 20),
          Text(
            'Everyone else, look away. This is between $name and the phone.',
            textAlign: TextAlign.center,
            style: partyBody(19, PartyColors.muted),
          ),
        ],
      ),
      actions: [
        PartyButton(
          label: "I'm $name. Show me",
          onPressed: () {
            HapticFeedback.selectionClick();
            setState(() => _missionShown = true);
          },
        ),
      ],
    );
  }

  Widget _buildMission() {
    final name = _players[_missionIdx];
    final last = _missionIdx == _players.length - 1;
    return PartyStage(
      key: ValueKey('mission-$_missionIdx'),
      header: 'FOR ${name.toUpperCase()} ONLY',
      centerBody: true,
      onClose: _confirmLeave,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          const Center(child: PartyStamp('TOP SECRET')),
          const SizedBox(height: 28),
          Text('Your secret mission',
              textAlign: TextAlign.center,
              style: partyBody(18, PartyColors.muted)),
          const SizedBox(height: 12),
          Text(_game.missions[_missionIdx]!,
              textAlign: TextAlign.center, style: partyTitle(32)),
          const SizedBox(height: 24),
          Text(
            'Do it sneakily before the end. Worth $kSecretMissionBonus '
            'points if the room agrees you pulled it off.',
            textAlign: TextAlign.center,
            style: partyBody(17, PartyColors.muted),
          ),
        ],
      ),
      actions: [
        PartyButton(
          label: last ? 'Hide it' : 'Hide it, pass it on',
          icon: Icons.visibility_off,
          onPressed: () {
            HapticFeedback.selectionClick();
            setState(() {
              _missionShown = false;
              if (last) {
                _phase = _Phase.handoffDone;
              } else {
                _missionIdx++;
              }
            });
          },
        ),
      ],
    );
  }

  Widget _buildHandoffDone() {
    return PartyStage(
      header: 'SECRET MISSIONS',
      centerBody: true,
      onClose: _confirmLeave,
      body: Column(
        children: [
          const Icon(Icons.lock_rounded, size: 72, color: PartyColors.gold),
          const SizedBox(height: 24),
          Text('Everyone has a secret.',
              textAlign: TextAlign.center, style: partyTitle(34)),
          const SizedBox(height: 16),
          Text(
            'Put the phone where the whole room can see it. Trust no one.',
            textAlign: TextAlign.center,
            style: partyBody(20, PartyColors.muted),
          ),
        ],
      ),
      actions: [
        PartyButton(
          label: 'First task',
          onPressed: () => setState(() => _phase = _Phase.intro),
        ),
      ],
    );
  }

  Widget _kindBadge(PartyTask task) {
    final color = switch (task.kind) {
      PartyTaskKind.headToHead => PartyColors.coral,
      PartyTaskKind.performance => const Color(0xFF14B8A6),
      PartyTaskKind.gatherReveal => const Color(0xFF8B5CF6),
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(task.kind.label,
            style: const TextStyle(
                fontFamily: 'Fredoka',
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
                letterSpacing: 1.5)),
      ),
    );
  }

  String _clockNote(PartyTask task) {
    if (task.perPlayer) return '${task.seconds} seconds each, one at a time.';
    return '${_fmt(task.seconds)} on the clock. Everyone at once.';
  }

  Widget _buildIntro() {
    final task = _task;
    return PartyStage(
      key: ValueKey('intro-${task.id}'),
      header: _taskHeader,
      onClose: _confirmLeave,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _kindBadge(task),
          const SizedBox(height: 16),
          Text(task.title, style: partyTitle(38)),
          const SizedBox(height: 16),
          Text(task.prompt, style: partyBody(24)),
          const SizedBox(height: 20),
          Row(
            children: [
              const Icon(Icons.timer_outlined,
                  color: PartyColors.gold, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_clockNote(task),
                    style: partyBody(17, PartyColors.gold)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Read it aloud. Then start the clock.',
              style: partyBody(15, PartyColors.muted)),
        ],
      ),
      actions: [
        PartyButton(
          label: task.perPlayer
              ? 'First up: ${_players.first}'
              : 'Start the clock',
          icon: task.perPlayer ? null : Icons.play_arrow_rounded,
          onPressed: task.perPlayer
              ? () => setState(() {
                    _resetClock(twist: false);
                    _phase = _Phase.clock;
                  })
              : _startClock,
        ),
      ],
    );
  }

  Widget _buildTwist() {
    final task = _task;
    return PartyStage(
      key: ValueKey('twist-${task.id}'),
      centerBody: true,
      header: _taskHeader,
      onClose: _confirmLeave,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          const Center(child: PartyStamp('TWIST', size: 34)),
          const SizedBox(height: 28),
          Text(task.twist!,
              textAlign: TextAlign.center, style: partyTitle(32)),
          const SizedBox(height: 20),
          Text(
            task.twistPerPlayer
                ? '${task.twistSeconds} seconds each, one at a time.'
                : '${_fmt(task.twistSeconds)} on the clock. Everyone at once.',
            textAlign: TextAlign.center,
            style: partyBody(17, PartyColors.gold),
          ),
        ],
      ),
      actions: [
        PartyButton(
          label: task.twistPerPlayer
              ? 'First up: ${_players.first}'
              : 'Start the clock',
          onPressed: task.twistPerPlayer
              ? () => setState(() => _phase = _Phase.clock)
              : _startClock,
        ),
      ],
    );
  }

  static String _fmt(int s) =>
      '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  Widget _buildClock() {
    final task = _task;
    final perPlayer = _clockPerPlayer;
    final total = _clockSeconds;
    final urgent = _running && _remaining <= 5;
    final String next;
    if (perPlayer && _turn < _players.length - 1) {
      next = 'Next: ${_players[_turn + 1]}';
    } else if (task.hasTwist && !_twistPart) {
      next = 'Reveal the twist';
    } else {
      next = 'Judge it';
    }

    return PartyStage(
      key: const ValueKey('clock'),
      centerBody: true,
      header: _taskHeader,
      onClose: _confirmLeave,
      body: Column(
        children: [
          Text(task.title,
              textAlign: TextAlign.center,
              style: partyBody(18, PartyColors.muted)),
          if (perPlayer) ...[
            const SizedBox(height: 8),
            Text("${_players[_turn]}, you're up",
                textAlign: TextAlign.center, style: partyTitle(32)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 220,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.square(
                  dimension: 210,
                  child: CircularProgressIndicator(
                    value: total == 0 ? 0 : _remaining / total,
                    strokeWidth: 12,
                    backgroundColor: PartyColors.card,
                    valueColor: AlwaysStoppedAnimation(
                        urgent ? PartyColors.coral : PartyColors.gold),
                  ),
                ),
                if (_timeUp)
                  const PartyStamp('TIME', size: 40)
                else
                  SizedBox(
                    width: 170,
                    child: FittedBox(
                      child: Text(
                        _fmt(_remaining),
                        key: const ValueKey('party-clock'),
                        style: partyTitle(80).copyWith(
                            color: urgent ? PartyColors.coral : null,
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ]),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _twistPart ? task.twist! : task.prompt,
            textAlign: TextAlign.center,
            style: partyBody(18, PartyColors.muted),
          ),
        ],
      ),
      actions: [
        if (_timeUp)
          PartyButton(label: next, onPressed: _afterClock)
        else if (_running)
          PartyButton(
              label: 'Done early', secondary: true, onPressed: _endClock)
        else
          PartyButton(
              label: 'Start',
              icon: Icons.play_arrow_rounded,
              onPressed: _startClock),
      ],
    );
  }

  static const _ordinals = ['1st', '2nd', '3rd', '4th', '5th', '6th', '7th',
      '8th'];

  Widget _buildJudge() {
    final task = _task;
    final two = _players.length == 2;
    final complete = _ranking.length == _players.length;
    return PartyStage(
      key: ValueKey('judge-${task.id}'),
      header: _taskHeader,
      onClose: _confirmLeave,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(two ? 'Who won?' : 'Rank them',
              style: partyTitle(36)),
          const SizedBox(height: 8),
          Text(
            two
                ? '${task.judging} Tap the winner.'
                : '${task.judging} Tap players best first.',
            style: partyBody(17, PartyColors.muted),
          ),
          const SizedBox(height: 16),
          for (var p = 0; p < _players.length; p++) ...[
            _NameTile(
              name: _players[p],
              compact: _players.length > 5,
              place: _ranking.contains(p)
                  ? _ordinals[_ranking.indexOf(p)]
                  : null,
              onTap: two
                  ? () {
                      HapticFeedback.selectionClick();
                      _lockIn([p, 1 - p]);
                    }
                  : () => _tapRank(p),
            ),
            SizedBox(height: _players.length > 5 ? 6 : 10),
          ],
        ],
      ),
      actions: two
          ? const []
          : [
              PartyButton(
                label: 'Lock it in',
                onPressed: complete ? () => _lockIn([..._ranking]) : null,
              ),
              if (_ranking.isNotEmpty)
                PartyButton(
                  label: 'Start over',
                  secondary: true,
                  onPressed: () => setState(_ranking.clear),
                ),
            ],
    );
  }

  Widget _buildScores() {
    final last = _lastResult!;
    final winner = _players[last.ranking.first];
    final String next;
    if (!_game.allTasksScored) {
      next = 'Next task';
    } else if (_game.hasMissions) {
      next = 'Reveal the secret missions';
    } else {
      next = 'Crown the champion';
    }
    return PartyStage(
      key: ValueKey('scores-${_game.results.length}'),
      header: 'AFTER TASK ${_game.results.length} OF ${_game.tasks.length}',
      onClose: _confirmLeave,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('$winner takes it.', style: partyTitle(34)),
          const SizedBox(height: 16),
          _Scoreboard(
            game: _game,
            delta: last.points,
          ),
        ],
      ),
      actions: [PartyButton(label: next, onPressed: _afterScores)],
    );
  }

  Widget _buildMissionReveal() {
    final name = _players[_revealIdx];
    return PartyStage(
      key: ValueKey('reveal-$_revealIdx'),
      centerBody: true,
      header: 'SECRET MISSIONS ${_revealIdx + 1} OF ${_players.length}',
      onClose: _confirmLeave,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Text("$name's secret mission was",
              textAlign: TextAlign.center,
              style: partyBody(19, PartyColors.muted)),
          const SizedBox(height: 14),
          Text(_game.missions[_revealIdx]!,
              textAlign: TextAlign.center, style: partyTitle(32)),
          const SizedBox(height: 28),
          Text('Did they pull it off?',
              textAlign: TextAlign.center, style: partyBody(22)),
          const SizedBox(height: 6),
          Text('The room decides. $name may plead their case.',
              textAlign: TextAlign.center,
              style: partyBody(16, PartyColors.muted)),
        ],
      ),
      actions: [
        PartyButton(
          label: 'They did. +$kSecretMissionBonus',
          onPressed: () => _missionVerdict(true),
        ),
        PartyButton(
          label: 'Not a chance',
          secondary: true,
          onPressed: () => _missionVerdict(false),
        ),
      ],
    );
  }

  Widget _buildChampion() {
    final champs = _game.champions();
    final names = champs.map((p) => _players[p]).join(' & ');
    return PartyStage(
      key: const ValueKey('champion'),
      header: 'FINAL SCORES',
      onClose: () => Navigator.of(context).pop(),
      overlay: const ConfettiBurst(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          const Icon(Icons.emoji_events_rounded,
              size: 80, color: PartyColors.gold),
          const SizedBox(height: 8),
          Center(
            child: PartyStamp(champs.length > 1 ? 'CO-CHAMPIONS' : 'CHAMPION',
                color: PartyColors.coral, size: 26),
          ),
          const SizedBox(height: 18),
          Text(names,
              key: const ValueKey('party-champion-name'),
              textAlign: TextAlign.center,
              style: partyTitle(44).copyWith(color: PartyColors.gold)),
          const SizedBox(height: 6),
          Text(
            '${_game.totalScore(champs.first)} points. '
            '${champs.length > 1 ? 'Shared, grudgingly.' : 'Nobody is surprised. Some are upset.'}',
            textAlign: TextAlign.center,
            style: partyBody(17, PartyColors.muted),
          ),
          const SizedBox(height: 20),
          _Scoreboard(game: _game, showMissions: _game.hasMissions),
        ],
      ),
      actions: [
        PartyButton(
          label: 'Play again',
          icon: Icons.replay_rounded,
          onPressed: () => setState(_newGame),
        ),
        PartyButton(
          label: 'Done',
          secondary: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _NameTile extends StatelessWidget {
  final String name;
  final String? place;
  final VoidCallback onTap;

  /// Tighter rows so a table of 6–8 mostly fits without scrolling.
  final bool compact;
  const _NameTile(
      {required this.name,
      required this.onTap,
      this.place,
      this.compact = false});

  @override
  Widget build(BuildContext context) {
    final picked = place != null;
    return Material(
      color: picked ? PartyColors.gold : PartyColors.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: picked ? null : onTap,
        child: Container(
          constraints: BoxConstraints(minHeight: compact ? 48 : 62),
          padding: EdgeInsets.symmetric(
              horizontal: 18, vertical: compact ? 6 : 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: picked ? PartyColors.gold : PartyColors.cardBorder,
                width: 2),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: partyTitle(compact ? 22 : 26).copyWith(
                        color: picked ? PartyColors.onGold : null)),
              ),
              if (picked)
                Text(place!,
                    style: partyTitle(24)
                        .copyWith(color: PartyColors.onGold)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Standings, best first: name, optional "+n this task", total.
class _Scoreboard extends StatelessWidget {
  final PartyGame game;
  final Map<int, int>? delta;
  final bool showMissions;
  const _Scoreboard(
      {required this.game, this.delta, this.showMissions = false});

  @override
  Widget build(BuildContext context) {
    final order = game.standings();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < order.length; i++) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: i == 0 ? const Color(0x33FBBF24) : PartyColors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: i == 0 ? PartyColors.gold : PartyColors.cardBorder,
                  width: 1.5),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 30,
                  child: Text('${i + 1}',
                      style: partyTitle(22).copyWith(
                          color: i == 0
                              ? PartyColors.gold
                              : PartyColors.muted)),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(game.players[order[i]],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: partyTitle(22)),
                      if (showMissions && game.missions[order[i]] != null)
                        Text(
                          game.missionOutcomes[order[i]] == true
                              ? 'Mission done +$kSecretMissionBonus'
                              : 'Mission failed',
                          style: partyBody(13, PartyColors.muted),
                        ),
                    ],
                  ),
                ),
                if (delta != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text('+${delta![order[i]] ?? 0}',
                        style: partyBody(17, PartyColors.gold)),
                  ),
                Text('${game.totalScore(order[i])}',
                    key: ValueKey('party-score-${order[i]}'),
                    style: partyTitle(28)),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}
