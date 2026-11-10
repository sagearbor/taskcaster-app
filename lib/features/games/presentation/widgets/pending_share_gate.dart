import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/services/invite/invite_link_parser.dart';
import '../../../../core/services/invite/pending_invite_service.dart';
import '../../../../core/services/share/share_links.dart';
import '../../../arena/domain/models/feed_post.dart';
import '../../../arena/domain/repositories/feed_repository.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import '../../../tasks/data/datasources/starter_pack_data.dart';
import '../../domain/repositories/game_repository.dart';
import '../bloc/games_bloc.dart';
import '../screens/shared_post_screen.dart';
import '../screens/task_execution_screen.dart';

/// Routes the WP-09 share links once someone is signed in (mounted under
/// Home, beside PendingInviteGate):
///
///   TaskLink (/t/<id>, web /?task=<id>&from=<post>)  -> that task, clock
///        ready to start when the camera opens; the Posted screen then shows
///        the answered post side by side
///   ChallengeLink (/c/<postId>)  -> the challenger's task the same way
///   FeedPostLink (/p/<postId>)   -> the shared-post screen ("Your turn")
///
/// A guest arriving from a link is signed in silently first by
/// PendingInviteGuestSignIn, so a stranger goes link -> task in one tap.
class PendingShareGate extends StatefulWidget {
  final Widget child;

  /// Injectable for tests; defaults to the service-locator singleton.
  final PendingInviteService? invites;

  const PendingShareGate({super.key, required this.child, this.invites});

  @override
  State<PendingShareGate> createState() => _PendingShareGateState();
}

class _PendingShareGateState extends State<PendingShareGate> {
  late final PendingInviteService _invites;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _invites = widget.invites ?? sl<PendingInviteService>();
    _invites.addListener(_onLinkMaybeAvailable);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onLinkMaybeAvailable();
    });
  }

  @override
  void dispose() {
    _invites.removeListener(_onLinkMaybeAvailable);
    super.dispose();
  }

  void _onLinkMaybeAvailable() {
    if (!mounted || _busy || _invites.pendingLink == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _busy) return;
      final link = _invites.consumeLink();
      if (link == null) return;
      _busy = true;
      try {
        await openShareLink(context, link);
      } finally {
        _busy = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The Starter Pack id for [taskId] (current or retired), accepting short
/// ids (`starter-09` -> `starter-09-v3`, else `-v2`), or null when it is not
/// a public task. Mirrors functions/src/starter_tasks.js#starterTask.
String? resolvePublicTaskId(String taskId) {
  final ids = {for (final t in StarterPackData.allTasks()) t.id};
  for (final id in [taskId, '$taskId-v3', '$taskId-v2']) {
    if (ids.contains(id)) return id;
  }
  return null;
}

/// Opens one share [link] on top of the current route.
Future<void> openShareLink(BuildContext context, DeepLink link) async {
  switch (link) {
    case TaskLink(:final taskId, :final fromPostId):
      final publicId = resolvePublicTaskId(taskId);
      if (publicId != null) {
        await openSharedTask(context, taskId: publicId, fromPostId: fromPostId);
      } else if (fromPostId != null) {
        _pushSharedPost(context, fromPostId);
      }
    case ChallengeLink(:final challengeId):
      final post = await _loadPost(challengeId);
      if (!context.mounted) return;
      final publicId = post == null ? null : resolvePublicTaskId(post.taskId);
      if (publicId != null) {
        await openSharedTask(context,
            taskId: publicId, fromPostId: challengeId);
      } else {
        _pushSharedPost(context, challengeId);
      }
    case FeedPostLink(:final postId):
      _pushSharedPost(context, postId);
    case JoinGameLink():
      // Joins are PendingInviteGate's job.
      return;
  }
}

void _pushSharedPost(BuildContext context, String postId) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => SharedPostScreen(postId: postId)),
  );
}

Future<FeedPost?> _loadPost(String postId) async {
  try {
    return await sl<FeedRepository>()
        .watchPost(postId)
        .first
        .timeout(const Duration(seconds: 8));
  } catch (e) {
    debugPrint('PendingShareGate: could not load post $postId: $e');
    return null;
  }
}

/// "Your turn": open (or create) the player's Starter Pack on [taskId] with
/// the task screen in autoStart mode — the 30 s clock starts when the camera
/// opens (WP-05's flow). [fromPostId] rides along to the Posted screen.
///
/// A null [taskId] opens the player's next unsubmitted task instead.
Future<void> openSharedTask(
  BuildContext context, {
  required String? taskId,
  String? fromPostId,
}) async {
  assert(taskId == null || ShareLinks.isPublicTask(taskId));
  final navigator = Navigator.of(context);
  final bloc = GamesBloc(
    gameRepository: sl<GameRepository>(),
    authRepository: sl<AuthRepository>(),
  )..add(StartStarterPack(taskId: taskId));
  try {
    await for (final state in bloc.stream) {
      if (state is StarterPackReady) {
        navigator.push(
          MaterialPageRoute(
            builder: (_) => TaskExecutionScreen(
              gameId: state.gameId,
              taskIndex: state.taskIndex,
              autoStart: true,
              challengeFromPostId: fromPostId,
            ),
          ),
        );
        break;
      }
      if (state is GamesError) break;
    }
  } finally {
    await bloc.close();
  }
}
