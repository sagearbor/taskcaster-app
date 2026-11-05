import 'package:equatable/equatable.dart';

import '../../../core/models/game.dart';
import '../../../core/models/player_task_status.dart';
import '../../../core/models/submission.dart';
import '../../../core/models/task.dart';

/// One friend's 1..5 grade of another player's entry (WP-13).
///
/// Stored at `games/{gameId}/peer_grades/{id}` where [id] binds the task, the
/// entry and the grader, so firestore.rules refuses a second grade (it would
/// be an update) and a grade written under someone else's name.
class PeerGrade extends Equatable {
  final String taskId;
  final int taskIndex;
  final String targetUid;
  final String graderUid;
  final int score;

  const PeerGrade({
    required this.taskId,
    required this.taskIndex,
    required this.targetUid,
    required this.graderUid,
    required this.score,
  });

  String get id => PeerGrading.gradeDocId(taskId, targetUid, graderUid);

  /// The fields the client writes (createdAt is added as a server timestamp).
  Map<String, dynamic> toMap() => {
        'taskId': taskId,
        'taskIndex': taskIndex,
        'targetUid': targetUid,
        'graderUid': graderUid,
        'score': score,
      };

  @override
  List<Object?> get props => [taskId, taskIndex, targetUid, graderUid, score];
}

/// One entry whose score just locked.
class PeerLock extends Equatable {
  final String uid;
  final int points;
  final double mean;
  final int gradeCount;

  const PeerLock({
    required this.uid,
    required this.points,
    required this.mean,
    required this.gradeCount,
  });

  @override
  List<Object?> get props => [uid, points, mean, gradeCount];
}

/// What [PeerGrading.settle] decided for one task.
class PeerSettlement {
  final int taskIndex;
  final List<PeerLock> locks;
  final Map<String, List<String>> peerGraders;
  final bool complete;

  const PeerSettlement({
    required this.taskIndex,
    required this.locks,
    required this.peerGraders,
    required this.complete,
  });
}

/// The rules of a group-graded friend game (WP-13), shared by the UI (who can
/// grade what) and the offline mock backend.
///
/// The SERVER is the source of truth for scores: functions/src/peer_grading.js
/// locks entries and writes totals with the Admin SDK. [settle] and [apply]
/// mirror it line for line so the mock data source (mock-first development,
/// widget tests) plays a group game to the end exactly like production.
class PeerGrading {
  const PeerGrading._();

  /// An entry locks this long after the task's first entry at the latest.
  static const Duration lockAfter = Duration(hours: 24);

  static String gradeDocId(String taskId, String targetUid, String graderUid) =>
      '${taskId}__${targetUid}__$graderUid';

  /// `round(mean x 2)` on 0..10 (the Arena's crowd formula); 0 with no grades.
  static int pointsFor(List<int> scores) {
    if (scores.isEmpty) return 0;
    final mean = scores.reduce((a, b) => a + b) / scores.length;
    return (mean * 2).round().clamp(0, 10);
  }

  static bool _posted(PlayerTaskStatus? s) =>
      s != null &&
      (s.state == TaskPlayerState.submitted ||
          s.state == TaskPlayerState.judged);

  /// Whether [uid] has unlocked grading for [task] (by posting their entry).
  static bool canGrade(Task task, String uid) =>
      _posted(task.playerStatuses[uid]);

  /// The entries [uid] still has to grade on [task], in roster order: every
  /// OTHER player's posted, not-yet-locked entry that [uid] has not graded
  /// (per the server's [Task.peerGraders] plus [alsoGraded], the grades this
  /// device just wrote and the server has not echoed yet). Empty until [uid]
  /// has posted their own entry.
  static List<Submission> queue(
    Game game,
    int taskIndex,
    String uid, {
    Set<String> alsoGraded = const {},
  }) {
    if (!game.isGroupJudged) return const [];
    if (taskIndex < 0 || taskIndex >= game.tasks.length) return const [];
    final task = game.tasks[taskIndex];
    if (task.isCompleted || !canGrade(task, uid)) return const [];

    final out = <Submission>[];
    for (final p in game.players) {
      final target = p.userId;
      if (target == uid) continue;
      if (task.playerStatuses[target]?.state != TaskPlayerState.submitted) {
        continue;
      }
      if (task.hasPeerGraded(target, uid) || alsoGraded.contains(target)) {
        continue;
      }
      final entry = task.getSubmissionByUser(target);
      if (entry != null) out.add(entry);
    }
    return out;
  }

