import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/models/game.dart';
import 'package:taskcaster_app/core/models/game_settings.dart';
import 'package:taskcaster_app/core/models/player.dart';
import 'package:taskcaster_app/core/models/player_task_status.dart';
import 'package:taskcaster_app/core/models/submission.dart';
import 'package:taskcaster_app/features/arena/domain/models/feed_post.dart';
import 'package:taskcaster_app/features/home/domain/home_hero_plan.dart';
import 'package:taskcaster_app/features/tasks/data/datasources/daily_task_data.dart';
import 'package:taskcaster_app/features/tasks/data/datasources/starter_pack_data.dart';

const uid = 'me';
final now = DateTime.utc(2026, 11, 9, 18, 48);
final today = DailyTaskData.dayKey(now);

Game starter({required int posted}) {
  final tasks = StarterPackData.tasks();
  return Game(
    id: 'starter-game',
    gameName: StarterPackData.gameName,
    creatorId: uid,
    judgeId: uid,
    status: GameStatus.inProgress,
    inviteCode: 'AAA111',
    createdAt: DateTime.utc(2026, 11, 1),
    players: const [Player(userId: uid, displayName: 'Me', totalScore: 0)],
    tasks: [
      for (var i = 0; i < tasks.length; i++)
        tasks[i].copyWith(playerStatuses: {
          uid: PlayerTaskStatus(
            playerId: uid,
            state: i < posted
                ? TaskPlayerState.submitted
                : TaskPlayerState.not_started,
          ),
        }),
    ],
    settings: const GameSettings(crowdJudged: true, shareToArena: true),
    gameKind: Game.kindStarter,
  );
}

Game daily({required bool posted, String? dayKey}) {
  final key = dayKey ?? today;
  return Game(
    id: DailyTaskData.gameIdFor(uid, key),
    gameName: DailyTaskData.gameNameFor(key),
    creatorId: uid,
    judgeId: uid,
    status: GameStatus.inProgress,
    inviteCode: 'BBB222',
    createdAt: now,
    players: const [Player(userId: uid, displayName: 'Me', totalScore: 0)],
    tasks: [
      DailyTaskData.taskForDayKey(key).copyWith(playerStatuses: {
        uid: PlayerTaskStatus(
          playerId: uid,
          state:
              posted ? TaskPlayerState.submitted : TaskPlayerState.not_started,
        ),
      }),
    ],
    settings: const GameSettings(crowdJudged: true, shareToArena: true),
    gameKind: Game.kindDaily,
  );
}

FeedPost post(String taskId, DateTime at) => FeedPost(
      id: '$taskId@$at',
      gameId: 'g',
      taskId: taskId,
      taskTitle: 't',
      userId: uid,
      displayName: 'Me',
      mediaType: SubmissionMediaType.text,
      text: 'x',
      createdAt: at,
    );

HomeHeroPlan plan(List<Game> games, [List<FeedPost> posts = const []]) =>
    HomeHeroPlan.resolve(games: games, myPosts: posts, userId: uid, now: now);

void main() {
  final dailyId = DailyTaskData.taskFor(now).id;
  final yesterday = now.subtract(const Duration(days: 1));

  test('no starter game: offer one', () {
    expect(plan([]).kind, HomeHeroKind.noStarter);
  });

  test('starter in progress, nothing posted today: the next starter task', () {
    final p = plan([starter(posted: 2)], [post('starter-03', yesterday)]);
    expect(p.kind, HomeHeroKind.starterTask);
    expect(p.starterNextIndex, 2);
    expect(p.starterTask!.id, StarterPackData.tasks()[2].id);
    expect(p.streak, 1);
    expect(p.streakAtRisk, isTrue);
  });

  test('a starter task posted today brings today\'s task forward', () {
    final p = plan([starter(posted: 1)], [post('starter-09-v2', now)]);
    expect(p.kind, HomeHeroKind.dailyTask);
    expect(p.dailyTask.id, dailyId);
    expect(p.starterHasTasksLeft, isTrue);
    expect(p.streak, 1);
    expect(p.streakAtRisk, isFalse);
  });

  test('starter left and today\'s task done: back to the starter', () {
    final p = plan(
      [starter(posted: 1), daily(posted: true)],
      [post('starter-09-v2', now), post(dailyId, now)],
    );
    expect(p.kind, HomeHeroKind.starterTask);
    expect(p.dailyDone, isTrue);
  });

  test('starter finished: today\'s task', () {
    final p = plan([starter(posted: 10)], [post('starter-08-v2', yesterday)]);
    expect(p.kind, HomeHeroKind.dailyTask);
    expect(p.streakAtRisk, isTrue);
  });

  test('starter finished and today posted: done for today', () {
    final p = plan(
      [starter(posted: 10), daily(posted: true)],
      [post('starter-08-v2', yesterday), post(dailyId, now)],
    );
    expect(p.kind, HomeHeroKind.dailyDone);
    expect(p.streak, 2);
    expect(p.untilNextTask, const Duration(hours: 5, minutes: 12));
  });

  test('the daily game alone (post not landed yet) is enough, and counts '
      'for the streak', () {
    final p = plan(
      [starter(posted: 10), daily(posted: true)],
      [post('starter-08-v2', yesterday)],
    );
    expect(p.kind, HomeHeroKind.dailyDone);
    expect(p.streak, 2);
    expect(p.streakAtRisk, isFalse);
  });

  test('the post alone (game not reloaded yet) is enough', () {
    final p = plan([starter(posted: 10)], [post(dailyId, now)]);
    expect(p.kind, HomeHeroKind.dailyDone);
    expect(p.streak, 1);
  });

  test('yesterday\'s daily game does not count as today\'s', () {
    final yKey = DailyTaskData.dayKey(yesterday);
    final p = plan([starter(posted: 10), daily(posted: true, dayKey: yKey)]);
    expect(p.kind, HomeHeroKind.dailyTask);
  });

  test('the same task id posted 30 days ago does not count as today', () {
    final p = plan(
      [starter(posted: 10)],
      [post(dailyId, now.subtract(const Duration(days: 30)))],
    );
    expect(p.kind, HomeHeroKind.dailyTask);
    expect(p.dailyDone, isFalse);
  });

  test('the next UTC day brings a fresh task to do', () {
    final tomorrow = DateTime.utc(2026, 11, 10, 0, 5);
    final p = HomeHeroPlan.resolve(
      games: [starter(posted: 10), daily(posted: true)],
      myPosts: [post(dailyId, now)],
      userId: uid,
      now: tomorrow,
    );
    expect(p.kind, HomeHeroKind.dailyTask);
    expect(p.dailyTask.id, isNot(dailyId));
    expect(p.streak, 1);
    expect(p.streakAtRisk, isTrue);
  });
}
