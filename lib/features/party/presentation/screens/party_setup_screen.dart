import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/party_game.dart';
import '../widgets/party_stage.dart';
import 'party_play_screen.dart';

/// Party mode setup: names in (no accounts), pick a pack length, decide on
/// secret missions, go. Same high-contrast stage as the game itself.
class PartySetupScreen extends StatefulWidget {
  const PartySetupScreen({super.key});

  @override
  State<PartySetupScreen> createState() => _PartySetupScreenState();
}

class _PartySetupScreenState extends State<PartySetupScreen> {
  static const _quickNames = ['Me', 'Mum', 'Dad', 'Gran', 'Bestie', 'Neighbour'];
  static const _maxNameLength = 14;

  final List<String> _players = [];
  final _nameController = TextEditingController();
  final _nameFocus = FocusNode();
  int _taskCount = 5;
  bool _missions = true;

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  bool get _full => _players.length >= kPartyMaxPlayers;

  void _add(String raw) {
    var name = raw.trim();
    if (name.isEmpty || _full) return;
    if (name.length > _maxNameLength) {
      name = name.substring(0, _maxNameLength);
    }
    // Two Sams become "Sam" and "Sam 2".
    final base = name;
    var n = 2;
    while (_players.any((p) => p.toLowerCase() == name.toLowerCase())) {
      name = '$base $n';
      n++;
    }
    HapticFeedback.selectionClick();
    setState(() => _players.add(name));
    _nameController.clear();
  }

  void _start() {
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => PartyPlayScreen(
        players: List.of(_players),
        taskCount: _taskCount,
        withMissions: _missions,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final quick = [
      ..._quickNames.where((q) => !_players.contains(q)),
      'Player ${_players.length + 1}',
    ];
    final need = kPartyMinPlayers - _players.length;
    return PartyStage(
      header: 'PARTY MODE',
      onClose: () => Navigator.of(context).maybePop(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Same room.\nOne phone.', style: partyTitle(34)),
          const SizedBox(height: 8),
          Text(
            'The phone hosts, reads the tasks and runs the clock. You lot '
            'do the rest and judge each other harshly.',
            style: partyBody(16, PartyColors.muted),
          ),
          const SizedBox(height: 22),
          _label('WHO IS PLAYING  ${_players.length}/$kPartyMaxPlayers'),
          const SizedBox(height: 10),
          if (_players.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in _players)
                  InputChip(
                    key: ValueKey('player-chip-$p'),
                    label: Text(p),
                    labelStyle: partyBody(17, PartyColors.onGold),
                    color: const WidgetStatePropertyAll(PartyColors.gold),
                    backgroundColor: PartyColors.gold,
                    deleteIconColor: PartyColors.onGold,
                    side: BorderSide.none,
                    onDeleted: () => setState(() => _players.remove(p)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          if (!_full) ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('party-name-field'),
                    controller: _nameController,
                    focusNode: _nameFocus,
                    maxLength: _maxNameLength,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.done,
                    style: partyBody(18),
                    cursorColor: PartyColors.gold,
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: 'Type a name',
                      hintStyle: partyBody(18, PartyColors.muted),
                      filled: true,
                      fillColor: PartyColors.card,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (v) {
                      _add(v);
                      _nameFocus.requestFocus();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'Add player',
                  style: IconButton.styleFrom(
                    backgroundColor: PartyColors.gold,
                    foregroundColor: PartyColors.onGold,
                    minimumSize: const Size(52, 52),
                  ),
                  onPressed: () => _add(_nameController.text),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final q in quick)
                  _QuickChip(label: '+ $q', onTap: () => _add(q)),
              ],
            ),
          ],
          const SizedBox(height: 24),
          _label('HOW LONG'),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < kPartyPackLengths.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: _lengthCard(kPartyPackLengths[i])),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Material(
            color: PartyColors.card,
            borderRadius: BorderRadius.circular(16),
            child: SwitchListTile(
              key: const ValueKey('party-missions-switch'),
              value: _missions,
              onChanged: (v) => setState(() => _missions = v),
              activeColor: PartyColors.gold,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: Text('Secret missions', style: partyBody(18)),
              subtitle: Text(
                'Everyone gets a hidden side quest. Revealed at the end.',
                style: partyBody(14, PartyColors.muted),
              ),
            ),
          ),
        ],
      ),
      actions: [
        PartyButton(
          label: need > 0
              ? 'Add $need more player${need == 1 ? '' : 's'}'
              : 'Start the party',
          onPressed: need > 0 ? null : _start,
        ),
      ],
    );
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
          fontFamily: 'Fredoka',
          color: PartyColors.gold,
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.6,
        ),
      );

  Widget _lengthCard(PartyPackLength l) {
    final selected = l.tasks == _taskCount;
    return Material(
      color: selected ? PartyColors.gold : PartyColors.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: ValueKey('pack-${l.tasks}'),
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _taskCount = l.tasks),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          child: Column(
            children: [
              Text('${l.tasks}',
                  style: partyTitle(30).copyWith(
                      color: selected ? PartyColors.onGold : null)),
              Text('tasks',
                  style: partyBody(
                      13, selected ? PartyColors.onGold : PartyColors.muted)),
              const SizedBox(height: 2),
              FittedBox(
                child: Text(l.minutes,
                    style: partyBody(
                        14, selected ? PartyColors.onGold : PartyColors.gold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A tappable "+ Name" pill. (Material's ActionChip picks up the app's
/// light chip theme and turns white-on-white on the stage.)
class _QuickChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _QuickChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PartyColors.card,
      shape: const StadiumBorder(
          side: BorderSide(color: PartyColors.cardBorder, width: 1.5)),
      child: InkWell(
        key: ValueKey('quick-$label'),
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Text(label, style: partyBody(15)),
        ),
      ),
    );
  }
}
