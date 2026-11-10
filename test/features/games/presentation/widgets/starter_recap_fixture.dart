// Shared fixture for the StarterRecapView tests and goldens: a real Starter
// Pack game where the player has posted [posted] of the ten tasks, a few of
// which the crowd has already scored.
import 'dart:convert';
import 'dart:io';

import 'package:taskcaster_app/core/models/game.dart';
import 'package:taskcaster_app/core/models/game_settings.dart';
import 'package:taskcaster_app/core/models/player.dart';
import 'package:taskcaster_app/core/models/player_task_status.dart';
import 'package:taskcaster_app/core/models/submission.dart';
import 'package:taskcaster_app/core/models/task.dart';
import 'package:taskcaster_app/features/arena/domain/models/feed_post.dart';
import 'package:taskcaster_app/features/tasks/data/datasources/starter_pack_data.dart';

const recapMe = 'me';
final recapCreated = DateTime(2026, 11, 9, 12);

String recapPhoto(String name) => base64Encode(
    File('test/fixtures/recap/$name.jpg').readAsBytesSync());

/// One posted entry: media, stamp, crowd grades, and (optionally) the score
/// CrowdScoreApplier locked into the game.
class RecapSpec {
  final SubmissionMediaType type;
  final String? photo;
  final String? text;
  final String stamp;
  final int grades;
  final int gradeSum;
  final int? locked;

  const RecapSpec(this.type,
      {this.photo,
      this.text,
      required this.stamp,
      this.grades = 0,
      this.gradeSum = 0,
      this.locked});
}

const recapSpecs = <RecapSpec>[
  RecapSpec(SubmissionMediaType.photo,
      photo: 'face', stamp: 'NAILED IT', grades: 5, gradeSum: 19, locked: 8),
  RecapSpec(SubmissionMediaType.text,
      text: 'The toaster is now "Gerald". He knows what he did.',
      stamp: 'NO REGRETS',
      grades: 3,
      gradeSum: 9,
      locked: 6),
  RecapSpec(SubmissionMediaType.photo,
      photo: 'sock', stamp: 'TECHNICALLY', grades: 1, gradeSum: 4),
  RecapSpec(SubmissionMediaType.photo,
      photo: 'tower', stamp: 'ART', grades: 4, gradeSum: 17, locked: 8),
  RecapSpec(SubmissionMediaType.photo,
      photo: 'sandwich', stamp: 'SEND HELP', grades: 0),
  RecapSpec(SubmissionMediaType.text,
      text: 'The light stays on. The light has always stayed on.',
      stamp: "DON'T ASK",
      grades: 2,
      gradeSum: 9),
  RecapSpec(SubmissionMediaType.video, stamp: 'NAILED IT', grades: 0),
  RecapSpec(SubmissionMediaType.photo,
      photo: 'face', stamp: 'TECHNICALLY', grades: 0),
  RecapSpec(SubmissionMediaType.text,
      text: 'Hat 1: a colander. Hat 9: a regret.',
      stamp: 'NO REGRETS',
      grades: 0),
  RecapSpec(SubmissionMediaType.photo,
      photo: 'tower', stamp: 'ART', grades: 0),
];

/// The starter game with the first [posted] tasks submitted, and the posts.
({Game game, List<FeedPost> posts}) recapFixture(
    {int posted = 7, bool photos = true}) {
  final base = StarterPackData.tasks();
  final tasks = <Task>[];
  final posts = <FeedPost>[];
  for (var i = 0; i < base.length; i++) {
    final t = base[i];
    if (i >= posted) {
      tasks.add(t.copyWith(
        status: TaskStatus.waiting_for_submissions,
        playerStatuses: {
          recapMe: const PlayerTaskStatus(
              playerId: recapMe, state: TaskPlayerState.not_started),
        },
        submissions: const [],
      ));
      continue;
    }
    final spec = recapSpecs[i];
    final postId = 'post-$i';
    tasks.add(t.copyWith(
      status: TaskStatus.waiting_for_submissions,
      playerStatuses: {
        recapMe: PlayerTaskStatus(
          playerId: recapMe,
          state: spec.locked != null
              ? TaskPlayerState.judged
              : TaskPlayerState.submitted,
          score: spec.locked,
        ),
      },
      submissions: [
        Submission(
          id: 's-$i',
          userId: recapMe,
          score: spec.locked ?? 0,
          isJudged: spec.locked != null,
          submittedAt: recapCreated,
          mediaType: spec.type,
          text: spec.text,
          stamp: spec.stamp,
          feedPostId: postId,
        ),
      ],
    ));
    posts.add(FeedPost(
      id: postId,
      gameId: 'starter-1',
      taskId: t.id,
      taskTitle: t.title,
      userId: recapMe,
      displayName: 'Sage',
      mediaType: spec.type,
      photoData:
          photos && spec.photo != null ? recapPhoto(spec.photo!) : null,
      text: spec.text,
      stamp: spec.stamp,
      createdAt: recapCreated,
      gradeCount: spec.grades,
      gradeSum: spec.gradeSum,
    ));
  }
  final game = Game(
    id: 'starter-1',
    gameName: StarterPackData.gameName,
    creatorId: recapMe,
    judgeId: recapMe,
    status: GameStatus.inProgress,
    inviteCode: 'ABC234',
    createdAt: recapCreated,
    players: const [
      Player(userId: recapMe, displayName: 'Sage', totalScore: 0),
    ],
    tasks: tasks,
    settings: const GameSettings(crowdJudged: true, shareToArena: true),
    gameKind: Game.kindStarter,
  );
  return (game: game, posts: posts);
}
