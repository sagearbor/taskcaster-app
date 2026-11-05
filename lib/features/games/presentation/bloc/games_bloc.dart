import 'dart:math';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/models/game.dart';
import '../../../../core/utils/friendly_errors.dart';
import '../../../../core/models/player.dart';
import '../../../../core/models/game_settings.dart';
import '../../../../core/models/task.dart';
import '../../../../core/models/player_task_status.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import '../../../tasks/data/datasources/prebuilt_tasks_data.dart';
import '../../../tasks/data/datasources/starter_pack_data.dart';
import '../../domain/repositories/game_repository.dart';
import '../../../../core/services/ar/ar_games.dart';
import '../../../../core/di/service_locator.dart';
import '../../../arena/domain/repositories/feed_repository.dart';

part 'games_event.dart';
part 'games_state.dart';

class GamesBloc extends Bloc<GamesEvent, GamesState> {
  final GameRepository gameRepository;
  final AuthRepository authRepository;

  /// Optional Arena. Used only to seed the house entries when the Starter Pack
  /// opens, so a brand-new player has something to grade. Nullable (and
  /// resolved from the service locator when omitted) so existing bloc tests
  /// construct unchanged.
  final FeedRepository? feedRepository;

  GamesBloc({
    required this.gameRepository,
    required this.authRepository,
    this.feedRepository,
  }) : super(GamesInitial()) {
    // restartable(): each LoadGames cancels the previous subscription, so the
    // create/join/delete handlers re-adding it never stack listeners.
    on<LoadGames>(_onLoadGames, transformer: restartable());
    on<CreateGame>(_onCreateGame);
    on<JoinGame>(_onJoinGame);
    on<DeleteGame>(_onDeleteGame);
    on<QuickPlayGame>(_onQuickPlayGame);
    on<StartStarterPack>(_onStartStarterPack);
    on<ChallengeFriends>(_onChallengeFriends);
  }

  Future<void> _onLoadGames(LoadGames event, Emitter<GamesState> emit) async {
    emit(GamesLoading());

    // emit.forEach keeps the emitter valid for the life of the stream, instead
    // of .listen() emitting after the handler returns (which throws "emit was
    // called after an event handler completed normally" and leaks the sub).
    await emit.forEach<List<Game>>(
      gameRepository.getGamesStream(),
      onData: (games) => GamesLoaded(games: games),
      onError: (error, _) =>
          _gamesError('load games', error, 'Could not load your games.'),
    );
  }

  /// Log the raw error for diagnostics, then emit copy a player can act on —
  /// never the exception string itself.
  GamesError _gamesError(String operation, Object e, String fallback) {
    debugPrint('GamesBloc $operation failed: $e');
    return GamesError(
      message: FriendlyErrors.action(e, fallback: '$fallback Please try again.'),
    );
  }

  Future<void> _onCreateGame(CreateGame event, Emitter<GamesState> emit) async {
    emit(GamesLoading());
    try {
      await gameRepository.createGame(
        event.gameName,
        event.creatorId,
        event.judgeId,
      );
      add(LoadGames());
    } catch (e) {
      emit(_gamesError('create game', e, 'Could not create the game.'));
    }
  }

  Future<void> _onJoinGame(JoinGame event, Emitter<GamesState> emit) async {
    try {
      await gameRepository.joinGame(
        event.inviteCode,
        event.userId,
        event.displayName,
      );
      add(LoadGames());
    } catch (e) {
      emit(_gamesError(
          'join game', e, 'Could not join the game. Double-check the code.'));
    }
  }

  Future<void> _onDeleteGame(DeleteGame event, Emitter<GamesState> emit) async {
    try {
      await gameRepository.deleteGame(event.gameId);
      add(LoadGames());
    } catch (e) {
      emit(_gamesError('delete game', e, 'Could not delete the game.'));
    }
  }

