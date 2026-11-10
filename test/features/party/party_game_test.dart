import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/features/party/domain/party_game.dart';
import 'package:taskcaster_app/features/party/domain/party_tasks.dart';

void main() {
  group('content', () {
    test('at least 25 tasks with unique ids, every kind represented', () {
      expect(kPartyTasks.length, greaterThanOrEqualTo(25));
      expect(kPartyTasks.map((t) => t.id).toSet().length, kPartyTasks.length);
      for (final k in PartyTaskKind.values) {
        expect(kPartyTasks.where((t) => t.kind == k).length,
            greaterThanOrEqualTo(5),
            reason: k.name);
      }
    });

    test('gather tasks carry a twist; others do not', () {
      for (final t in kPartyTasks) {
        if (t.kind == PartyTaskKind.gatherReveal) {
          expect(t.twist, isNotNull, reason: t.id);
          expect(t.twistSeconds, greaterThan(0), reason: t.id);
        } else {
          expect(t.twist, isNull, reason: t.id);
        }
      }
    });

    test('copy has no exclamation marks', () {
      final all = [
        for (final t in kPartyTasks) ...[
          t.title,
          t.prompt,
          t.judging,
          t.twist ?? ''
        ],
        ...kSecretMissions,
      ];
      for (final s in all) {
        expect(s.contains('!'), isFalse, reason: s);
      }
    });

    test('enough distinct missions for a full table', () {
      expect(kSecretMissions.toSet().length,
          greaterThanOrEqualTo(kPartyMaxPlayers));
    });
  });

  group('pack draw', () {
    test('draws the requested count, no repeats, opens head to head', () {
      for (final l in kPartyPackLengths) {
        final g = PartyGame.start(
            players: const ['A', 'B'],
            taskCount: l.tasks,
            random: Random(l.tasks));
        expect(g.tasks.length, l.tasks);
        expect(g.tasks.map((t) => t.id).toSet().length, l.tasks);
        expect(g.tasks.first.kind, PartyTaskKind.headToHead);
      }
    });

    test('a 5-task pack mixes all three kinds', () {
      final g = PartyGame.start(
          players: const ['A', 'B', 'C'], taskCount: 5, random: Random(1));
      expect(g.tasks.map((t) => t.kind).toSet(), PartyTaskKind.values.toSet());
    });

    test('rejects fewer than 2 or more than 8 players', () {
      expect(() => PartyGame.start(players: const ['A'], taskCount: 3),
          throwsArgumentError);
      expect(
          () => PartyGame.start(
              players: List.generate(9, (i) => 'P$i'), taskCount: 3),
          throwsArgumentError);
    });
  });

  group('secret missions', () {
    test('one distinct mission per player when on', () {
      final players = List.generate(8, (i) => 'P$i');
      final g =
          PartyGame.start(players: players, taskCount: 3, random: Random(3));
      expect(g.hasMissions, isTrue);
      expect(g.missions.length, 8);
      expect(g.missions.values.toSet().length, 8);
    });

    test('none when off', () {
      final g = PartyGame.start(
          players: const ['A', 'B'], taskCount: 3, withMissions: false);
      expect(g.hasMissions, isFalse);
      expect(g.missions, isEmpty);
    });
  });

  group('scoring', () {
    test('ranking gives n, n-1 … 1 points', () {
      final g = PartyGame.start(
          players: const ['A', 'B', 'C', 'D'],
          taskCount: 3,
          random: Random(2));
      final r = g.scoreCurrentTask([2, 0, 3, 1]);
      expect(r.points, {2: 4, 0: 3, 3: 2, 1: 1});
      expect(g.currentTaskIndex, 1);
    });

    test('two players: winner 2, loser 1', () {
      final g = PartyGame.start(
          players: const ['A', 'B'], taskCount: 3, random: Random(2));
      g.scoreWinner(1);
      expect(g.totalScore(1), 2);
      expect(g.totalScore(0), 1);
    });

    test('rejects incomplete or duplicate rankings', () {
      final g = PartyGame.start(
          players: const ['A', 'B', 'C'], taskCount: 3, random: Random(2));
      expect(() => g.scoreCurrentTask([0, 1]), throwsArgumentError);
      expect(() => g.scoreCurrentTask([0, 0, 1]), throwsArgumentError);
      expect(() => g.scoreCurrentTask([0, 1, 5]), throwsArgumentError);
    });

    test('cannot score past the last task', () {
      final g = PartyGame.start(
          players: const ['A', 'B'], taskCount: 3, random: Random(2));
      for (var i = 0; i < 3; i++) {
        g.scoreWinner(0);
      }
      expect(g.allTasksScored, isTrue);
      expect(g.currentTask, isNull);
      expect(() => g.scoreWinner(0), throwsStateError);
    });

    test('mission bonus can flip the result', () {
      final g = PartyGame.start(
          players: const ['A', 'B', 'C'], taskCount: 3, random: Random(2));
      g.scoreCurrentTask([0, 1, 2]); // A3 B2 C1
      g.scoreCurrentTask([0, 1, 2]); // A6 B4 C2
      g.scoreCurrentTask([1, 0, 2]); // A8 B7 C3
      expect(g.champions(), [0]);
      g.setMissionOutcome(1, true);
      g.setMissionOutcome(0, false);
      expect(g.totalScore(1), 7 + kSecretMissionBonus);
      expect(g.champions(), [1]);
      expect(g.standings(), [1, 0, 2]);
    });

    test('a tie on top makes co-champions', () {
      final g = PartyGame.start(
          players: const ['A', 'B', 'C'], taskCount: 3, random: Random(2));
      g.scoreCurrentTask([0, 1, 2]);
      g.scoreCurrentTask([1, 0, 2]);
      expect(g.champions(), [0, 1]);
    });
  });
}
