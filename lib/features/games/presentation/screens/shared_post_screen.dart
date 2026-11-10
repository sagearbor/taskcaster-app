import 'package:flutter/material.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/services/share/share_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../arena/domain/models/feed_post.dart';
import '../../../arena/domain/repositories/feed_repository.dart';
import '../../../arena/presentation/widgets/post_card.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import '../../../tasks/data/datasources/starter_pack_data.dart';
import '../widgets/pending_share_gate.dart';

/// A shared Arena attempt opened in the app (`/p/<id>`, or a `/c/` dare whose
/// task is not public): the clip, then "Your turn". The in-app twin of the
/// public share page (functions/src/share_page.js), with the same privacy
/// rule — a post that is not shareable shows only to its owner.
class SharedPostScreen extends StatefulWidget {
  final String postId;

  /// Injectable for tests; default to the locator.
  final FeedRepository? feedRepository;
  final String? viewerUid;

  const SharedPostScreen({
    super.key,
    required this.postId,
    this.feedRepository,
    this.viewerUid,
  });

  @override
  State<SharedPostScreen> createState() => _SharedPostScreenState();
}

class _SharedPostScreenState extends State<SharedPostScreen> {
  late final Stream<FeedPost?> _post;
  late final String? _me;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _post = (widget.feedRepository ?? sl<FeedRepository>())
        .watchPost(widget.postId);
    _me = widget.viewerUid ??
        (sl.isRegistered<AuthRepository>()
            ? sl<AuthRepository>().getCurrentUserId()
            : null);
  }

  Future<void> _yourTurn(String? publicTaskId) async {
    if (_opening) return;
    setState(() => _opening = true);
    // A public task: that task. Anything else: the player's own next task.
    await openSharedTask(
      context,
      taskId: publicTaskId,
      fromPostId: publicTaskId == null ? null : widget.postId,
    );
    if (mounted) setState(() => _opening = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.violetDeep,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(gradient: AppTheme.heroGradient),
        child: SafeArea(
          child: StreamBuilder<FeedPost?>(
            stream: _post,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                );
              }
              final post = snapshot.data;
              final visible = post != null &&
                  (ShareService.isPublic(post) || post.userId == _me);
              if (!visible) return _gone(context);
              return _content(context, post);
            },
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, FeedPost post) {
    final publicId = resolvePublicTaskId(post.taskId);
    final seconds = publicId == null
        ? null
        : StarterPackData.byId(publicId)?.teaserSeconds;
    final first = post.displayName.trim().split(RegExp(r'\s+')).first;
    final name = first.isEmpty ? 'Someone' : first;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$name vs. ${post.taskTitle}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 16),
          PostCard(post: post),
          const SizedBox(height: 20),
          SizedBox(
            height: 58,
            child: FilledButton(
              key: const Key('shared-post-your-turn'),
              onPressed: _opening ? null : () => _yourTurn(publicId),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.coral,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                publicId == null
                    ? 'Play your own'
                    : 'Your turn — ${seconds ?? 30} s',
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Same task. The clock starts when your camera opens.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withOpacity(0.8)),
          ),
        ],
      ),
    );
  }

  Widget _gone(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🙈', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 12),
            Text(
              'This one\'s private (or gone).',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _opening ? null : () => _yourTurn(null),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.coral,
                foregroundColor: Colors.white,
              ),
              child: const Text('Play a task instead'),
            ),
          ],
        ),
      ),
    );
  }
}
