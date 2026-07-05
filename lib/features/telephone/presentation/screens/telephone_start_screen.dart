import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/models/telephone_session.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import '../../data/datasources/telephone_session_store.dart';
import '../../data/practice/local_practice_telephone_repository.dart';
import '../../data/datasources/nearby_permissions.dart';
import '../../domain/repositories/telephone_repository.dart';
import 'offline_telephone_screens.dart';
import 'telephone_session_screen.dart';

/// Entry point for Drawing Telephone: pick a name, then create a new game or
/// join one with an invite code. Identity is a fresh per-session id, so the
/// same person can open two browser tabs and play as two distinct players —
/// which is exactly how this gets verified.
class TelephoneStartScreen extends StatefulWidget {
  const TelephoneStartScreen({super.key});

  @override
  State<TelephoneStartScreen> createState() => _TelephoneStartScreenState();
}

/// Which disclosure card is expanded. Only one opens at a time so the screen
/// never regresses into the old nine-button decision wall. The primary "Start
/// game" action is a plain button now; Join and Options are the two cards.
enum _Section { none, join, options }

class _TelephoneStartScreenState extends State<TelephoneStartScreen> {
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  final _uuid = const Uuid();
  bool _busy = false;

  /// The selected game mode for "Start a game" (online or offline) and
  /// "Practice".
  TelephoneGameMode _mode = TelephoneGameMode.classicTelephone;

  _Section _openSection = _Section.none;

  /// A previously-saved active session, if any. Drives the "Rejoin your game"
  /// button so leaving the session screen is never fatal.
  SavedTelephoneSession? _saved;

  TelephoneRepository get _repo => sl<TelephoneRepository>();
  TelephoneSessionStore get _store => sl<TelephoneSessionStore>();

