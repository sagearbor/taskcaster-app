import 'package:flutter/material.dart';

import '../../../../core/services/moderation/moderation_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/models/feed_post.dart';

/// The "⋯" on someone else's Arena post: Report post / Block <name>
/// (App Store guideline 1.2). Never shown on the viewer's own posts.
///
/// Both actions take effect for the viewer straight away — the post (or every
/// post by that author) drops out of the queue through
/// [ModerationService.changes] — and the server write follows.
class PostMenu extends StatelessWidget {
  final FeedPost post;
  final ModerationService moderation;

  /// The signed-in viewer (reporter / blocker). Empty: hide locally only.
  final String viewerId;

  const PostMenu({
    super.key,
    required this.post,
    required this.moderation,
    required this.viewerId,
  });

  static const String reportThanks =
      'Thanks — we\'ll review it within 24 hours.';

  /// "Greg", or a stand-in for a post with no name.
  static String nameOf(FeedPost post) {
    final name = post.displayName.trim();
    return name.isEmpty ? 'this player' : name;
  }

  @override
  Widget build(BuildContext context) {
    final name = nameOf(post);
    return PopupMenuButton<_PostAction>(
      key: const Key('post-card-more'),
      tooltip: 'More',
      icon: const Icon(Icons.more_horiz_rounded, size: 22),
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.under,
      onSelected: (action) {
        switch (action) {
          case _PostAction.report:
            reportFlow(context,
                post: post, moderation: moderation, viewerId: viewerId);
          case _PostAction.block:
            blockFlow(context,
                post: post, moderation: moderation, viewerId: viewerId);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          key: Key('post-menu-report'),
          value: _PostAction.report,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.flag_outlined, color: AppTheme.coral),
            title: Text('Report post'),
          ),
        ),
        PopupMenuItem(
          key: const Key('post-menu-block'),
          value: _PostAction.block,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.block_rounded, color: AppTheme.coral),
            title: Text('Block $name', overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
    );
  }

  /// Reason picker, then a confirm step, then hide + report + thank.
  static Future<void> reportFlow(
    BuildContext context, {
    required FeedPost post,
    required ModerationService moderation,
    required String viewerId,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final reason = await showDialog<ReportReason>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        key: const Key('report-reason-dialog'),
        title: const Text('Why are you reporting this?'),
        children: [
          for (final r in ReportReason.values)
            SimpleDialogOption(
              key: Key('report-reason-${r.value}'),
              onPressed: () => Navigator.of(dialogContext).pop(r),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(r.label,
                    style: Theme.of(dialogContext).textTheme.titleMedium),
              ),
            ),
        ],
      ),
    );
    if (reason == null || !context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('report-confirm-dialog'),
        title: const Text('Report this post?'),
        content: Text(
          'Reason: ${reason.label}. The post will be hidden for you, and '
          'we\'ll review it within 24 hours.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('report-confirm'),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.coral),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Report'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // Hidden for the reporter the moment they confirm; the write follows (and
    // Firestore queues it if they're offline).
    final write = moderation.reportPost(
      post: post,
      reason: reason,
      reporterId: viewerId,
    );
    messenger?.showSnackBar(const SnackBar(content: Text(reportThanks)));
    try {
      await write;
    } catch (e) {
      debugPrint('Report for ${post.id} not written: $e');
    }
  }

  /// Confirm, then block the author for this account.
  static Future<void> blockFlow(
    BuildContext context, {
    required FeedPost post,
    required ModerationService moderation,
    required String viewerId,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final name = nameOf(post);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('block-confirm-dialog'),
        title: Text('Block $name?'),
        content: Text(
          'You won\'t see posts from $name in the Arena any more. You can '
          'unblock them in Settings > Blocked players.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('block-confirm'),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.coral),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Block'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final write = moderation.blockAuthorOf(post, uid: viewerId);
    messenger?.showSnackBar(SnackBar(content: Text('$name is blocked.')));
    try {
      await write;
    } catch (e) {
      debugPrint('Block of ${post.authorKey} not saved to the account: $e');
    }
  }
}

enum _PostAction { report, block }
