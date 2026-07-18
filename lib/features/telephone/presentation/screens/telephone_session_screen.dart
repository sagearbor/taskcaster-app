import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/models/telephone_session.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../data/datasources/telephone_session_store.dart';
import '../../domain/repositories/telephone_repository.dart';
import '../bloc/telephone_bloc.dart';
import '../widgets/drawing_canvas.dart';

/// Hosts a single Drawing Telephone game and renders the right UI for the
/// current phase. [playerId] is this device's per-session identity.
class TelephoneSessionScreen extends StatelessWidget {
  final String sessionId;
  final String playerId;
  final String displayName;

  /// Optional transport override. Defaults to the app's shared online
  /// [TelephoneRepository] (Firestore). "Practice (solo)" passes a local,
  /// fully-offline bot repository; offline play passes the Nearby-backed
  /// (Bluetooth / Wi-Fi Direct) repository — the same screens run over any.
  final TelephoneRepository? repository;

  const TelephoneSessionScreen({
    super.key,
    required this.sessionId,
    required this.playerId,
    required this.displayName,
    this.repository,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          TelephoneBloc(repository: repository ?? sl<TelephoneRepository>())
            ..add(TelephoneSubscribed(sessionId)),
      child: _SessionView(
        sessionId: sessionId,
        playerId: playerId,
      ),
    );
  }
}

class _SessionView extends StatelessWidget {
  final String sessionId;
  final String playerId;

  const _SessionView({required this.sessionId, required this.playerId});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<TelephoneBloc, TelephoneState>(
      listenWhen: (prev, curr) =>
          (curr.error != null && prev.error != curr.error) ||
          (curr.status == TelephoneStatus.error && curr.session == null),
      listener: (context, state) {
        if (state.error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.error!)),
          );
        }
        // Drop a stale saved pointer once the session is gone, so the start
        // screen won't keep offering "Rejoin" for a game that no longer exists.
        if (state.status == TelephoneStatus.error && state.session == null) {
          sl<TelephoneSessionStore>().clearIfSession(sessionId);
        }
      },
      builder: (context, state) {
        final session = state.session;
        final title = session?.gameName ?? 'Drawing Telephone';

        Widget body;
        if (state.status == TelephoneStatus.error && session == null) {
          body = _Centered(
            child: Text(state.error ?? 'Something went wrong.'),
          );
        } else if (session == null) {
          body = const _Centered(child: CircularProgressIndicator());
        } else {
          switch (session.phase) {
            case TelephonePhase.lobby:
              body = _LobbyView(session: session, playerId: playerId);
              break;
            case TelephonePhase.playing:
              body = _PlayView(session: session, playerId: playerId);
              break;
            case TelephonePhase.reveal:
              body = _RevealView(session: session);
              break;
            case TelephonePhase.rating:
              body = _RatingView(session: session, playerId: playerId);
              break;
            case TelephonePhase.results:
              body = _ResultsView(session: session, playerId: playerId);
              break;
          }
        }

        return Scaffold(
          appBar: AppBar(title: Text(title)),
          body: SafeArea(child: body),
        );
      },
    );
  }
}

class _Centered extends StatelessWidget {
  final Widget child;
  const _Centered({required this.child});
  @override
  Widget build(BuildContext context) => Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: child,
      ));
}

// ---------------------------------------------------------------------------
// Lobby
// ---------------------------------------------------------------------------

class _LobbyView extends StatelessWidget {
  final TelephoneSession session;
  final String playerId;

  const _LobbyView({required this.session, required this.playerId});

