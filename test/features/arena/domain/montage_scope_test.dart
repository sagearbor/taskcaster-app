import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/features/arena/domain/models/montage.dart';

/// The montage document id is a CONTRACT with functions/src/contract.js
/// (`montageDocId`): Starter Pack tasks are scoped across every player's solo
/// game, so two different games looking at the same starter task must read
/// the same document; ordinary game tasks stay scoped to their game.
void main() {
  group('Montage.idFor', () {
    test('starter tasks share one document across games', () {
      expect(Montage.scopeFor('game-a', 'starter-01-v2'), Montage.starterScope);
      expect(Montage.idFor('game-a', 'starter-01-v2'), 'starter_starter-01-v2');
      expect(
        Montage.idFor('game-b', 'starter-01-v2'),
        Montage.idFor('game-a', 'starter-01-v2'),
      );
      expect(Montage.idFor('', 'starter-03'), 'starter_starter-03');
    });

    test('game tasks are scoped to their game', () {
      expect(Montage.scopeFor('game-a', 'task-7'), 'game-a');
      expect(Montage.idFor('game-a', 'task-7'), 'game-a_task-7');
      expect(
        Montage.idFor('game-a', 'task-7'),
        isNot(Montage.idFor('game-b', 'task-7')),
      );
    });
  });
}