  @override
  void initState() {
    super.initState();
    // Offer to resume a saved session, if one exists.
    _store.load().then((saved) {
      if (mounted) setState(() => _saved = saved);
    });
    // Pre-fill with the signed-in display name when we have one.
    final auth = sl<AuthRepository>();
    auth.getCurrentUser().then((user) {
      if (mounted && user != null && _nameController.text.isEmpty) {
        _nameController.text = user.displayName;
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  String get _name {
    final n = _nameController.text.trim();
    return n.isEmpty ? 'Player' : n;
  }

  /// Firestore rules require an authenticated user. Make sure we have one
  /// (anonymous is fine) before any read/write so real play never silently
  /// fails on permissions.
  Future<void> _ensureSignedIn() async {
    final auth = sl<AuthRepository>();
    if (auth.getCurrentUserId() == null) {
      await auth.signInAnonymously();
    }
  }

  Future<void> _create() async {
    if (_nameController.text.trim().isEmpty) {
      _toast('Enter your name first');
      return;
    }
    setState(() => _busy = true);
    try {
      await _ensureSignedIn();
      final playerId = _uuid.v4();
      final result = await _repo.createSession(
        creatorUid: playerId,
        creatorName: _name,
        gameMode: _mode,
      );
      // Remember this device as the host so re-entering is a resume, not a
      // duplicate join — the core fix for "host lost the Start button".
      await _store.save(SavedTelephoneSession(
        sessionId: result.sessionId,
        playerId: playerId,
        isHost: true,
        sessionCode: result.inviteCode,
        displayName: _name,
      ));
      _open(result.sessionId, playerId, _name);
    } catch (e) {
      _toast('Could not create game. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.length != 6) {
      _toast('Enter the 6-character invite code');
      return;
    }
    if (_nameController.text.trim().isEmpty) {
      _toast('Enter your name first');
      return;
    }
    setState(() => _busy = true);
    try {
      // If we already have an identity for this exact code (we created it, or
      // already joined it), resume as that same player instead of creating a
      // duplicate. This is what stops "join your own game" adding a second you.
      final saved = _saved;
      if (saved != null && saved.sessionCode == code) {
        _open(saved.sessionId, saved.playerId, saved.displayName);
        return;
      }

      await _ensureSignedIn();
      final playerId = _uuid.v4();
      final sessionId = await _repo.joinSession(
        inviteCode: code,
        uid: playerId,
        displayName: _name,
      );
      await _store.save(SavedTelephoneSession(
        sessionId: sessionId,
        playerId: playerId,
        isHost: false,
        sessionCode: code,
        displayName: _name,
      ));
      _open(sessionId, playerId, _name);
    } catch (e) {
      _toast(_friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Resume the saved session as the existing player (host stays host).
  void _rejoin() {
    final saved = _saved;
    if (saved == null) return;
    _open(saved.sessionId, saved.playerId, saved.displayName);
  }

  /// Start a fully-offline solo game: just you plus two auto-playing bots, run
  /// entirely in memory (no Firebase, no invite code, no waiting). Play every
  /// step on the real game screens; the bots fill their turns the moment you
  /// submit, all the way to the reveal.
  Future<void> _practice() async {
    setState(() => _busy = true);
    try {
      final playerId = _uuid.v4();
      final repo = LocalPracticeTelephoneRepository();
      final sessionId = await repo.startPractice(
        humanUid: playerId,
        humanName: _name,
        gameMode: _mode,
      );
      if (!mounted) return;
      // push (not pushReplacement) so "back" returns here; nothing is saved to
      // the resume store, so practice never offers a stale "Rejoin".
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TelephoneSessionScreen(
            sessionId: sessionId,
            playerId: playerId,
            displayName: _name,
            repository: repo,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Offline / no-internet play over Google Nearby Connections (Bluetooth +
  /// Wi-Fi Direct). Android only — no account or invite code needed.
  void _hostOffline() {
    if (_nameController.text.trim().isEmpty) {
      _toast('Enter your name first');
      return;
    }
    if (!NearbyPermissions.isSupportedPlatform) {
      _toast('Offline nearby play is only available on Android.');
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => OfflineHostScreen(displayName: _name, gameMode: _mode),
    ));
  }

  void _joinOffline() {
    if (_nameController.text.trim().isEmpty) {
      _toast('Enter your name first');
      return;
    }
    if (!NearbyPermissions.isSupportedPlatform) {
      _toast('Offline nearby play is only available on Android.');
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => OfflineJoinScreen(displayName: _name),
    ));
  }

  void _open(String sessionId, String playerId, String displayName) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => TelephoneSessionScreen(
          sessionId: sessionId,
          playerId: playerId,
          displayName: displayName,
        ),
      ),
    );
  }

  String _friendly(Object e) {
    final t = e.toString().toLowerCase();
    if (t.contains('not found')) {
      return 'No game with that code. Double-check and try again.';
    }
    if (t.contains('already started')) {
      return 'That game has already started.';
    }
    if (t.contains('full')) return 'That game is full (8 players max).';
    return 'Could not join. Please try again.';
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _toggle(_Section section) {
    setState(() =>
        _openSection = _openSection == section ? _Section.none : section);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nearbySupported = NearbyPermissions.isSupportedPlatform;
    return Scaffold(
      appBar: AppBar(title: const Text('Drawing Telephone')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('🎨 Drawing Telephone',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                'Write a prompt, draw the prompt before you, guess the drawing '
                'before you — then laugh at how it mutated. 2–8 players.',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              // Everyone needs a name whichever door they pick — keep it first.
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Your name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 20),

              // ---- Primary action: start a game ----------------------------
              SizedBox(
                height: 56,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _create,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Start game',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 4),
              Text('You host online — share a 6-letter code and friends join.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 16),

              // ---- Secondary: join with a code -----------------------------
              _SectionCard(
                icon: Icons.group_add,
                title: 'Join with a code',
                subtitle: 'Got a 6-letter code from a friend?',
                expanded: _openSection == _Section.join,
                onTap: _busy ? null : () => _toggle(_Section.join),
                children: [
                  TextField(
                    controller: _codeController,
                    maxLength: 6,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Invite code',
                      hintText: '6-character code',
                      prefixIcon: Icon(Icons.tag),
                    ),
                    style: const TextStyle(
                        letterSpacing: 3, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _busy ? null : _join,
                    icon: const Icon(Icons.login),
                    label: const Text('Join with code'),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ---- Options: everything else, tucked away -------------------
              _SectionCard(
                icon: Icons.more_horiz,
                title: 'Options',
                subtitle: 'Game mode, offline nearby & practice',
                expanded: _openSection == _Section.options,
                onTap: _busy ? null : () => _toggle(_Section.options),
                children: [
                  _ModePicker(
                    mode: _mode,
                    onChanged:
                        _busy ? null : (m) => setState(() => _mode = m),
                  ),
                  if (nearbySupported) ...[
                    const SizedBox(height: 16),
                    FilledButton.tonalIcon(
                      onPressed: _busy ? null : _hostOffline,
                      icon: const Icon(Icons.wifi_tethering),
                      label: const Text('Host offline nearby'),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'No internet needed — Android phones connect directly '
                      'over Bluetooth & Wi-Fi Direct.',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _joinOffline,
                      icon: const Icon(Icons.travel_explore),
                      label: const Text('Find nearby game'),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'No code needed — finds an offline host in the same '
                      'room.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: _busy ? null : _practice,
                    icon: const Icon(Icons.smart_toy_outlined),
                    label:
                        const Text('Practice solo — play vs bots, no internet'),
                  ),
                ],
              ),

              // ---- Resume a saved session ----------------------------------
              if (_saved != null) ...[
                const SizedBox(height: 16),
                Card(
                  color: theme.colorScheme.primaryContainer,
                  child: ListTile(
                    leading: Icon(Icons.history,
                        color: theme.colorScheme.onPrimaryContainer),
                    title: Text(
                      _saved!.isHost
                          ? "You're hosting game ${_saved!.sessionCode}"
                          : "You're in game ${_saved!.sessionCode}",
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    trailing: FilledButton(
                      onPressed: _busy ? null : _rejoin,
                      child: const Text('Rejoin'),
                    ),
                  ),
                ),
              ],
              if (_busy) ...[
                const SizedBox(height: 24),
                const Center(child: CircularProgressIndicator()),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One of the two primary "doors" (Start / Join): a card with an always-visible
/// header row that expands its details on tap — progressive disclosure instead
/// of the old wall of nine simultaneous actions.
class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool expanded;
  final VoidCallback? onTap;
  final List<Widget> children;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.expanded,
    required this.onTap,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            onTap: onTap,
            leading: Icon(icon, color: theme.colorScheme.primary),
            title: Text(title,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            subtitle: Text(subtitle, style: theme.textTheme.bodySmall),
            trailing: Icon(expanded ? Icons.expand_less : Icons.expand_more),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Game-mode chooser for "Create a new game" / "Practice". Drives whether a new
/// session plays the classic telephone chain or one of the "same prompt" modes
/// (which add rating + a winner).
class _ModePicker extends StatelessWidget {
  final TelephoneGameMode mode;
  final ValueChanged<TelephoneGameMode>? onChanged;
  const _ModePicker({required this.mode, required this.onChanged});

  static const _options = [
    (
      TelephoneGameMode.classicTelephone,
      'Telephone',
      Icons.repeat,
      'Write → draw → guess → draw again — telephone! Best with 3+ '
          '(with 2 players it ends after one drawing).',
    ),
    (
      TelephoneGameMode.samePrompt,
      'Same prompt',
      Icons.groups,
      'Everyone draws the same prompt, then rate for a winner.',
    ),
    (
      TelephoneGameMode.samePromptTurns,
      'Turn by turn',
      Icons.swap_horiz,
      'Same prompt, one artist at a time. Then rate for a winner.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected =
        _options.firstWhere((o) => o.$1 == mode, orElse: () => _options.first);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Game mode', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final o in _options)
              ChoiceChip(
                avatar: Icon(o.$3,
                    size: 18,
                    color: o.$1 == mode
                        ? theme.colorScheme.onSecondaryContainer
                        : null),
                label: Text(o.$2),
                selected: o.$1 == mode,
                onSelected:
                    onChanged == null ? null : (_) => onChanged!(o.$1),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(selected.$4, style: theme.textTheme.bodySmall),
      ],
    );
  }
}