  Future<void> _confirmRemove(
    BuildContext context,
    TelephoneSession session,
    TelephonePlayer player,
  ) async {
    final bloc = context.read<TelephoneBloc>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove player?'),
        content: Text(
            'Remove ${player.displayName} from the game? They can rejoin with '
            'the invite code.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      bloc.add(TelephonePlayerRemoved(
        sessionId: session.id,
        uid: player.uid,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCreator = session.creatorUid == playerId;
    final canStart = session.playerCount >= 2;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Invite code', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: session.inviteCode));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Invite code copied')),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 20),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              session.inviteCode,
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: 8,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text('Tap to copy. Share it so friends can join.',
            style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
        const SizedBox(height: 24),
        Text('Players (${session.playerCount}/8)',
            style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        ...session.players.map((p) {
          final isHostRow = p.uid == session.creatorUid;
          // The host gets a kick control on every OTHER player's row — handy
          // for clearing an accidental duplicate or a no-show.
          final canKick = isCreator && !isHostRow;
          return ListTile(
            dense: true,
            leading: CircleAvatar(
              child: Text(p.displayName.isNotEmpty
                  ? p.displayName[0].toUpperCase()
                  : '?'),
            ),
            title: Text(p.displayName +
                (p.uid == playerId ? ' (you)' : '') +
                (isHostRow ? '  •  host' : '')),
            trailing: canKick
                ? IconButton(
                    icon: const Icon(Icons.person_remove_outlined),
                    tooltip: 'Remove ${p.displayName}',
                    onPressed: () => _confirmRemove(context, session, p),
                  )
                : null,
          );
        }),
        const SizedBox(height: 24),
        if (isCreator)
          FilledButton.icon(
            onPressed: canStart
                ? () => context
                    .read<TelephoneBloc>()
                    .add(TelephoneStarted(session.id))
                : null,
            icon: const Icon(Icons.play_arrow),
            label: Text(canStart
                ? 'Start game'
                : 'Waiting for at least 2 players…'),
          )
        else
          Center(
            child: Text('Waiting for the host to start…',
                style: theme.textTheme.bodyMedium),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Play
// ---------------------------------------------------------------------------

class _PlayView extends StatelessWidget {
  final TelephoneSession session;
  final String playerId;

  const _PlayView({required this.session, required this.playerId});

  @override
  Widget build(BuildContext context) {
    if (!session.hasPlayer(playerId)) {
      return const _Centered(
        child: Text('You are not part of this game.'),
      );
    }

    // Same-prompt modes: everyone draws the SAME shared prompt. In turn-taking
    // only the active drawer gets the canvas; everyone else waits.
    if (session.gameMode.isSamePrompt) {
      if (session.isAwaitingSubmission(playerId)) {
        return _SamePromptDrawInput(
          key: ValueKey('draw-${session.step}-$playerId'),
          session: session,
          playerId: playerId,
        );
      }
      return _SamePromptWaitingView(session: session, playerId: playerId);
    }

    // Classic chain.
    if (session.hasSubmittedCurrentStep(playerId)) {
      return _WaitingView(session: session);
    }
    final type = session.currentEntryType;
    final key = ValueKey('step-${session.step}-$playerId');
    switch (type) {
      case TelephoneEntryType.prompt:
        return _PromptInput(key: key, session: session, playerId: playerId);
      case TelephoneEntryType.drawing:
        return _DrawInput(key: key, session: session, playerId: playerId);
      case TelephoneEntryType.guess:
        return _GuessInput(key: key, session: session, playerId: playerId);
    }
  }
}

class _StepHeader extends StatelessWidget {
  final TelephoneSession session;
  final String instruction;
  const _StepHeader({required this.session, required this.instruction});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Round ${session.step + 1} of ${session.totalSteps}',
            style: theme.textTheme.labelMedium
                ?.copyWith(color: theme.colorScheme.primary)),
        const SizedBox(height: 4),
        Text(instruction,
            style:
                theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
      ],
    );
  }
}

void _submit(BuildContext context, TelephoneSession session, String uid,
    String content) {
  context.read<TelephoneBloc>().add(TelephoneEntrySubmitted(
        sessionId: session.id,
        uid: uid,
        content: content,
      ));
}

void _playAgain(BuildContext context, TelephoneSession session) {
  context
      .read<TelephoneBloc>()
      .add(TelephonePlayAgainRequested(session.id));
}

/// The step's submit button. While the bloc has a submission in flight it
/// shows a spinner and disables itself, and if the send fails (e.g. an offline
/// peer whose link to the host dropped) it re-enables so the exact same
/// content can simply be re-sent — no more "the button did nothing".
class _SubmitButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  const _SubmitButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final submitting =
        context.select((TelephoneBloc bloc) => bloc.state.submitting);
    return FilledButton(
      onPressed: submitting ? null : onPressed,
      child: submitting
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          : Text(label),
    );
  }
}

