import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/models/telephone_session.dart';
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
        FilledButton(
          onPressed: _send,
          child: const Text('Submit prompt'),
        ),
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
          FilledButton(
            onPressed: _send,
            child: const Text('Submit drawing'),
          ),
        ],
      ),
    );
  }

  void _send() {
    if (_controller.isEmpty) {
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
        DrawingView(json: drawing?.content ?? ''),
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
        FilledButton(
          onPressed: _send,
          child: const Text('Submit guess'),
        ),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final waitingOn = session.players
        .where((p) => !session.hasSubmittedCurrentStep(p.uid))
        .map((p) => p.displayName)
        .toList();
    return _Centered(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.hourglass_top, size: 48),
          const SizedBox(height: 16),
          Text('Submitted! 🎉',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            '${session.submittedUids.length}/${session.playerCount} done',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          if (waitingOn.isNotEmpty)
            Text('Waiting on: ${waitingOn.join(', ')}',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center),
          const SizedBox(height: 24),
          const CircularProgressIndicator(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reveal
// ---------------------------------------------------------------------------

class _RevealView extends StatelessWidget {
  final TelephoneSession session;
  const _RevealView({required this.session});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      // One card per chain, plus a trailing "Play again" footer.
      itemCount: session.chains.length + 1,
      itemBuilder: (context, index) {
        if (index == session.chains.length) {
          return Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 24),
            child: _PlayAgainButton(session: session),
          );
        }
        final chain = session.chains[index];
        if (chain.isEmpty) return const SizedBox.shrink();
        final starter = chain.first.authorName;
        return Card(
          margin: const EdgeInsets.only(bottom: 20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("$starter's chain",
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Divider(),
                ...chain.map((entry) => _RevealEntry(entry: entry)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RevealEntry extends StatelessWidget {
  final TelephoneEntry entry;
  const _RevealEntry({required this.entry});

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
            DrawingView(json: entry.content, size: 220)
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
          FilledButton(
            onPressed: _send,
            child: const Text('Submit drawing'),
          ),
        ],
      ),
    );
  }

  void _send() {
    if (_controller.isEmpty) {
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
