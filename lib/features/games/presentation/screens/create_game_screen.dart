import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/models/game_settings.dart';
import '../../../../core/models/task.dart';
import '../../../../core/utils/friendly_errors.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../tasks/presentation/screens/task_browser_screen.dart';
import '../../../tasks/data/datasources/prebuilt_tasks_data.dart';
import '../../domain/repositories/game_repository.dart';
import 'game_detail_screen.dart';

/// Create a friend game in one tap: a fun name is already filled in (edit it
/// inline or re-roll it), five random tasks are already picked (switch to ten
/// with a chip, re-roll, or pick them yourself), and the one button creates
/// the game and opens the invite sheet.
class CreateGameScreen extends StatefulWidget {
  const CreateGameScreen({super.key});

  @override
  State<CreateGameScreen> createState() => _CreateGameScreenState();
}

class _CreateGameScreenState extends State<CreateGameScreen> {
  final _formKey = GlobalKey<FormState>();
  final _gameNameController = TextEditingController();
  bool _isLoading = false;
  List<Task> _selectedTasks = [];

  /// 5 or 10 when the tasks came from a chip; null after a hand-picked set.
  int? _quickCount = 5;

  /// "Taskmaster mode": the creator judges every entry. Off by default, so a
  /// friend game is graded by everyone (WP-13).
  bool _taskmasterMode = false;

  static const _nameAdjectives = [
    'Epic', 'Wild', 'Chaotic', 'Legendary', 'Silly',
    'Mighty', 'Cosmic', 'Sneaky', 'Glorious', 'Absurd',
  ];
  static const _nameNouns = [
    'Showdown', 'Challenge', 'Party', 'Games', 'Tournament',
    'Mayhem', 'Quest', 'Bash', 'Face-Off', 'Spectacular',
  ];

  @override
  void initState() {
    super.initState();
    _gameNameController.text = _suggestGameName();
    _selectedTasks = _randomTasks(5);
  }

  String _suggestGameName() {
    final now = DateTime.now();
    final adjective = _nameAdjectives[now.microsecond % _nameAdjectives.length];
    final noun = _nameNouns[now.millisecond % _nameNouns.length];
    return '$adjective $noun';
  }

  @override
  void dispose() {
    _gameNameController.dispose();
    super.dispose();
  }

  String? _validateGameName(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Give your game a name';
    if (v.length < 3) return 'At least 3 characters';
    if (v.length > 50) return 'Keep it under 50 characters';
    return null;
  }

  List<Task> _randomTasks(int count) =>
      (List<Task>.from(PrebuiltTasksData.getAllTasks())..shuffle())
          .take(count)
          .toList();

  void _pickCount(int count) {
    setState(() {
      _quickCount = count;
      _selectedTasks = _randomTasks(count);
    });
  }

  Future<void> _pickTasksYourself() async {
    final selected = await Navigator.of(context).push<List<Task>>(
      MaterialPageRoute(
        builder: (context) => TaskBrowserScreen(
          initiallySelectedTasks: _selectedTasks,
          maxTasks: 10,
        ),
      ),
    );
    if (selected != null && selected.isNotEmpty && mounted) {
      setState(() {
        _selectedTasks = selected;
        _quickCount = null;
      });
    }
  }

  Future<void> _createGame() async {
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    try {
      if (!_formKey.currentState!.validate()) return;
      if (_selectedTasks.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Pick at least one task')),
        );
        return;
      }

      final authState = context.read<AuthBloc>().state;
      if (authState is! AuthAuthenticated) {
        messenger.showSnackBar(
          SnackBar(
            content: const Text('You must be signed in to create a game'),
            backgroundColor: errorColor,
          ),
        );
        return;
      }

      setState(() => _isLoading = true);

      final gameRepository = sl<GameRepository>();
      final gameId = await gameRepository.createGame(
        _gameNameController.text.trim(),
        authState.user.id,
        // Taskmaster mode: the creator is the judge. Otherwise nobody is.
        authState.user.id,
        judgingMode:
            _taskmasterMode ? JudgingMode.judge : JudgingMode.group,
      );
      await gameRepository.addTasksToGame(gameId, _selectedTasks);

      if (mounted) {
        // Land the creator straight in their new game's lobby (replacing this
        // screen so "back" returns home) with the invite sheet already open —
        // the moment of peak invite intent.
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => GameDetailScreen(
              gameId: gameId,
              promptShareOnLoad: true,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Create game failed: $e');
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(FriendlyErrors.action(
              e,
              fallback: 'Could not create the game. Please try again.',
            )),
            backgroundColor: errorColor,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('New game')),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                children: [
                  _Label('NAME YOUR GAME'),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: const Key('create-game-name'),
                    controller: _gameNameController,
                    enabled: !_isLoading,
                    maxLength: 50,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.done,
                    validator: _validateGameName,
                    style: theme.textTheme.headlineSmall,
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: 'Name your game',
                      suffixIcon: IconButton(
                        tooltip: 'New name',
                        icon: const Icon(Icons.casino_outlined),
                        color: scheme.primary,
                        onPressed: _isLoading
                            ? null
                            : () => setState(() => _gameNameController.text =
                                _suggestGameName()),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  _Label('HOW MANY TASKS?'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    children: [
                      for (final n in const [5, 10])
                        ChoiceChip(
                          key: Key('create-game-count-$n'),
                          label: Text(n == 5 ? 'Quick · 5' : 'Party · 10'),
                          selected: _quickCount == n,
                          onSelected:
                              _isLoading ? null : (_) => _pickCount(n),
                          labelStyle: theme.textTheme.titleSmall?.copyWith(
                            color: _quickCount == n
                                ? scheme.onPrimary
                                : scheme.onSurface,
                          ),
                          selectedColor: scheme.primary,
                          showCheckmark: false,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < _selectedTasks.length; i++)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 26,
                                    child: Text(
                                      '${i + 1}',
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(color: scheme.primary),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      _selectedTasks[i].title,
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 4),
                          Wrap(
                            children: [
                              TextButton.icon(
                                onPressed: _isLoading
                                    ? null
                                    : () => _pickCount(
                                        _quickCount ?? _selectedTasks.length),
                                icon: const Icon(Icons.shuffle, size: 18),
                                label: const Text('Shuffle'),
                              ),
                              TextButton.icon(
                                onPressed:
                                    _isLoading ? null : _pickTasksYourself,
                                icon: const Icon(Icons.tune, size: 18),
                                label: const Text('Pick them myself'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  const _Label('WHO SCORES?'),
                  const SizedBox(height: 4),
                  SwitchListTile(
                    key: const Key('create-game-taskmaster'),
                    contentPadding: EdgeInsets.zero,
                    value: _taskmasterMode,
                    onChanged: _isLoading
                        ? null
                        : (v) => setState(() => _taskmasterMode = v),
                    title: const Text('Judge mode'),
                    subtitle: Text(
                      _taskmasterMode
                          ? 'You judge every entry yourself.'
                          : 'Off: everyone grades everyone else, 1 to 5. '
                              'Nobody has to sit out as judge.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const Key('create-and-invite'),
                    onPressed: _isLoading ? null : _createGame,
                    icon: _isLoading
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.ios_share_rounded),
                    label: const Text('Create and invite'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.labelMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.3,
      ),
    );
  }
}