/// The big one-tap "Play again" button used by both the classic reveal and the
/// same-prompt results screen — repeat with the same crew and settings.
class _PlayAgainButton extends StatelessWidget {
  final TelephoneSession session;
  const _PlayAgainButton({required this.session});

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: () => _playAgain(context, session),
      icon: const Icon(Icons.replay),
      label: const Text('Play again — same crew'),
    );
  }
}

class _PromptInput extends StatefulWidget {
  final TelephoneSession session;
  final String playerId;
  const _PromptInput(
      {super.key, required this.session, required this.playerId});

  @override
  State<_PromptInput> createState() => _PromptInputState();
}

class _PromptInputState extends State<_PromptInput> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _StepHeader(
          session: widget.session,
          instruction: 'Write a prompt for someone to draw',
        ),
        TextField(
          controller: _controller,
          autofocus: true,
          maxLength: 120,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'e.g. A cat riding a skateboard on the moon',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _send(),
        ),
        const SizedBox(height: 8),
        _SubmitButton(label: 'Submit prompt', onPressed: _send),
      ],
    );
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Write something first!')),
      );
      return;
    }
    _submit(context, widget.session, widget.playerId, text);
  }
}

class _DrawInput extends StatefulWidget {
  final TelephoneSession session;
  final String playerId;
  const _DrawInput({super.key, required this.session, required this.playerId});

  @override
  State<_DrawInput> createState() => _DrawInputState();
}

class _DrawInputState extends State<_DrawInput> {
  final _controller = DrawingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prompt = widget.session.promptEntryForUid(widget.playerId);
    final theme = Theme.of(context);
    // NOT a ListView: a finger-drag on the canvas must DRAW, not scroll the
    // page. The canvas is a direct child so it owns the drag gestures.
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StepHeader(
            session: widget.session,
            instruction: 'Draw this prompt',
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              prompt?.content ?? '(missing prompt)',
              style: theme.textTheme.titleMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 12),
          DrawingCanvas(controller: _controller),
          const SizedBox(height: 12),
          _SubmitButton(label: 'Submit drawing', onPressed: _send),
        ],
      ),
    );
  }

  void _send() {
    if (!_controller.hasVisibleInk) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Draw something first!')),
      );
      return;
    }
    _submit(context, widget.session, widget.playerId, _controller.toJson());
  }
}

class _GuessInput extends StatefulWidget {
  final TelephoneSession session;
  final String playerId;
  const _GuessInput({super.key, required this.session, required this.playerId});

  @override
  State<_GuessInput> createState() => _GuessInputState();
}

class _GuessInputState extends State<_GuessInput> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final drawing = widget.session.promptEntryForUid(widget.playerId);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _StepHeader(
          session: widget.session,
          instruction: 'What is this a drawing of?',
        ),
        // The drawing replays itself stroke-by-stroke — watching it appear is
        // half the fun (and often half the clue).
        AnimatedDrawingView(json: drawing?.content ?? ''),
        const SizedBox(height: 16),
        TextField(
          controller: _controller,
          autofocus: true,
          maxLength: 120,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Your best guess…',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _send(),
        ),
        const SizedBox(height: 8),
        _SubmitButton(label: 'Submit guess', onPressed: _send),
      ],
    );
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Type a guess first!')),
      );
      return;
    }
    _submit(context, widget.session, widget.playerId, text);
  }
}

class _WaitingView extends StatelessWidget {
  final TelephoneSession session;
  const _WaitingView({required this.session});

