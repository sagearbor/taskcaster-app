import 'package:flutter/foundation.dart';

import '../../../core/models/game.dart';
import '../../../core/models/player_task_status.dart';
import '../../games/domain/repositories/game_repository.dart';
import 'crowd_score_policy.dart';
import 'models/feed_post.dart';
import 'repositories/feed_repository.dart';

/// Carries settled crowd grades back into the game's scoreboard.
///
/// The client that owns a crowd-judged game is its judge: whenever the owner
/// opens it, any of their submissions whose Arena post has reached a final
/// score is judged with those points. Strictly one-shot per task — a task in
/// the `judged` state is never revisited, so scores can never be applied twice.
class CrowdScoreApplier {
  final GameRepository gameRepository;
  final FeedRepository feedRepository;

  CrowdScoreApplier({
    required this.gameRepository,
    required this.feedRepository,
  });

  /// Judge every one of [game]'s tasks that is waiting on a now-final crowd
  /// score. Returns how many were applied.
  Future<int> applyPending(Game game) async {
    final creatorId = game.creatorId;
    var applied = 0;

    for (var i = 0; i < game.tasks.length; i++) {
      final task = game.tasks[i];

      // Only submitted-not-yet-judged tasks are candidates. `judged` tasks are
      // done forever: this is what makes the applier one-shot.
      final status = task.getPlayerStatus(creatorId);
      if (status == null || status.state != TaskPlayerState.submitted) continue;

      final submission = task.submissions
          .where((s) => s.userId == creatorId && s.feedPostId != null)
          .firstOrNull;
      if (submission == null) continue;

      FeedPost? post;
      try {
        post = await feedRepository.watchPost(submission.feedPostId!).first;
      } catch (e) {
        debugPrint('CrowdScoreApplier could not read post '
            '${submission.feedPostId}: $e');
        continue;
      }
      if (post == null || !CrowdScorePolicy.isFinal(post)) continue;

      await gameRepository.judgeSubmission(
        game.id,
        i,
        creatorId,
        CrowdScorePolicy.points(post),
      );
      applied++;
    }

    return applied;
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
