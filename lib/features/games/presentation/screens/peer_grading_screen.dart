import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/models/submission.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/link_utils.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../arena/domain/models/feed_post.dart';
import '../../../arena/domain/repositories/feed_repository.dart';
import '../../../arena/presentation/widgets/arena_video.dart';
import '../../../arena/presentation/widgets/grade_bar.dart';
import '../../domain/repositories/game_repository.dart';
import '../bloc/peer_grading_cubit.dart';

/// Friend games, everyone grades everyone (WP-13): the in-game grade queue.
///
/// One entry at a time — the player, their entry, and the Arena's 1..5 grade
/// bar. Grading moves straight on to the next entry; when the queue is empty
/// the screen says so and explains when scores lock.
class PeerGradingScreen extends StatelessWidget {
  final String gameId;
  final int taskIndex;
  final String currentUserId;

  /// Injectable for tests; default to the service locator.
  final GameRepository? gameRepository;

  /// Photo entries live on their Arena post; null skips that lookup.
  final FeedRepository? feedRepository;

  const PeerGradingScreen({
    super.key,
    required this.gameId,
    required this.taskIndex,
    required this.currentUserId,
    this.gameRepository,
    this.feedRepository,
  });

  @override
  Widget build(BuildContext context) {
    final feed = feedRepository ??
        (sl.isRegistered<FeedRepository>() ? sl<FeedRepository>() : null);
    return BlocProvider(
      create: (_) => PeerGradingCubit(
        gameRepository: gameRepository ?? sl<GameRepository>(),
        gameId: gameId,
        taskIndex: taskIndex,
        currentUserId: currentUserId,
      ),
      child: _PeerGradingView(feedRepository: feed),
    );
  }
}

class _PeerGradingView extends StatelessWidget {
  final FeedRepository? feedRepository;

  const _PeerGradingView({required this.feedRepository});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Grade the crew')),
      body: BlocConsumer<PeerGradingCubit, PeerGradingState>(
        listenWhen: (a, b) =>
            b is PeerGradingReady &&
            b.error != null &&
            (a is! PeerGradingReady || a.error != b.error),
        listener: (context, state) {
          final error = (state as PeerGradingReady).error!;
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(error)));
        },
        builder: (context, state) {
          return switch (state) {
            PeerGradingLoading() =>
              const Center(child: CircularProgressIndicator()),
            PeerGradingUnavailable() => const _Message(
                icon: Icons.search_off_rounded,
                title: 'This task is gone',
                body: 'The game may have been deleted.',
              ),
            PeerGradingReady(isDone: true) => _AllGraded(state: state),
            PeerGradingReady() => _EntryToGrade(
                state: state,
                feedRepository: feedRepository,
              ),
          };
        },
      ),
    );
  }
}

class _EntryToGrade extends StatelessWidget {
  final PeerGradingReady state;
  final FeedRepository? feedRepository;

  const _EntryToGrade({required this.state, required this.feedRepository});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.tokens;
    final entry = state.current!;
    final player = state.game.getPlayerById(entry.userId);
    final name = player?.displayName ?? 'A friend';
    final total = state.gradedCount + state.queue.length;
    final position = state.gradedCount + 1;
    final rubric = state.task.rubric;

    return ListView(
      key: Key('peer-grade-entry-${entry.userId}'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Text(
          'ENTRY $position OF $total',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.3,
          ),
        ),
        const SizedBox(height: 6),
        Text(state.task.title, style: theme.textTheme.titleLarge),
        const SizedBox(height: 16),
        Row(
          children: [
            UserAvatar(displayName: name, radius: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium),
            ),
            if (entry.isLate)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: tokens.lateContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('LATE',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: tokens.onLateContainer)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: _EntryMedia(
            key: ValueKey('media-${entry.userId}'),
            entry: entry,
            feedRepository: feedRepository,
          ),
        ),
        if (entry.caption != null && entry.caption!.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(entry.caption!, style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: 20),
        Text(
          rubric == null || rubric.isEmpty ? 'How did they do?' : rubric,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        AbsorbPointer(
          absorbing: state.submitting,
          child: GradeBar(
            key: ValueKey('grade-bar-${entry.userId}'),
            onGrade: (score) =>
                context.read<PeerGradingCubit>().grade(entry.userId, score),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Grades are anonymous. Scores lock once everyone has graded, '
          'or after 24 hours.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _AllGraded extends StatelessWidget {
  final PeerGradingReady state;

  const _AllGraded({required this.state});

  @override
  Widget build(BuildContext context) {
    final graded = state.gradedCount;
    return _Message(
      key: const Key('peer-grade-done'),
      icon: Icons.check_circle_rounded,
      title: graded == 0 ? 'Nothing to grade yet' : 'All graded',
      body: graded == 0
          ? 'Entries show up here as your friends post them.'
          : 'Thanks! Scores lock once everyone has graded, or after 24 hours.',
      action: FilledButton(
        onPressed: () => Navigator.of(context).maybePop(),
        child: const Text('Back to the game'),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  const _Message({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: context.tokens.success),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(body,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            if (action != null) ...[
              const SizedBox(height: 24),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// The entry itself: an in-app clip plays inline, text shows large, a photo
/// comes from its Arena post, and a pasted link opens externally.
class _EntryMedia extends StatelessWidget {
  final Submission entry;
  final FeedRepository? feedRepository;

  const _EntryMedia({super.key, required this.entry, this.feedRepository});

  @override
  Widget build(BuildContext context) {
    switch (entry.mediaType) {
      case SubmissionMediaType.video:
        return AspectRatio(
          aspectRatio: 9 / 16,
          child: ArenaVideo(
            url: entry.videoUrl,
            durationSeconds: entry.videoDurationSeconds,
            timerSeconds: entry.timerSeconds,
            clockOffsetSeconds: entry.clockOffsetSeconds,
            isLate: entry.isLate,
          ),
        );
      case SubmissionMediaType.text:
        return _Panel(child: _PanelText(entry.text ?? entry.textAnswer ?? ''));
      case SubmissionMediaType.photo:
        final repo = feedRepository;
        final postId = entry.feedPostId;
        if (repo == null || postId == null) {
          return const _Panel(child: _PanelText('Photo entry'));
        }
        return StreamBuilder<FeedPost?>(
          stream: repo.watchPost(postId),
          builder: (context, snap) {
            final data = snap.data?.photoData;
            if (data == null || data.isEmpty) {
              return const _Panel(child: _PanelText('Loading photo…'));
            }
            try {
              return Image.memory(base64Decode(data),
                  fit: BoxFit.cover, gaplessPlayback: true);
            } catch (_) {
              return const _Panel(child: _PanelText('Could not load photo'));
            }
          },
        );
      case SubmissionMediaType.link:
        final url = entry.videoUrl;
        return _Panel(
          child: FilledButton.tonalIcon(
            onPressed:
                url == null ? null : () => LinkUtils.openExternal(context, url),
            icon: const Icon(Icons.play_circle_outline),
            label: const Text('Watch their video'),
          ),
        );
    }
  }
}

class _Panel extends StatelessWidget {
  final Widget child;

  const _Panel({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 200),
      decoration: BoxDecoration(gradient: context.tokens.heroGradient),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: child,
    );
  }
}

class _PanelText extends StatelessWidget {
  final String text;

  const _PanelText(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: context.tokens.onHero,
            fontWeight: FontWeight.w600,
          ),
    );
  }
}
