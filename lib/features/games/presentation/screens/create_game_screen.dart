import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/models/task.dart';
import '../../../../core/utils/friendly_errors.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../tasks/presentation/screens/task_browser_screen.dart';
import '../../../tasks/data/datasources/prebuilt_tasks_data.dart';
import '../../domain/repositories/game_repository.dart';
import 'game_detail_screen.dart';

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

  // Smart default: pre-fill a fun game name so the user can create with
  // zero typing (they can still edit it).
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
    if (value == null || value.isEmpty) {
      return 'Game name is required';
    }
    if (value.length < 3) {
      return 'Game name must be at least 3 characters';
    }
    if (value.length > 50) {
      return 'Game name must be less than 50 characters';
    }
    return null;
  }

  Future<void> _selectTasks() async {
    final selectedTasks = await Navigator.of(context).push<List<Task>>(
      MaterialPageRoute(
        builder: (context) => TaskBrowserScreen(
          initiallySelectedTasks: _selectedTasks,
          maxTasks: 10,
        ),
      ),
    );

    if (selectedTasks != null) {
      setState(() {
        _selectedTasks = selectedTasks;
      });
    }
  }

  void _selectRandomTasks(int count) {
    // Pick straight from the prebuilt catalog — no navigation involved.
    final tasks = List<Task>.from(PrebuiltTasksData.getAllTasks())..shuffle();
    setState(() {
      _selectedTasks = tasks.take(count).toList();
    });
  }

  Future<void> _createGame() async {
    try {
      if (!_formKey.currentState!.validate()) {
        return;
      }

      if (_selectedTasks.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select at least one task'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final authState = context.read<AuthBloc>().state;

      if (authState is! AuthAuthenticated) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You must be logged in to create a game'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      setState(() {
        _isLoading = true;
      });

      final gameRepository = sl<GameRepository>();

      final gameId = await gameRepository.createGame(
        _gameNameController.text.trim(),
        authState.user.id,
        authState.user.id, // Creator is always the judge.
      );

      // Add tasks to game
      await gameRepository.addTasksToGame(gameId, _selectedTasks);

      if (mounted) {
        // Land the creator straight in their new game's lobby (replacing this
        // screen so "back" returns home) and immediately offer the invite
        // dialog — the moment of peak invite intent.
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(FriendlyErrors.action(
              e,
              fallback: 'Could not create the game. Please try again.',
            )),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New Game'),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Let\'s Get Started!',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Create a game and invite your friends to join',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              TextFormField(
                controller: _gameNameController,
                decoration: InputDecoration(
                  labelText: 'Game Name',
                  hintText: 'Enter a fun name for your game',
                  helperText: 'At least 3 characters required',
                  prefixIcon: const Icon(Icons.sports_esports),
                  suffixIcon: _gameNameController.text.length >= 3
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : null,
                ),
                validator: _validateGameName,
                enabled: !_isLoading,
                textInputAction: TextInputAction.next,
                maxLength: 50,
                onChanged: (value) => setState(() {}), // Rebuild to show check icon
              ),
              const SizedBox(height: 24),

              // Task Selection Section
              Text(
                'Select Tasks',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              if (_selectedTasks.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Icon(
                          Icons.playlist_add,
                          size: 48,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No tasks selected yet',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _isLoading ? null : () => _selectRandomTasks(5),
                                icon: const Icon(Icons.shuffle),
                                label: const Text('Quick (5)'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _isLoading ? null : () => _selectRandomTasks(10),
                                icon: const Icon(Icons.celebration),
                                label: const Text('Party (10)'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _isLoading ? null : _selectTasks,
                                icon: const Icon(Icons.search),
                                label: const Text('Browse Tasks'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                )
              else
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.check_circle,
                              color: Colors.green[700],
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${_selectedTasks.length} task${_selectedTasks.length == 1 ? '' : 's'} selected',
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 100,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _selectedTasks.length,
                            itemBuilder: (context, index) {
                              final task = _selectedTasks[index];
                              return Container(
                                width: 200,
                                margin: const EdgeInsets.only(right: 8),
                                child: Card(
                                  color: Theme.of(context).colorScheme.primaryContainer,
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          task.title,
                                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                                fontWeight: FontWeight.bold,
                                              ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          task.description,
                                          style: Theme.of(context).textTheme.bodySmall,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _isLoading ? null : _selectTasks,
                                icon: const Icon(Icons.edit),
                                label: const Text('Change Tasks'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue[300]),
                        const SizedBox(width: 8),
                        Text(
                          'How it works',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[300],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '1. Create your game and share the invite code\n'
                      '2. Friends join using the code\n'
                      '3. Add tasks and start the game\n'
                      '4. Players submit videos for each task\n'
                      '5. Judge scores submissions and declares winner!',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.blue[300],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _createGame,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Create Game'),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}