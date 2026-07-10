import 'dart:math';

import 'package:flutter/material.dart';

import '../../../../core/di/service_locator.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import '../../../friends/domain/models/friend.dart';
import '../../../friends/domain/repositories/friends_repository.dart';
import '../../../friends/domain/repositories/invites_repository.dart';
import '../../../games/domain/repositories/game_repository.dart';
import '../../../games/presentation/screens/game_detail_screen.dart';
import '../../data/house_hunt_prompts.dart';
import '../../domain/house_hunt_service.dart';

/// Author a House Hunt for a faraway friend: auto-deal five prompts (reshuffle
/// or swap any one, or write your own), pick who to send it to, then fire it
/// off as a one-tap invite. One calm screen, sensible defaults, one primary
/// button — the hider is the judge and the seeker hunts their own home.
class HouseHuntStartScreen extends StatefulWidget {
  const HouseHuntStartScreen({
    super.key,
    this.preselectedFriendUid,
    this.preselectedFriendName,
  });

  /// When set (the "Send one back" role swap), the hunt is pre-targeted at this
  /// person — the original hider you are now hunting back.
  final String? preselectedFriendUid;
  final String? preselectedFriendName;

  @override
  State<HouseHuntStartScreen> createState() => _HouseHuntStartScreenState();
}

class _HouseHuntStartScreenState extends State<HouseHuntStartScreen> {
  final _rng = Random();
  final _emailController = TextEditingController();

  /// The five slots. [_texts] holds what is displayed/sent; [_ids] holds the
  /// deck id for each slot, or null once a slot is a custom-written prompt (so
  /// swaps avoid repeating deck picks).
  late List<String> _texts;
  late List<String?> _ids;

  Friend? _selectedFriend;
  bool _busy = false;

  HouseHuntService get _service => HouseHuntService(
        authRepository: sl<AuthRepository>(),
        gameRepository: sl<GameRepository>(),
        invitesRepository: sl<InvitesRepository>(),
      );