  /// Pure: what locks on task [taskId] right now. [locked] is the uids whose
  /// entry for this task is already in the ledger. Null when [game] is not a
  /// group game or has no such task.
  static PeerSettlement? settle({
    required Game game,
    required String taskId,
    required Iterable<PeerGrade> grades,
    required Set<String> locked,
    required DateTime now,
  }) {
    if (!game.isGroupJudged) return null;
    final taskIndex = game.tasks.indexWhere((t) => t.id == taskId);
    if (taskIndex < 0) return null;
    final task = game.tasks[taskIndex];
    final roster = game.playerIds;
    if (roster.isEmpty) return null;
    final inRoster = roster.toSet();

    bool posted(String uid) => _posted(task.playerStatuses[uid]);
    bool skipped(String uid) =>
        task.playerStatuses[uid]?.state == TaskPlayerState.skipped;

    // target -> grader -> score, first grade per pair only.
    final byTarget = <String, Map<String, int>>{};
    for (final g in grades) {
      if (g.taskId != taskId) continue;
      if (!inRoster.contains(g.graderUid) || !inRoster.contains(g.targetUid)) {
        continue;
      }
      if (g.graderUid == g.targetUid || g.score < 1 || g.score > 5) continue;
      byTarget.putIfAbsent(g.targetUid, () => {}).putIfAbsent(
            g.graderUid,
            () => g.score,
          );
    }

    DateTime? openedAt;
    for (final uid in roster) {
      if (!posted(uid)) continue;
      final at = task.playerStatuses[uid]?.submittedAt;
      if (at != null && (openedAt == null || at.isBefore(openedAt))) {
        openedAt = at;
      }
    }
    final expired =
        openedAt != null && now.difference(openedAt) >= lockAfter;

    final done = Set<String>.of(locked);
    final locks = <PeerLock>[];
    for (final uid in roster) {
      if (!posted(uid) || done.contains(uid)) continue;
      final given = byTarget[uid] ?? const <String, int>{};
      final required = roster.where((p) => p != uid && !skipped(p));
      if (!expired && !required.every(given.containsKey)) continue;
      final scores = given.values.toList();
      final mean = scores.isEmpty
          ? 0.0
          : scores.reduce((a, b) => a + b) / scores.length;
      locks.add(PeerLock(
        uid: uid,
        points: pointsFor(scores),
        mean: mean,
        gradeCount: scores.length,
      ));
      done.add(uid);
    }

    final complete = roster.every(
        (uid) => done.contains(uid) || skipped(uid) || (expired && !posted(uid)));

    return PeerSettlement(
      taskIndex: taskIndex,
      locks: locks,
      peerGraders: {
        for (final e in byTarget.entries) e.key: (e.value.keys.toList()..sort()),
      },
      complete: complete,
    );
  }

  /// Pure: [game] after [outcome]. [totals] is every player's sum over the
  /// whole ledger (all tasks, including the locks just made) — the server
  /// recomputes totals from its ledger the same way.
  static Game apply(
    Game game,
    PeerSettlement outcome, {
    required Map<String, int> totals,
    required DateTime now,
  }) {
    final tasks = List<Task>.from(game.tasks);
    var task = tasks[outcome.taskIndex];
    final statuses = Map<String, PlayerTaskStatus>.from(task.playerStatuses);
    final submissions = List<Submission>.from(task.submissions);

    for (final lock in outcome.locks) {
      final prev = statuses[lock.uid] ??
          PlayerTaskStatus(playerId: lock.uid, state: TaskPlayerState.submitted);
      statuses[lock.uid] = prev.copyWith(
        state: TaskPlayerState.judged,
        score: lock.points,
        scoredAt: now,
      );
      final i = submissions.indexWhere((s) => s.userId == lock.uid);
      if (i >= 0) {
        submissions[i] =
            submissions[i].copyWith(score: lock.points, isJudged: true);
      }
    }
    task = task.copyWith(
      playerStatuses: statuses,
      submissions: submissions,
      peerGraders: outcome.peerGraders,
      status: outcome.complete ? TaskStatus.completed : null,
    );
    tasks[outcome.taskIndex] = task;

    var next = game.copyWith(
      tasks: tasks,
      players: [
        for (final p in game.players)
          p.copyWith(totalScore: totals[p.userId] ?? 0),
      ],
    );
    if (outcome.complete) {
      if (tasks.every((t) => t.isCompleted)) {
        next = next.copyWith(status: GameStatus.completed);
      } else if (game.currentTaskIndex == outcome.taskIndex &&
          outcome.taskIndex < tasks.length - 1) {
        next = next.copyWith(currentTaskIndex: outcome.taskIndex + 1);
      }
    }
    return next;
  }
}
