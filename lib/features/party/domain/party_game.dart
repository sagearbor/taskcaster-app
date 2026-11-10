import 'dart:math';

import 'party_tasks.dart';

/// Pack sizes offered on the setup screen, with a rough running time.
class PartyPackLength {
  final int tasks;
  final String label;
  final String minutes;
  const PartyPackLength(this.tasks, this.label, this.minutes);
}

const List<PartyPackLength> kPartyPackLengths = [
  PartyPackLength(3, 'Quick', '≈ 10 min'),
  PartyPackLength(5, 'Classic', '≈ 15 min'),
  PartyPackLength(8, 'Marathon', '≈ 25 min'),
];

const int kPartyMinPlayers = 2;
const int kPartyMaxPlayers = 8;

/// One finished task: who placed where and what they earned.
class PartyTaskResult {
  final PartyTask task;

  /// Player indexes, best first.
  final List<int> ranking;

  /// Points per player index for this task.
  final Map<int, int> points;

  const PartyTaskResult({
    required this.task,
    required this.ranking,
    required this.points,
  });
}

/// Pure, local state of one in-person party: players, the drawn pack, the
/// secret missions and the scores. No Flutter, no Firestore.
///
/// Scoring is Taskmaster-shaped: with n players, 1st gets n points, 2nd
/// n-1 … last gets 1. Two players: winner 2, loser 1. A completed secret
/// mission is worth [kSecretMissionBonus].
class PartyGame {
  final List<String> players;
  final List<PartyTask> tasks;

  /// Secret mission per player index (empty when missions are off).
  final Map<int, String> missions;

  final List<PartyTaskResult> results = [];
  final Map<int, bool> missionOutcomes = {};

  PartyGame._(this.players, this.tasks, this.missions);

  /// Draws a pack of [taskCount] tasks with a good mix of kinds, and (when
  /// [withMissions]) a distinct secret mission per player. [random] makes
  /// the draw deterministic in tests.
  factory PartyGame.start({
    required List<String> players,
    required int taskCount,
    bool withMissions = true,
    Random? random,
    List<PartyTask> library = kPartyTasks,
    List<String> missionLibrary = kSecretMissions,
  }) {
    if (players.length < kPartyMinPlayers ||
        players.length > kPartyMaxPlayers) {
      throw ArgumentError.value(players.length, 'players',
          'needs $kPartyMinPlayers–$kPartyMaxPlayers players');
    }
    final rng = random ?? Random();
    final tasks = drawPack(taskCount, rng, library);
    final missions = <int, String>{};
    if (withMissions) {
      final pool = [...missionLibrary]..shuffle(rng);
      for (var i = 0; i < players.length; i++) {
        missions[i] = pool[i % pool.length];
      }
    }
    return PartyGame._(List.unmodifiable(players), tasks, missions);
  }

  /// Interleaves the kinds so a pack never runs three performances in a
  /// row: head-to-head opens (it warms the room up), a fetch lands early.
  static List<PartyTask> drawPack(
      int count, Random rng, List<PartyTask> library) {
    final byKind = {
      for (final k in PartyTaskKind.values)
        k: (library.where((t) => t.kind == k).toList()..shuffle(rng)),
    };
    const pattern = [
      PartyTaskKind.headToHead,
      PartyTaskKind.gatherReveal,
      PartyTaskKind.performance,
      PartyTaskKind.headToHead,
      PartyTaskKind.performance,
      PartyTaskKind.gatherReveal,
      PartyTaskKind.headToHead,
      PartyTaskKind.performance,
    ];
    final out = <PartyTask>[];
    var i = 0;
    while (out.length < count && out.length < library.length) {
      final want = pattern[i % pattern.length];
      i++;
      final pool = byKind[want]!;
      if (pool.isNotEmpty) {
        out.add(pool.removeAt(0));
      } else if (byKind.values.every((p) => p.isEmpty)) {
        break;
      }
    }
    return out;
  }

  bool get hasMissions => missions.isNotEmpty;

  int get currentTaskIndex => results.length;

  bool get allTasksScored => results.length >= tasks.length;

  PartyTask? get currentTask => allTasksScored ? null : tasks[results.length];

  /// Points for finishing in [place] (0 = first) among all players.
  int pointsForPlace(int place) => players.length - place;

  /// Records the room's verdict for the current task. [ranking] lists player
  /// indexes best first and must name every player exactly once.
  PartyTaskResult scoreCurrentTask(List<int> ranking) {
    final task = currentTask;
    if (task == null) throw StateError('No task left to score');
    if (ranking.length != players.length ||
        ranking.toSet().length != players.length ||
        ranking.any((p) => p < 0 || p >= players.length)) {
      throw ArgumentError.value(ranking, 'ranking', 'must rank every player');
    }
    final points = {
      for (var place = 0; place < ranking.length; place++)
        ranking[place]: pointsForPlace(place),
    };
    final result = PartyTaskResult(
        task: task, ranking: List.unmodifiable(ranking), points: points);
    results.add(result);
    return result;
  }

  /// Two-player shortcut: tapping the winner ranks the other player second.
  PartyTaskResult scoreWinner(int winner) {
    final rest = [
      for (var i = 0; i < players.length; i++)
        if (i != winner) i,
    ];
    return scoreCurrentTask([winner, ...rest]);
  }

  void setMissionOutcome(int player, bool completed) {
    if (!missions.containsKey(player)) return;
    missionOutcomes[player] = completed;
  }

  int taskPoints(int player) =>
      results.fold(0, (sum, r) => sum + (r.points[player] ?? 0));

  int missionPoints(int player) =>
      missionOutcomes[player] == true ? kSecretMissionBonus : 0;

  int totalScore(int player) => taskPoints(player) + missionPoints(player);

  /// Player indexes sorted by total score, best first (ties keep seat
  /// order).
  List<int> standings() {
    final order = List<int>.generate(players.length, (i) => i);
    order.sort((a, b) {
      final d = totalScore(b).compareTo(totalScore(a));
      return d != 0 ? d : a.compareTo(b);
    });
    return order;
  }

  /// Everyone tied on the top score.
  List<int> champions() {
    final s = standings();
    final top = totalScore(s.first);
    return s.where((p) => totalScore(p) == top).toList();
  }
}
