import 'package:flutter/material.dart';
import '../../../../core/models/task.dart';
import '../../../tasks/data/datasources/prebuilt_tasks_data.dart';
import '../widgets/task_card.dart';

class TaskBrowserScreen extends StatefulWidget {
  final List<Task> initiallySelectedTasks;
  final int maxTasks;

  const TaskBrowserScreen({
    super.key,
    this.initiallySelectedTasks = const [],
    this.maxTasks = 10,
  });

  @override
  State<TaskBrowserScreen> createState() => _TaskBrowserScreenState();
}

class _TaskBrowserScreenState extends State<TaskBrowserScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  List<Task> _allTasks = [];
  List<Task> _filteredTasks = [];
  Set<String> _selectedTaskIds = {};
  String _searchQuery = '';

  final List<String> _categories = [
    'All',
    ...PrebuiltTasksData.categories,
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _categories.length, vsync: this);
    _allTasks = PrebuiltTasksData.getAllTasks();
    _filteredTasks = _allTasks;

    // Initialize with already-selected tasks
    _selectedTaskIds = widget.initiallySelectedTasks.map((t) => t.id).toSet();

    _tabController.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    setState(() {
      _filterTasks();
    });
  }

  void _filterTasks() {
    setState(() {
      List<Task> tasks = _allTasks;

      // Filter by category (each prebuilt task carries a category field).
      final selectedCategory = _categories[_tabController.index];
      if (selectedCategory != 'All') {
        tasks =
            tasks.where((task) => task.category == selectedCategory).toList();
      }

      // Filter by search query
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        tasks = tasks.where((task) {
          return task.title.toLowerCase().contains(query) ||
              task.description.toLowerCase().contains(query) ||
              (task.category?.toLowerCase().contains(query) ?? false);
        }).toList();
      }

      _filteredTasks = tasks;
    });
  }

  void _toggleTaskSelection(Task task) {
    setState(() {
      if (_selectedTaskIds.contains(task.id)) {
        _selectedTaskIds.remove(task.id);
      } else {
        if (_selectedTaskIds.length < widget.maxTasks) {
          _selectedTaskIds.add(task.id);
        } else {
          _showMaxTasksSnackBar();
        }
      }
    });
  }

  void _showMaxTasksSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Maximum ${widget.maxTasks} tasks allowed'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _selectRandomTasks(int count) {
    setState(() {
      _selectedTaskIds.clear();

      final shuffled = List<Task>.from(_allTasks)..shuffle();
      final randomTasks = shuffled.take(count).toList();

      _selectedTaskIds = randomTasks.map((t) => t.id).toSet();
    });

    _showSnackBar('Selected $count random tasks');
  }

  void _clearSelection() {
    setState(() {
      _selectedTaskIds.clear();
    });
    _showSnackBar('Selection cleared');
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _showTaskPreview(Task task) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (context, scrollController) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(
              controller: scrollController,
              children: [
                Row(
                  children: [
                    Icon(
                      task.taskType == TaskType.video
                          ? Icons.videocam
                          : Icons.extension,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        task.title,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                if (task.category != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Chip(
                      label: Text(task.category!),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  task.description,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _toggleTaskSelection(task);
                  },
                  icon: Icon(_selectedTaskIds.contains(task.id)
                      ? Icons.check_circle
                      : Icons.add_circle),
                  label: Text(_selectedTaskIds.contains(task.id)
                      ? 'Remove from Game'
                      : 'Add to Game'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _done() {
    final selectedTasks = _allTasks
        .where((task) => _selectedTaskIds.contains(task.id))
        .toList();

    Navigator.of(context).pop(selectedTasks);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Tasks'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: _categories.map((category) {
            return Tab(text: category);
          }).toList(),
        ),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search tasks...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                  _filterTasks();
                                });
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                        _filterTasks();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.filter_list),
                  onSelected: (value) {
                    if (value == 'random_5') {
                      _selectRandomTasks(5);
                    } else if (value == 'random_10') {
                      _selectRandomTasks(10);
                    } else if (value == 'clear') {
                      _clearSelection();
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'random_5',
                      child: Row(
                        children: [
                          Icon(Icons.shuffle),
                          SizedBox(width: 8),
                          Text('Random 5 tasks'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'random_10',
                      child: Row(
                        children: [
                          Icon(Icons.shuffle),
                          SizedBox(width: 8),
                          Text('Random 10 tasks'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'clear',
                      child: Row(
                        children: [
                          Icon(Icons.clear_all),
                          SizedBox(width: 8),
                          Text('Clear selection'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Task grid
          Expanded(
            child: _filteredTasks.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No tasks found',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: MediaQuery.of(context).size.width > 600 ? 3 : 2,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 0.75,
                    ),
                    itemCount: _filteredTasks.length,
                    itemBuilder: (context, index) {
                      final task = _filteredTasks[index];
                      final isSelected = _selectedTaskIds.contains(task.id);

                      return TaskCard(
                        task: task,
                        isSelected: isSelected,
                        onTap: () => _toggleTaskSelection(task),
                        onLongPress: () => _showTaskPreview(task),
                      );
                    },
                  ),
          ),
        ],
      ),

      // Bottom bar with selected count and Done button
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${_selectedTaskIds.length} task${_selectedTaskIds.length == 1 ? '' : 's'} selected',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ElevatedButton.icon(
                onPressed: _selectedTaskIds.isEmpty ? null : _done,
                icon: const Icon(Icons.check),
                label: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}