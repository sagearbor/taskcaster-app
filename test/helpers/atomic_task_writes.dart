import 'package:mocktail/mocktail.dart';
import 'package:taskcaster_app/core/models/game.dart';
import 'package:taskcaster_app/core/models/task.dart';
import 'package:taskcaster_app/features/games/domain/repositories/game_repository.dart';

/// Makes a mocktail [GameRepository] behave like the real one for
/// `updateTaskAtomically`: the task mutation is applied to the game the mock's
/// own `getGameStream` stub returns (standing in for the fresh read inside
/// the transaction), and the resulting game is handed to [onWrite].
///
/// Lets the task-execution tests keep asserting on "the game that was
/// written" now that the bloc no longer writes whole games.
void stubAtomicTaskWrites(
  GameRepository repo, {
  required void Function(Game written) onWrite,
}) {
  registerFallbackValue((Task t) => t);
  when(() => repo.updateTaskAtomically(any(), any(), any()))
      .thenAnswer((invocation) async {
    final gameId = invocation.positionalArguments[0] as String;
    final taskIndex = invocation.positionalArguments[1] as int;
    final mutate = invocation.positionalArguments[2] as Task Function(Task);
    final game = await repo.getGameStream(gameId).first;
    if (game == null) throw Exception('Game not found');
    final tasks = List<Task>.from(game.tasks);
    tasks[taskIndex] = mutate(tasks[taskIndex]);
    onWrite(game.copyWith(tasks: tasks));
  });
}