  Future<void> _onQuickPlayGame(
    QuickPlayGame event,
    Emitter<GamesState> emit,
  ) async {
    emit(GamesLoading());

    try {
      // Get current user
      final user = await authRepository.getCurrentUser();
      if (user == null) {
        throw Exception('Not authenticated');
      }

      // Generate fun game name
      final gameName = _generateGameName();

      // AR quick-play seeds the single requested AR mini-game task; otherwise
      // 5 random video tasks.
      final arTask = ArTaskSeeds.forId(event.arGameId);
      final randomTasks = arTask != null ? [arTask] : _getRandomTasks(count: 5);

      // Initialize player statuses for all tasks
      final initializedTasks = randomTasks.map((task) {
        return task.copyWith(
          playerStatuses: {
            user.id: PlayerTaskStatus(
              playerId: user.id,
              state: TaskPlayerState.not_started,
            ),
          },
          status: TaskStatus.waiting_for_submissions,
        );
      }).toList();

      // Set deadline for first task
      final firstTaskDeadline = DateTime.now().add(const Duration(hours: 24));
      if (initializedTasks.isNotEmpty) {
        initializedTasks[0] = initializedTasks[0].copyWith(deadline: firstTaskDeadline);
      }

      // createGame seeds the doc with a fresh invite code that no other game
      // holds (GameRepositoryImpl retries until it is unique); read it back
      // so the full write below keeps that code rather than minting one.
      final gameId = await gameRepository.createGame(
        gameName,
        user.id,
        user.id,
      );
      final created = await gameRepository.getGameStream(gameId).first;
      if (created == null) {
        throw Exception('Quick Play game vanished right after it was created');
      }

      final game = Game(
        id: gameId,
        gameName: gameName,
        creatorId: user.id,
        judgeId: user.id, // Creator is judge in Quick Play
        status: GameStatus.inProgress, // Skip lobby!
        inviteCode: created.inviteCode,
        players: [
          Player(
            userId: user.id,
            displayName: user.displayName,
            totalScore: 0,
          ),
        ],
        tasks: initializedTasks,
        currentTaskIndex: 0,
        createdAt: DateTime.now(),
        mode: GameMode.async,
        settings: GameSettings.quickPlay(),
        // Friends may still join a Quick Play game mid-way (see
        // GameRepository.joinGame and the games rule).
        gameKind: Game.kindQuick,
      );

      // Then write the full game (tasks, in progress) over the seed doc.
      await gameRepository.updateGame(gameId, game);

      emit(QuickPlaySuccess(gameId: gameId));
    } catch (e) {
      emit(_gamesError('quick play', e, 'Could not start a quick game.'));
    }
  }

  /// Create a friend game from a 5-task pack. Same path as "Create custom
  /// game" (createGame -> addTasksToGame, lobby, creator judges), minus the
  /// form: the point is to get to the invite link in one tap.
  Future<void> _onChallengeFriends(
    ChallengeFriends event,
    Emitter<GamesState> emit,
  ) async {
    emit(GamesLoading());

    try {
      final user = await authRepository.getCurrentUser();
      if (user == null) {
        throw Exception('Not authenticated');
      }

      final name = challengeNameFor(user.displayName);
      final gameId = await gameRepository.createGame(name, user.id, user.id);
      await gameRepository.addTasksToGame(gameId, _getRandomTasks(count: 5));

      emit(ChallengeFriendsReady(gameId: gameId));
    } catch (e) {
      emit(_gamesError(
          'challenge friends', e, 'Could not set up your challenge.'));
    }
  }

