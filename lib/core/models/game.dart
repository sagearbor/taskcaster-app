import 'package:equatable/equatable.dart';
import 'player.dart';
import 'task.dart';
import 'game_settings.dart';

enum GameStatus { lobby, inProgress, completed }

enum GameMode {
  async, // Players submit when ready (primary use case)
  same_device, // Pass phone around (future)
  live, // All online simultaneously (future)
}

class Game extends Equatable {
  final String id;
  final String gameName;
  final String creatorId;
  final String judgeId;
  final GameStatus status;
  final String inviteCode;
  final DateTime createdAt;
  final List<Player> players;
  final List<Task> tasks;

  // NEW: Async game fields
  final GameMode mode;
  final GameSettings settings;
  final int currentTaskIndex; // Which task is currently active

  /// When true, the game is discoverable in the public gallery and can be
  /// cloned as a template by other users.
  final bool isPublic;

  /// How many times this game has been cloned as a template (drives the
  /// "most popular" sort in the public gallery).
  final int cloneCount;

  /// Lowercased email addresses the creator has specifically invited to this
  /// game. Lets players see "invites for you" and join without typing the
  /// invite code. Backward-compatible: defaults to an empty list.
  final List<String> invitedEmails;

  /// Discriminates special game variants that reuse the ordinary games
  /// collection (e.g. 'house_hunt'). Null means an ordinary game.
  /// Backward-compatible: older docs without this key parse as null.
  final String? gameKind;

  const Game({
    required this.id,
    required this.gameName,
    required this.creatorId,
    required this.judgeId,
    required this.status,
    required this.inviteCode,
    required this.createdAt,
    required this.players,
    required this.tasks,
    this.mode = GameMode.async,
    required this.settings,
    this.currentTaskIndex = 0,
    this.isPublic = false,
    this.cloneCount = 0,
    this.invitedEmails = const [],
    this.gameKind,
  });

  factory Game.fromMap(Map<String, dynamic> map) {
    return Game(
      id: map['id'] as String,
      gameName: map['gameName'] as String,
      creatorId: map['creatorId'] as String,
      judgeId: map['judgeId'] as String,
      status: GameStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => GameStatus.lobby,
      ),
      inviteCode: map['inviteCode'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
      players: (map['players'] as List<dynamic>?)
          ?.map((e) => Player.fromMap(e as Map<String, dynamic>))
          .toList() ?? [],
      tasks: (map['tasks'] as List<dynamic>?)
          ?.map((e) => Task.fromMap(e as Map<String, dynamic>))
          .toList() ?? [],
      mode: GameMode.values.firstWhere(
        (e) => e.name == map['mode'],
        orElse: () => GameMode.async,
      ),
      settings: map['settings'] != null
          ? GameSettings.fromMap(map['settings'] as Map<String, dynamic>)
          : GameSettings.quickPlay(),
      currentTaskIndex: map['currentTaskIndex'] as int? ?? 0,
      isPublic: map['isPublic'] as bool? ?? false,
      cloneCount: map['cloneCount'] as int? ?? 0,
      // Backward-compatible: older docs have no invitedEmails. Normalize to
      // lowercase so lookups (which lowercase the query email) always match.
      invitedEmails: (map['invitedEmails'] as List<dynamic>?)
              ?.map((e) => (e as String).toLowerCase())
              .toList() ??
          const [],
      // Backward-compatible: older docs have no gameKind key, so absence
      // parses as null (an ordinary game).
      gameKind: map['gameKind'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'gameName': gameName,
      'creatorId': creatorId,
      'judgeId': judgeId,
      'status': status.name,
      'inviteCode': inviteCode,
      'createdAt': createdAt.toIso8601String(),
      'players': players.map((e) => e.toMap()).toList(),
      // Flat list of participant uids, kept in step with players[] so security
      // rules can check membership cheaply. Derived from players via the getter.
      'playerIds': playerIds,
      'tasks': tasks.map((e) => e.toMap()).toList(),
      'mode': mode.name,
      'settings': settings.toMap(),
      'currentTaskIndex': currentTaskIndex,
      'isPublic': isPublic,
      'cloneCount': cloneCount,
      'invitedEmails': invitedEmails,
      'gameKind': gameKind,
    };
  }

  Game copyWith({
    String? id,
    String? gameName,
    String? creatorId,
    String? judgeId,
    GameStatus? status,
    String? inviteCode,
    DateTime? createdAt,
    List<Player>? players,
    List<Task>? tasks,
    GameMode? mode,
    GameSettings? settings,
    int? currentTaskIndex,
    bool? isPublic,
    int? cloneCount,
    List<String>? invitedEmails,
    String? gameKind,
  }) {
    return Game(
      id: id ?? this.id,
      gameName: gameName ?? this.gameName,
      creatorId: creatorId ?? this.creatorId,
      judgeId: judgeId ?? this.judgeId,
      status: status ?? this.status,
      inviteCode: inviteCode ?? this.inviteCode,
      createdAt: createdAt ?? this.createdAt,
      players: players ?? this.players,
      tasks: tasks ?? this.tasks,
      mode: mode ?? this.mode,
      settings: settings ?? this.settings,
      currentTaskIndex: currentTaskIndex ?? this.currentTaskIndex,
      isPublic: isPublic ?? this.isPublic,
      cloneCount: cloneCount ?? this.cloneCount,
      invitedEmails: invitedEmails ?? this.invitedEmails,
      gameKind: gameKind ?? this.gameKind,
    );
  }

  /// The user ids of every player on the roster. Persisted (see [toMap]) so
  /// Firestore security rules can gate game updates to actual participants
  /// without reading the nested players[] objects. Always derived from
  /// [players] so it can never drift out of sync in memory; [fromMap] backfills
  /// it for older documents written before this field existed.
  List<String> get playerIds => players.map((p) => p.userId).toList();

  bool get isInLobby => status == GameStatus.lobby;
  bool get isInProgress => status == GameStatus.inProgress;
  bool get isCompleted => status == GameStatus.completed;

  Player? getPlayerById(String userId) {
    try {
      return players.firstWhere((player) => player.userId == userId);
    } catch (e) {
      return null;
    }
  }

  bool isUserInGame(String userId) {
    return players.any((player) => player.userId == userId);
  }

  bool isUserCreator(String userId) {
    return creatorId == userId;
  }

  bool isUserJudge(String userId) {
    return judgeId == userId;
  }

  // NEW: Async game computed properties
  Task? get currentTask {
    if (currentTaskIndex >= 0 && currentTaskIndex < tasks.length) {
      return tasks[currentTaskIndex];
    }
    return null;
  }

  bool get hasMoreTasks => currentTaskIndex < tasks.length - 1;

  bool get allTasksCompleted =>
      tasks.isNotEmpty && tasks.every((task) => task.isCompleted);

  int get completedTasksCount =>
      tasks.where((task) => task.isCompleted).length;

  double get progressPercentage {
    if (tasks.isEmpty) return 0.0;
    return (completedTasksCount / tasks.length) * 100;
  }

  // Check if game can be started
  bool get canStart {
    return isInLobby && players.length >= 2 && tasks.isNotEmpty;
  }

  // Check if game is ready for next task
  bool get canAdvanceToNextTask {
    return currentTask != null &&
           currentTask!.isCompleted &&
           hasMoreTasks;
  }

  @override
  List<Object?> get props => [
        id,
        gameName,
        creatorId,
        judgeId,
        status,
        inviteCode,
        createdAt,
        players,
        tasks,
        mode,
        settings,
        currentTaskIndex,
        isPublic,
        cloneCount,
        invitedEmails,
        gameKind,
      ];
}