import 'dart:math';
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
import '../../domain/repositories/game_repository.dart';
import '../../../../core/services/ar/ar_games.dart';

part 'games_event.dart';
part 'games_state.dart';

class GamesBloc extends Bloc<GamesEvent, GamesState> {
  final GameRepository gameRepository;
  final AuthRepository authRepository;

  GamesBloc({
    required this.gameRepository,
    required this.authRepository,
  }) : super(GamesInitial()) {
    on<LoadGames>(_onLoadGames);
    on<CreateGame>(_onCreateGame);
    on<JoinGame>(_onJoinGame);
    on<DeleteGame>(_onDeleteGame);
    on<QuickPlayGame>(_onQuickPlayGame);
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

      // Create game object
      final game = Game(
        id: '', // Firestore will generate
        gameName: gameName,
        creatorId: user.id,
        judgeId: user.id, // Creator is judge in Quick Play
        status: GameStatus.inProgress, // Skip lobby!
        inviteCode: _generateInviteCode(),
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
      );

      // Create in Firestore via updateGame (since createGame doesn't support full Game objects)
      // First create basic game
      final gameId = await gameRepository.createGame(
        gameName,
        user.id,
        user.id,
      );

      // Then update with full game data including tasks
      final completeGame = game.copyWith(id: gameId);
      await gameRepository.updateGame(gameId, completeGame);

      emit(QuickPlaySuccess(gameId: gameId));
    } catch (e) {
      emit(_gamesError('quick play', e, 'Could not start a quick game.'));
    }
  }

  String _generateGameName() {
    final adjectives = ['Epic', 'Awesome', 'Crazy', 'Wild', 'Fun', 'Amazing', 'Super', 'Mega'];
    final nouns = ['Adventure', 'Challenge', 'Quest', 'Game', 'Mission', 'Journey', 'Party'];
    final random = Random();
    final adj = adjectives[random.nextInt(adjectives.length)];
    final noun = nouns[random.nextInt(nouns.length)];
    return '$adj $noun #${random.nextInt(9999).toString().padLeft(4, '0')}';
  }

  String _generateInviteCode() {
    final random = Random();
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List.generate(6, (_) => chars[random.nextInt(chars.length)]).join();
  }

  List<Task> _getRandomTasks({required int count}) {
    final allTasks = PrebuiltTasksData.getAllTasks();
    final random = Random();

    // Shuffle and take first 'count' tasks
    final shuffled = List<Task>.from(allTasks)..shuffle(random);
    return shuffled.take(count).toList();
  }
}