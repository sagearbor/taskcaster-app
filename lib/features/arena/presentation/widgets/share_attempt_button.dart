import 'package:flutter/material.dart';

import '../../../../core/services/share/share_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/models/feed_post.dart';

/// "Share your attempt" (audit WP-09): the OS share sheet with a funny line
/// and the `/c/<postId>` dare link. Disabled until the post has loaded.
///
/// [primary] is the big coral button (Posted screen); otherwise a white
/// outlined one for dark backdrops ([onDark]) or the theme's outlined style.
class ShareAttemptButton extends StatefulWidget {
  final FeedPost? post;
  final bool primary;
  final bool onDark;
  final String label;

  /// Injectable for tests; defaults to the locator's [ShareService].
  final ShareService? shareService;

  const ShareAttemptButton({
    super.key,
    required this.post,
    this.primary = false,
    this.onDark = false,
    this.label = 'Share your attempt',
    this.shareService,
  });

  @override
  State<ShareAttemptButton> createState() => _ShareAttemptButtonState();
}

class _ShareAttemptButtonState extends State<ShareAttemptButton> {
  bool _busy = false;

  Future<void> _share() async {
    final post = widget.post;
    if (post == null || _busy) return;
    setState(() => _busy = true);
    final service = widget.shareService ?? ShareService.fromLocator();
    final outcome = await service.shareAttempt(post);
    if (!mounted) return;
    setState(() => _busy = false);
    showShareOutcome(context, outcome);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.post != null && !_busy;
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.ios_share_rounded, size: 20),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            widget.label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: widget.primary ? 18 : 16,
              fontWeight: widget.primary ? FontWeight.bold : FontWeight.w700,
            ),
          ),
        ),
      ],
    );
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));

    if (widget.primary) {
      return SizedBox(
        height: 58,
        child: FilledButton(
          key: const Key('share-attempt-button'),
          onPressed: enabled ? _share : null,
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.coral,
            foregroundColor: Colors.white,
            shape: shape,
          ),
          child: child,
        ),
      );
    }
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        key: const Key('share-attempt-button'),
        onPressed: enabled ? _share : null,
        style: widget.onDark
            ? OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white70),
                shape: shape,
              )
            : OutlinedButton.styleFrom(shape: shape),
        child: child,
      ),
    );
  }
}

/// The snackbar after a share: silent for the sheet (the OS already said
/// something), "Link copied" where there is no sheet, a gentle retry line on
/// failure.
void showShareOutcome(BuildContext context, ShareOutcome outcome) {
  final message = switch (outcome) {
    ShareOutcome.sheet => null,
    ShareOutcome.copied => 'Link copied — paste it anywhere.',
    ShareOutcome.failed => 'Couldn\'t share right now. Try again in a moment.',
  };
  if (message == null) return;
  ScaffoldMessenger.maybeOf(context)
      ?.showSnackBar(SnackBar(content: Text(message)));
}