  /// Playful waiting copy. `{name}` is replaced with the first player we're
  /// still waiting on. Picked deterministically per step, so the quip is
  /// stable across rebuilds within a phase.
  static const List<String> _quips = [
    'Waiting for {name} to finish their masterpiece…',
    '{name} is still picking the perfect colour…',
    'Shh — {name} is deep in creative thought…',
    '{name} promises it looks better in person…',
    'Hang tight — {name} is really committing to the bit…',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final waitingOn = session.players
        .where((p) => !session.hasSubmittedCurrentStep(p.uid))
        .toList();
    final quip = waitingOn.isEmpty
        ? 'Everyone is done — moving on!'
        : _quips[session.step % _quips.length]
            .replaceAll('{name}', waitingOn.first.displayName);

    return _Centered(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Submitted! 🎉',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            '${session.submittedUids.length}/${session.playerCount} done',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 28),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final p in session.players)
                _PlayerProgressChip(
                  name: p.displayName,
                  submitted: session.hasSubmittedCurrentStep(p.uid),
                ),
            ],
          ),
          const SizedBox(height: 28),
          Text(quip,
              style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

/// One player's avatar in the waiting view: greyed while they're still
/// working, popping to full colour with a check badge once they submit.
class _PlayerProgressChip extends StatelessWidget {
  final String name;
  final bool submitted;
  const _PlayerProgressChip({required this.name, required this.submitted});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 72,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedScale(
            scale: submitted ? 1.0 : 0.88,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutBack,
            child: AnimatedOpacity(
              opacity: submitted ? 1.0 : 0.4,
              duration: const Duration(milliseconds: 300),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  UserAvatar(displayName: name, radius: 24),
                  if (submitted)
                    Positioned(
                      right: -3,
                      bottom: -3,
                      child: Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check_circle,
                            size: 20, color: Color(0xFF43A047)),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            name,
            style: theme.textTheme.labelSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reveal
// ---------------------------------------------------------------------------

/// The reveal — the game's payoff. Chains are presented one at a time,
/// entry by entry (tap anywhere / "Next" to advance), so the whole room
/// watches each corruption step land. After the last chain it settles on the
/// full recap list.
///
/// The reveal cursor is pure local widget state: every device advances at its
/// own pace and the session model / transport are untouched.
class _RevealView extends StatefulWidget {
  final TelephoneSession session;
  const _RevealView({required this.session});

  @override
  State<_RevealView> createState() => _RevealViewState();
}

class _RevealViewState extends State<_RevealView> {
  int _chainIndex = 0;
  int _entryIndex = 0;
  bool _finished = false;
  final _scrollController = ScrollController();

  List<List<TelephoneEntry>> get _chains =>
      widget.session.chains.where((c) => c.isNotEmpty).toList();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _advance() {
    if (_finished) return;
    final chains = _chains;
    if (chains.isEmpty) return;
    setState(() {
      if (_entryIndex < chains[_chainIndex].length - 1) {
        _entryIndex++;
      } else if (_chainIndex < chains.length - 1) {
        _chainIndex++;
        _entryIndex = 0;
      } else {
        _finished = true;
      }
    });
    // Keep the newest entry in view as the chain grows.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_finished || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chains = _chains;
    if (chains.isEmpty || _finished) {
      // Final state: the full recap (with a little ceremony on top and the
      // one-tap "Play again — same crew" footer).
      return _RevealRecap(
        session: widget.session,
        chains: chains,
        celebrate: chains.isNotEmpty,
      );
    }

    // Clamp defensively in case the session updates under us.
    final chainIdx = _chainIndex.clamp(0, chains.length - 1);
    final chain = chains[chainIdx];
    final entryIdx = _entryIndex.clamp(0, chain.length - 1);
    final starter = chain.first.authorName;
    final isLastEntry = entryIdx == chain.length - 1;
    final isLastChain = chainIdx == chains.length - 1;
    final nextLabel = !isLastEntry
        ? 'Next'
        : (isLastChain ? 'See full recap' : 'Next chain');

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _advance,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Chain ${chainIdx + 1} of ${chains.length} '
                  '· step ${entryIdx + 1}/${chain.length}',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: theme.colorScheme.primary),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("$starter's chain",
                            style: theme.textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const Divider(),
                        for (var i = 0; i <= entryIdx; i++)
                          _SlideFadeIn(
                            key: ValueKey('reveal-$chainIdx-$i'),
                            child: _RevealEntry(
                              entry: chain[i],
                              // Drawings replay themselves as they're revealed.
                              animateDrawing: true,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: Text('Tap anywhere to continue',
                      style: theme.textTheme.bodySmall),
                ),
                FilledButton.icon(
                  onPressed: _advance,
                  icon: const Icon(Icons.navigate_next),
                  label: Text(nextLabel),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One-shot slide-up + fade-in for a newly revealed entry.
class _SlideFadeIn extends StatelessWidget {
  final Widget child;
  const _SlideFadeIn({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 24 * (1 - t)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// The full recap list (every chain, every entry) shown once the staged
/// reveal has finished — with a celebratory beat on top and the one-tap
/// "Play again" footer.
class _RevealRecap extends StatelessWidget {
  final TelephoneSession session;
  final List<List<TelephoneEntry>> chains;
  final bool celebrate;
  const _RevealRecap({
    required this.session,
    required this.chains,
    required this.celebrate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (celebrate) const _RevealCeremony(),
        for (final chain in chains)
          Card(
            margin: const EdgeInsets.only(bottom: 20),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("${chain.first.authorName}'s chain",
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const Divider(),
                  ...chain.map((entry) => _RevealEntry(entry: entry)),
                ],
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 24),
          child: _PlayAgainButton(session: session),
        ),
      ],
    );
  }
}

/// A short (~1.5s, plays once) celebration: trophy pops in with an elastic
/// scale while a hand-rolled confetti burst falls in staggered rows behind it.
class _RevealCeremony extends StatefulWidget {
  const _RevealCeremony();

  @override
  State<_RevealCeremony> createState() => _RevealCeremonyState();
}

class _RevealCeremonyState extends State<_RevealCeremony>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..forward();

  late final Animation<double> _trophyScale = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.0, 0.55, curve: Curves.elasticOut),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 170,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => CustomPaint(
                painter: _ConfettiPainter(_controller.value),
              ),
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ScaleTransition(
                scale: _trophyScale,
                child: const Icon(Icons.emoji_events,
                    size: 56, color: Color(0xFFF4B400)),
              ),
              const SizedBox(height: 8),
              Text("That's a wrap!",
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text('Every chain, fully derailed. Enjoy the recap.',
                  style: theme.textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConfettiPiece {
  final double x; // 0..1 horizontal start position
  final double delay; // 0..1 fraction of the animation before this piece drops
  final double drift; // horizontal drift over the fall
  final double spin; // radians of rotation over the fall
  final double size;
  final Color color;

  const _ConfettiPiece({
    required this.x,
    required this.delay,
    required this.drift,
    required this.spin,
    required this.size,
    required this.color,
  });
}

/// Lightweight confetti: a fixed, seeded particle set (deterministic — no
/// per-frame allocation) dropped in three staggered rows. Fades out at the
/// end and never loops.
class _ConfettiPainter extends CustomPainter {
  final double progress;
  _ConfettiPainter(this.progress);

  static final List<_ConfettiPiece> _pieces = _buildPieces();

  static List<_ConfettiPiece> _buildPieces() {
    final rng = math.Random(7);
    const colors = [
      Color(0xFFE53935),
      Color(0xFF1E88E5),
      Color(0xFF43A047),
      Color(0xFFFB8C00),
      Color(0xFF8E24AA),
      Color(0xFFF4B400),
    ];
    return List.generate(36, (i) {
      final row = i % 3; // staggered rows
      return _ConfettiPiece(
        x: rng.nextDouble(),
        delay: row * 0.14 + rng.nextDouble() * 0.08,
        drift: (rng.nextDouble() - 0.5) * 0.35,
        spin: (rng.nextDouble() - 0.5) * 10,
        size: 4 + rng.nextDouble() * 4,
        color: colors[i % colors.length],
      );
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final paint = Paint();
    for (final piece in _pieces) {
      final t = ((progress - piece.delay) / (1 - piece.delay)).clamp(0.0, 1.0);
      if (t <= 0) continue;
      final opacity = t < 0.75 ? 1.0 : 1.0 - (t - 0.75) / 0.25;
      final x = (piece.x + piece.drift * t) * size.width;
      final y = t * t * (size.height + 24) - 12; // accelerating fall
      paint.color = piece.color.withOpacity(opacity.clamp(0.0, 1.0));
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(piece.spin * t);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset.zero, width: piece.size, height: piece.size * 0.6),
          const Radius.circular(1),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _RevealEntry extends StatelessWidget {
  final TelephoneEntry entry;

  /// When true, drawings use [AnimatedDrawingView] so they replay stroke by
  /// stroke as they're revealed. The recap keeps the static [DrawingView].
  final bool animateDrawing;

  const _RevealEntry({required this.entry, this.animateDrawing = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = switch (entry.type) {
      TelephoneEntryType.prompt => '✍️ ${entry.authorName} wrote',
      TelephoneEntryType.drawing => '🎨 ${entry.authorName} drew',
      TelephoneEntryType.guess => '💭 ${entry.authorName} guessed',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: theme.colorScheme.primary)),
          const SizedBox(height: 6),
          if (entry.type == TelephoneEntryType.drawing)
            animateDrawing
                ? AnimatedDrawingView(json: entry.content, size: 220)
                : DrawingView(json: entry.content, size: 220)
          else
            Text(entry.content, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Same prompt — draw + wait
// ---------------------------------------------------------------------------

/// Draw the ONE shared prompt everyone is drawing (same-prompt modes). Reuses
/// the exact [DrawingCanvas]; the difference from the classic draw step is the
/// thing being drawn is `session.prompt`, not the previous link in a chain.
class _SamePromptDrawInput extends StatefulWidget {
  final TelephoneSession session;
  final String playerId;
  const _SamePromptDrawInput(
      {super.key, required this.session, required this.playerId});

  @override
  State<_SamePromptDrawInput> createState() => _SamePromptDrawInputState();
}

class _SamePromptDrawInputState extends State<_SamePromptDrawInput> {
  final _controller = DrawingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = widget.session;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            session.gameMode.isTurnTaking
                ? "Your turn! Everyone draws the same thing"
                : 'Everyone draws the same thing!',
            style: theme.textTheme.labelMedium
                ?.copyWith(color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 4),
          Text('Draw the prompt',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              session.prompt.isEmpty ? '(no prompt)' : session.prompt,
              style: theme.textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 12),
          DrawingCanvas(controller: _controller),
          const SizedBox(height: 12),
          _SubmitButton(label: 'Submit drawing', onPressed: _send),
        ],
      ),
    );
  }

  void _send() {
    if (!_controller.hasVisibleInk) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Draw something first!')),
      );
      return;
    }
    _submit(context, widget.session, widget.playerId, _controller.toJson());
  }
}

/// Shown to a same-prompt player who can't draw right now: either they already
/// submitted, or (turn-taking) it isn't their turn yet.
class _SamePromptWaitingView extends StatelessWidget {
  final TelephoneSession session;
  final String playerId;
  const _SamePromptWaitingView(
      {required this.session, required this.playerId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = session.chains.where((c) => c.isNotEmpty).length;
    final total = session.playerCount;

    final String headline;
    if (session.hasSubmittedCurrentStep(playerId)) {
      headline = 'Drawing submitted! 🎉';
    } else if (session.gameMode.isTurnTaking) {
      final drawer = session.activeDrawer;
      headline = drawer == null
          ? 'Waiting…'
          : "It's ${drawer.displayName}'s turn to draw";
    } else {
      headline = 'Waiting…';
    }

    return _Centered(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.brush_outlined, size: 48),
          const SizedBox(height: 16),
          Text(headline,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text('$done/$total drawings done',
              style: theme.textTheme.bodyLarge),
          const SizedBox(height: 24),
          const CircularProgressIndicator(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Rating
// ---------------------------------------------------------------------------

/// Rate every OTHER player's drawing 1–10. You can never rate your own. When
/// everyone has rated everyone the session rolls into the results screen.
class _RatingView extends StatefulWidget {
  final TelephoneSession session;
  final String playerId;
  const _RatingView({required this.session, required this.playerId});

  @override
  State<_RatingView> createState() => _RatingViewState();
}

class _RatingViewState extends State<_RatingView> {
  // targetUid -> chosen 1..10 score for this rater.
  final Map<String, int> _scores = {};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = widget.session;
    final me = widget.playerId;

    // Once you've rated everyone, wait for the rest of the group.
    if (!session.hasPlayer(me) || session.raterHasFinished(me)) {
      final waiting = session.players
          .where((p) => !session.raterHasFinished(p.uid))
          .map((p) => p.displayName)
          .toList();
      return _Centered(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.how_to_vote_outlined, size: 48),
            const SizedBox(height: 16),
            Text('Ratings submitted! 🎉',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (waiting.isNotEmpty)
              Text('Waiting on: ${waiting.join(', ')}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium),
            const SizedBox(height: 24),
            const CircularProgressIndicator(),
          ],
        ),
      );
    }

    final others = session.players.where((p) => p.uid != me).toList();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Rate the drawings!',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('Prompt: ${session.prompt}',
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontStyle: FontStyle.italic)),
        const SizedBox(height: 4),
        Text('Give each drawing a score from 1 to 10. You can\'t rate your own.',
            style: theme.textTheme.bodySmall),
        const SizedBox(height: 16),
        ...others.map((p) {
          final drawing = session.drawingForUid(p.uid);
          final score = _scores[p.uid] ?? 5;
          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.displayName,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  DrawingView(json: drawing?.content ?? '', size: 200),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: score.toDouble(),
                          min: 1,
                          max: 10,
                          divisions: 9,
                          label: '$score',
                          onChanged: (v) =>
                              setState(() => _scores[p.uid] = v.round()),
                        ),
                      ),
                      SizedBox(
                        width: 40,
                        child: Text('$score/10',
                            textAlign: TextAlign.end,
                            style: theme.textTheme.titleMedium),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () => _submitAll(others),
          icon: const Icon(Icons.check),
          label: const Text('Submit ratings'),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  void _submitAll(List<TelephonePlayer> others) {
    final bloc = context.read<TelephoneBloc>();
    // Default any sliders left untouched to 5, then fire one rating per target.
    for (final p in others) {
      bloc.add(TelephoneRatingSubmitted(
        sessionId: widget.session.id,
        raterUid: widget.playerId,
        targetUid: p.uid,
        value: _scores[p.uid] ?? 5,
      ));
    }
  }
}

// ---------------------------------------------------------------------------
// Results
// ---------------------------------------------------------------------------

/// Winner + this-round leaderboard + the running tally across "Play again"
/// rounds, every drawing with its score, and the one-tap replay.
class _ResultsView extends StatelessWidget {
  final TelephoneSession session;
  final String playerId;
  const _ResultsView({required this.session, required this.playerId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roundScores = session.roundScores;
    final winners = session.winnerUids;
    final winnerNames = winners
        .map((uid) => session.players
            .firstWhere((p) => p.uid == uid,
                orElse: () =>
                    const TelephonePlayer(uid: '', displayName: 'Someone'))
            .displayName)
        .toList();

    final String bannerText;
    if (winnerNames.isEmpty) {
      bannerText = 'No ratings — it\'s a draw!';
    } else if (winnerNames.length == 1) {
      bannerText = '🏆 ${winnerNames.first} wins this round!';
    } else {
      bannerText = '🏆 Tie: ${winnerNames.join(' & ')}!';
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Text('Round ${session.roundNumber}',
                  style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer)),
              const SizedBox(height: 6),
              Text(bannerText,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onPrimaryContainer,
                  )),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text('This round', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        ...session.roundLeaderboard.asMap().entries.map((e) {
          final rank = e.key + 1;
          final p = e.value;
          final isWinner = winners.contains(p.uid);
          return ListTile(
            dense: true,
            leading: CircleAvatar(
              backgroundColor: isWinner ? theme.colorScheme.primary : null,
              child: Text('$rank'),
            ),
            title: Text(p.displayName +
                (p.uid == playerId ? ' (you)' : '')),
            trailing: Text('${roundScores[p.uid] ?? 0} pts',
                style: theme.textTheme.titleMedium),
          );
        }),
        const Divider(height: 32),
        Text('Overall — running tally', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        ...session.overallLeaderboard.map((p) {
          final wins = session.roundsWon[p.uid] ?? 0;
          return ListTile(
            dense: true,
            leading: const Icon(Icons.emoji_events_outlined),
            title: Text(p.displayName +
                (p.uid == playerId ? ' (you)' : '')),
            subtitle: wins > 0
                ? Text('$wins ${wins == 1 ? 'round' : 'rounds'} won')
                : null,
            trailing: Text('${session.tallyPoints[p.uid] ?? 0} pts',
                style: theme.textTheme.titleMedium),
          );
        }),
        const Divider(height: 32),
        Text('The drawings — "${session.prompt}"',
            style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        ...session.players.map((p) {
          final drawing = session.drawingForUid(p.uid);
          if (drawing == null) return const SizedBox.shrink();
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(p.displayName,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      Text('${roundScores[p.uid] ?? 0} pts',
                          style: theme.textTheme.titleSmall),
                    ],
                  ),
                  const SizedBox(height: 8),
                  DrawingView(json: drawing.content, size: 200),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 16),
        _PlayAgainButton(session: session),
        const SizedBox(height: 24),
      ],
    );
  }
}
