import '../../../core/models/game.dart';
import '../../../core/models/player_task_status.dart';
import '../../../core/models/task.dart';
import '../../arena/domain/models/feed_post.dart';
import '../../tasks/data/datasources/daily_task_data.dart';
import 'streak.dart';

/// Which shape Home's hero takes.
enum HomeHeroKind {
  /// No Starter Pack game yet (an account from before round 7): offer one.
  noStarter,

  /// The next unposted Starter Pack task.
  starterTask,

  /// Today's task, not yet posted.
  dailyTask,

  /// Today's task is posted: "Done for today", the streak, the countdown.
  dailyDone,
}

/// Everything Home's hero needs, decided in one pure function (WP-6) so every
/// state is unit-testable without a widget tree.
///
/// The rules:
///  - no starter game -> [HomeHeroKind.noStarter];
///  - starter tasks left -> the next starter task, EXCEPT when the player has
///    already posted a starter task today and has not done today's task: then
///    today's task leads (that is how a brand-new player meets the daily task
///    on day one), with a way back to the starter;
///  - starter finished -> today's task, or "Done for today" once posted.
class HomeHeroPlan {
  final HomeHeroKind kind;

  /// The 🔥 streak in days (0 = none).
  final int streak;

  /// The streak is alive but nothing is posted today yet.
  final bool streakAtRisk;

  /// Today's task (the same for everyone this UTC day).
  final Task dailyTask;

  /// Today's task is posted.
  final bool dailyDone;

  /// The starter game, when there is one.
  final Game? starterGame;

  /// The next unposted starter task index, or -1 when all are posted.
  final int starterNextIndex;

  /// Time until the next UTC midnight, when today's task changes.
  final Duration untilNextTask;

  const HomeHeroPlan({
    required this.kind,
    required this.streak,
    required this.streakAtRisk,
    required this.dailyTask,
    required this.dailyDone,
    required this.starterGame,
    required this.starterNextIndex,
    required this.untilNextTask,
  });

  bool get starterHasTasksLeft => starterGame != null && starterNextIndex >= 0;

  /// The next starter task, when there is one.
  Task? get starterTask =>
      starterHasTasksLeft ? starterGame!.tasks[starterNextIndex] : null;

  static HomeHeroPlan resolve({
    required List<Game> games,
    required List<FeedPost> myPosts,
    required String userId,
    required DateTime now,
  }) {
    Game? starter;
    for (final g in games) {
      if (g.isStarter) {
        starter = g;
        break;
      }
    }
    var nextIndex = -1;
    if (starter != null) {
      for (var i = 0; i < starter.tasks.length; i++) {
        if (!_posted(starter.tasks[i], userId)) {
          nextIndex = i;
          break;
        }
      }
    }

    final today = DailyTaskData.dayKey(now);
    final dailyTask = DailyTaskData.taskFor(now);
    final dailyGameId = DailyTaskData.gameIdFor(userId, today);
    Game? dailyGame;
    for (final g in games) {
      if (g.id == dailyGameId) {
        dailyGame = g;
        break;
      }
    }

    bool postedTodayWhere(bool Function(FeedPost p) test) => myPosts.any(
        (p) => !p.isHouse && test(p) && DailyTaskData.dayKey(p.createdAt) == today);

    // Either record is enough: the game updates after the post is written,
    // and the post's server timestamp lands a moment after that.
    final dailyDone = (dailyGame != null &&
            dailyGame.tasks.isNotEmpty &&
            _posted(dailyGame.tasks.first, userId)) ||
        postedTodayWhere((p) => p.taskId == dailyTask.id);
    final starterPostedToday =
        postedTodayWhere((p) => p.taskId.startsWith('starter-'));

    var streak = currentStreak(myPosts, now);
    final anyPostToday = postedToday(myPosts, now);
    if (dailyDone && !anyPostToday) {
      // The daily game says posted but the post's server timestamp has not
      // landed yet: today still counts, on top of the run up to yesterday.
      streak += 1;
    }
    final atRisk = streak > 0 && !anyPostToday && !dailyDone;

    final HomeHeroKind kind;
    if (starter == null) {
      kind = HomeHeroKind.noStarter;
    } else if (nextIndex >= 0) {
      kind = (starterPostedToday && !dailyDone)
          ? HomeHeroKind.dailyTask
          : HomeHeroKind.starterTask;
    } else {
      kind = dailyDone ? HomeHeroKind.dailyDone : HomeHeroKind.dailyTask;
    }

    return HomeHeroPlan(
      kind: kind,
      streak: streak,
      streakAtRisk: atRisk,
      dailyTask: dailyTask,
      dailyDone: dailyDone,
      starterGame: starter,
      starterNextIndex: nextIndex,
      untilNextTask: DailyTaskData.untilNextTask(now),
    );
  }

  /// Posted (or already scored) by [userId]: a submission, or a status that
  /// says so.
  static bool _posted(Task task, String userId) {
    if (task.hasUserSubmitted(userId)) return true;
    final state = task.getPlayerStatus(userId)?.state;
    return state == TaskPlayerState.submitted ||
        state == TaskPlayerState.judged;
  }
}