  @override
  void initState() {
    super.initState();
    _dealFresh();
    if (widget.preselectedFriendUid != null) {
      _selectedFriend = Friend(
        uid: widget.preselectedFriendUid!,
        displayName: widget.preselectedFriendName?.trim().isNotEmpty == true
            ? widget.preselectedFriendName!
            : 'Your friend',
      );
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Set<String> get _currentIds => _ids.whereType<String>().toSet();

  void _dealFresh() {
    final hand = HouseHuntPrompts.deal(random: _rng);
    _texts = hand.map((p) => p.prompt).toList();
    _ids = hand.map<String?>((p) => p.id).toList();
  }

  void _reshuffle() => setState(_dealFresh);

  void _swap(int index) {
    final next = HouseHuntPrompts.randomExcluding(_currentIds, random: _rng);
    setState(() {
      _texts[index] = next.prompt;
      _ids[index] = next.id;
    });
  }

  Future<void> _editCustom(int index) async {
    final controller = TextEditingController(text: _texts[index]);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Write your own prompt'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 120,
          maxLines: 3,
          minLines: 1,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'e.g. Find something that reminds you of me',
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      setState(() {
        _texts[index] = result;
        _ids[index] = null; // now a custom prompt
      });
    }
  }

  void _selectFriend(Friend friend) {
    setState(() {
      if (_selectedFriend?.uid == friend.uid) {
        _selectedFriend = null; // tap again to deselect
      } else {
        _selectedFriend = friend;
        _emailController.clear();
      }
    });
  }

  Future<void> _ensureSignedIn() async {
    final auth = sl<AuthRepository>();
    if (auth.getCurrentUserId() == null) {
      await auth.signInAnonymously();
    }
  }

  Future<void> _send() async {
    setState(() => _busy = true);
    try {
      await _ensureSignedIn();

      final email = _emailController.text.trim();
      final friend = _selectedFriend;
      // Pure share-link path: nobody picked, so the hider will share the code
      // from the lobby (we auto-open that share sheet).
      final shareOnly = friend == null && email.isEmpty;

      final result = await _service.createAndSendHunt(
        prompts: _texts,
        friend: friend,
        email: friend == null && email.isNotEmpty ? email : null,
      );

      if (!mounted) return;
      if (friend != null) {
        _toast('Hunt sent to ${friend.displayName} 🏠');
      } else if (email.isNotEmpty) {
        _toast('Hunt sent to $email 🏠');
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => GameDetailScreen(
            gameId: result.gameId,
            // Share-link fallback: open the invite/share sheet on arrival.
            promptShareOnLoad: shareOnly,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _toast('Could not send the hunt. Please try again.');
      }
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('House Hunt')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('🏠 House Hunt',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                'Send five treasure-hunt prompts to a faraway friend — they dash '
                'around their own home, snap proof, and you judge the finds.',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // ---- The five prompts --------------------------------------
              Row(
                children: [
                  Text('Your ${HouseHuntPrompts.huntSize} prompts',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _busy ? null : _reshuffle,
                    icon: const Icon(Icons.casino),
                    label: const Text('Reshuffle'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              for (var i = 0; i < _texts.length; i++)
                _PromptCard(
                  index: i,
                  text: _texts[i],
                  isCustom: _ids[i] == null,
                  onSwap: () => _swap(i),
                  onEdit: () => _editCustom(i),
                ),

              const SizedBox(height: 24),

              // ---- Who to send it to -------------------------------------
              Text('Send it to',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _FriendPicker(
                selected: _selectedFriend,
                preselectedUid: widget.preselectedFriendUid,
                preselectedName: widget.preselectedFriendName,
                onSelect: _selectFriend,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                enabled: _selectedFriend == null,
                decoration: const InputDecoration(
                  labelText: 'Or invite by email',
                  hintText: 'friend@example.com',
                  prefixIcon: Icon(Icons.mail_outline),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'No friend or email? Send it anyway and share the code from the '
                'lobby.',
                style: theme.textTheme.bodySmall,
              ),

              const SizedBox(height: 24),
              SizedBox(
                height: 56,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _send,
                  icon: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                  label: const Text('Send the hunt 🏠',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One editable prompt row: the text plus swap-one and write-your-own actions.
class _PromptCard extends StatelessWidget {
  const _PromptCard({
    required this.index,
    required this.text,
    required this.isCustom,
    required this.onSwap,
    required this.onEdit,
  });

  final int index;
  final String text;
  final bool isCustom;
  final VoidCallback onSwap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: theme.colorScheme.primary.withOpacity(0.15),
              child: Text('${index + 1}',
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  )),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(text, style: theme.textTheme.bodyMedium),
                  if (isCustom)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('Your own',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          )),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Different prompt',
              icon: const Icon(Icons.refresh),
              onPressed: onSwap,
            ),
            IconButton(
              tooltip: 'Write your own',
              icon: const Icon(Icons.edit_outlined),
              onPressed: onEdit,
            ),
          ],
        ),
      ),
    );
  }
}

/// Friend chips fed by the real friend graph, plus any role-swap pre-target
/// (which may not be in the graph yet). Single-select.
class _FriendPicker extends StatelessWidget {
  const _FriendPicker({
    required this.selected,
    required this.preselectedUid,
    required this.preselectedName,
    required this.onSelect,
  });

  final Friend? selected;
  final String? preselectedUid;
  final String? preselectedName;
  final ValueChanged<Friend> onSelect;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Friend>>(
      stream: sl<FriendsRepository>().watchFriends(),
      builder: (context, snapshot) {
        final friends = List<Friend>.from(snapshot.data ?? const <Friend>[]);
        // Ensure a role-swap pre-target always appears, even before it lands in
        // the friend graph.
        if (preselectedUid != null &&
            !friends.any((f) => f.uid == preselectedUid)) {
          friends.insert(
            0,
            Friend(
              uid: preselectedUid!,
              displayName: preselectedName?.trim().isNotEmpty == true
                  ? preselectedName!
                  : 'Your friend',
            ),
          );
        }

        if (friends.isEmpty) {
          return Text(
            'No friends here yet — invite by email below, or send it and share '
            'the code.',
            style: Theme.of(context).textTheme.bodySmall,
          );
        }

        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: friends.map((friend) {
            final isSelected = selected?.uid == friend.uid;
            return ChoiceChip(
              avatar: Text(friend.avatarEmoji ?? '🙂'),
              label: Text(friend.displayName),
              selected: isSelected,
              onSelected: (_) => onSelect(friend),
            );
          }).toList(),
        );
      },
    );
  }
}