  /// Open the user's Starter Pack, creating it the first time.
  ///
  /// Idempotent by design: a user has exactly one `gameKind == 'starter'`
  /// game, so tapping "Start" twice (or coming back a week later) always lands
  /// in the same game, on the first task they haven't submitted.
  Future<void> _onStartStarterPack(
    StartStarterPack event,
    Emitter<GamesState> emit,
  ) async {
    emit(GamesLoading());

    try {
      final user = await authRepository.getCurrentUser();
      if (user == null) {
        throw Exception('Not authenticated');
      }

      Game? starter;
      try {
        final games = await gameRepository.getGamesStream().first;
        for (final g in games) {
          if (g.isStarter && g.creatorId == user.id) {
            starter = g;
            break;
          }
        }
      } catch (e) {
        // A failed lookup must not block a brand-new player: fall through and
        // create one.
        debugPrint('GamesBloc could not look for an existing starter: $e');
      }

      final String gameId;
      int taskIndex;
      final List<String> taskIds;
      if (starter != null) {
        gameId = starter.id;
        taskIndex = _firstUnsubmittedIndex(starter, user.id);
        taskIds = [for (final t in starter.tasks) t.id];
      } else {
        gameId = await gameRepository.createStarterGame(user);
        taskIndex = 0;
        taskIds = [for (final t in StarterPackData.tasks()) t.id];
      }
      // A share link's task (WP-09) wins over "next unsubmitted".
      final wanted = event.taskId;
      if (wanted != null) {
        final i = taskIds.indexOf(wanted);
        if (i >= 0) taskIndex = i;
      }

      // Best-effort: the Arena should never look empty to a first-time player.
      await _ensureHouseEntries();

      emit(StarterPackReady(gameId: gameId, taskIndex: taskIndex));
    } catch (e) {
      emit(_gamesError(
          'start starter pack', e, 'Could not start your first game.'));
    }
  }

  /// The first task [userId] has not submitted or had judged; the LAST task
  /// once they are all done (there is nothing further to open).
  static int _firstUnsubmittedIndex(Game game, String userId) {
    if (game.tasks.isEmpty) return 0;
    for (var i = 0; i < game.tasks.length; i++) {
      final status = game.tasks[i].getPlayerStatus(userId);
      final done = status != null &&
          (status.state == TaskPlayerState.submitted ||
              status.state == TaskPlayerState.judged);
      if (!done) return i;
    }
    return game.tasks.length - 1;
  }

  Future<void> _ensureHouseEntries() async {
    try {
      final repo = feedRepository ??
          (sl.isRegistered<FeedRepository>() ? sl<FeedRepository>() : null);
      await repo?.ensureHouseEntries();
    } catch (e) {
      debugPrint('GamesBloc could not seed house entries: $e');
    }
  }

  /// Default names for a "Challenge friends" game whose creator has no real
  /// name yet (a guest). This is what lands in a friend's invite, so it
  /// should read like a dare, not like "Guest's challenge".
  static const List<String> funChallengeNames = [
    'The Spoon Incident',
    'Operation Sofa Cushion',
    'The Great Kitchen Trials',
    'Nobody Panic',
    'Absolutely Not a Competition',
    'The Living Room Olympics',
    'A Dignity-Optional Evening',
    'The Fridge Remembers',
    'Trust Me, This Is Fine',
    'The Tea Towel Tribunal',
  ];

  /// "Sam's challenge" for a named player; a [funChallengeNames] pick for a
  /// guest (display name empty, or the placeholder "Guest" / "User").
  static String challengeNameFor(String displayName, {Random? random}) {
    final name = displayName.trim();
    final lower = name.toLowerCase();
    final isPlaceholder =
        name.isEmpty || lower == 'user' || lower.startsWith('guest');
    if (!isPlaceholder) return "$name's challenge";
    final r = random ?? Random();
    return funChallengeNames[r.nextInt(funChallengeNames.length)];
  }

  String _generateGameName() {
    final adjectives = ['Epic', 'Awesome', 'Crazy', 'Wild', 'Fun', 'Amazing', 'Super', 'Mega'];
    final nouns = ['Adventure', 'Challenge', 'Quest', 'Game', 'Mission', 'Journey', 'Party'];
    final random = Random();
    final adj = adjectives[random.nextInt(adjectives.length)];
    final noun = nouns[random.nextInt(nouns.length)];
    return '$adj $noun #${random.nextInt(9999).toString().padLeft(4, '0')}';
  }

  List<Task> _getRandomTasks({required int count}) {
    final allTasks = PrebuiltTasksData.getAllTasks();
    final random = Random();

    // Shuffle and take first 'count' tasks
    final shuffled = List<Task>.from(allTasks)..shuffle(random);
    return shuffled.take(count).toList();
  }
}