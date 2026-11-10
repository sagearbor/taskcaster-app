import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/features/arena/domain/models/feed_post.dart';
import 'package:taskcaster_app/features/games/domain/house_reactions.dart';
import 'package:taskcaster_app/features/tasks/data/datasources/starter_pack_data.dart';

void main() {
  group('HouseReactions', () {
    test('every stamp has at least six lines', () {
      for (final stamp in Stamps.values) {
        expect(HouseReactions.byStamp[stamp], isNotNull, reason: stamp);
        expect(HouseReactions.byStamp[stamp]!.length, greaterThanOrEqualTo(6),
            reason: stamp);
      }
    });

    test('every starter task has its own specials', () {
      for (final task in StarterPackData.tasks()) {
        expect(HouseReactions.byTask[task.id], isNotNull, reason: task.id);
        expect(HouseReactions.byTask[task.id]!.length, greaterThanOrEqualTo(3),
            reason: task.id);
      }
    });

    test('no exclamation marks, no blanks, no duplicates, short enough', () {
      final all = [
        ...HouseReactions.byStamp.values.expand((l) => l),
        ...HouseReactions.byTask.values.expand((l) => l),
      ];
      expect(all.length, greaterThanOrEqualTo(40));
      expect(all.toSet().length, all.length, reason: 'duplicate line');
      for (final line in all) {
        expect(line.contains('!'), isFalse, reason: line);
        expect(line.trim(), isNotEmpty);
        expect(line.trim(), line, reason: 'stray whitespace: "$line"');
        expect(line.contains('  '), isFalse, reason: 'double space: "$line"');
        expect(line.length, lessThanOrEqualTo(110), reason: line);
      }
    });

    test('deterministic: the same post always gets the same line', () {
      for (var i = 0; i < 50; i++) {
        expect(
          HouseReactions.pick(
              postId: 'post-$i', stamp: Stamps.technically, taskId: 'starter-03'),
          HouseReactions.pick(
              postId: 'post-$i', stamp: Stamps.technically, taskId: 'starter-03'),
        );
      }
    });

    test('a non-starter task draws only from the stamp bucket', () {
      for (final stamp in Stamps.values) {
        for (var i = 0; i < 40; i++) {
          final line = HouseReactions.pick(
              postId: 'p$i', stamp: stamp, taskId: 'friend-task');
          expect(HouseReactions.byStamp[stamp], contains(line));
        }
      }
    });

    test('a starter task mixes its specials with the stamp lines', () {
      final specials = HouseReactions.byTask['starter-07']!;
      final stampLines = HouseReactions.byStamp[Stamps.art]!;
      final picks = [
        for (var i = 0; i < 90; i++)
          HouseReactions.pick(
              postId: 'post$i', stamp: Stamps.art, taskId: 'starter-07'),
      ];
      for (final p in picks) {
        expect(specials.contains(p) || stampLines.contains(p), isTrue);
      }
      expect(picks.where(specials.contains), isNotEmpty);
      expect(picks.where(stampLines.contains), isNotEmpty);
      expect(picks.toSet().length, greaterThan(4), reason: 'variety');
    });

    test('an unknown or missing stamp reads as NO REGRETS', () {
      final noRegrets = HouseReactions.byStamp[Stamps.noRegrets]!;
      expect(noRegrets, contains(HouseReactions.pick(postId: 'x', stamp: null)));
      expect(noRegrets,
          contains(HouseReactions.pick(postId: 'y', stamp: 'WHATEVER')));
    });
  });
}
