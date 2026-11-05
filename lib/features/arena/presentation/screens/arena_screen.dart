import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shimmer/shimmer.dart';

import '../../../../core/config/environment.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../tasks/data/datasources/starter_pack_data.dart';
import '../../domain/models/montage.dart';
import '../../domain/repositories/feed_repository.dart';
import '../bloc/arena_bloc.dart';
import '../bloc/arena_event.dart';
import '../bloc/arena_state.dart';
import '../widgets/ad_slot_card.dart';
import '../widgets/finale_card.dart';
import '../widgets/grade_bar.dart';
import '../widgets/post_card.dart';

/// The Arena: a watch-and-grade queue, one post at a time, gated to tasks the
/// viewer has already submitted (see docs/PRODUCT_DIRECTION.md §2.3).
///
/// Takes no parameters — it reads the signed-in viewer off [AuthBloc] and
/// builds its own [ArenaBloc] from [FeedRepository].
class ArenaScreen extends StatelessWidget {
  const ArenaScreen({super.key});

  /// What the route pops with when a zero-post viewer taps the tease's
  /// "Your turn" bar. Home answers it by opening Starter Pack task 1; any
  /// other caller just gets the Arena closed, which lands them back on the
  /// task they came from.
  static const String yourTurnResult = 'your-turn';

  @override
  Widget build(BuildContext context) {
    final authState = context.read<AuthBloc>().state;
    final viewerId =
        authState is AuthAuthenticated ? authState.user.id : '';

    return BlocProvider(
      create: (_) => ArenaBloc(feedRepository: sl<FeedRepository>())
        ..add(LoadArena(viewerId: viewerId)),
      child: const _ArenaView(),
    );
  }
}

class _ArenaView extends StatelessWidget {
  const _ArenaView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('The Arena'),
        actions: [
          BlocBuilder<ArenaBloc, ArenaState>(
            builder: (context, state) {
              final graded = state is ArenaLoaded ? state.totalGradedByMe : 0;
              return Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: Text(
                    'graded $graded',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: BlocConsumer<ArenaBloc, ArenaState>(
        listenWhen: (previous, current) =>
            current is ArenaLoaded &&
            current.justEarnedBoost &&
            !(previous is ArenaLoaded && previous.justEarnedBoost),
        listener: (context, state) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Your posts jumped the queue'),
            ),
          );
        },
        builder: (context, state) {
          if (state is ArenaLoading || state is ArenaInitial) {
            return const _ArenaSkeleton();
          }
          if (state is ArenaError) {
            return ErrorView(
              message: 'Something went wrong',
              details: state.message,
              onRetry: () {
                final authState = context.read<AuthBloc>().state;
                final viewerId =
                    authState is AuthAuthenticated ? authState.user.id : '';
                context.read<ArenaBloc>().add(LoadArena(viewerId: viewerId));
              },
            );
          }
          if (state is ArenaTeaser) {
            return _ArenaTeaserView(state: state);
          }
          if (state is ArenaEmpty) {
            return _ArenaEmptyView(nothingUnlocked: state.nothingUnlocked);
          }
          if (state is ArenaLoaded) {
            return _ArenaLoadedBody(state: state);
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

class _ArenaEmptyView extends StatelessWidget {
  final bool nothingUnlocked;

  const _ArenaEmptyView({required this.nothingUnlocked});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.theater_comedy, size: 72, color: AppTheme.violet),
            const SizedBox(height: 24),
            Text(
              nothingUnlocked
                  ? 'Post yours to unlock everyone else\'s'
                  : 'Nothing new to grade right now — check back soon.',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            if (nothingUnlocked) ...[
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Do a task'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// WP-05: the Arena for a viewer with zero posts. The funniest content the
/// app has, visible exactly when a newcomer decides whether to stay — the
/// finale and the top few entries for task 1, one at a time, watch-only —
/// with a sticky "Your turn" bar. No grade bar: grading stays gated.
class _ArenaTeaserView extends StatefulWidget {
  final ArenaTeaser state;

  const _ArenaTeaserView({required this.state});

  @override
  State<_ArenaTeaserView> createState() => _ArenaTeaserViewState();
}

class _ArenaTeaserViewState extends State<_ArenaTeaserView> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final posts = widget.state.posts;
    final index = posts.isEmpty ? 0 : _index.clamp(0, posts.length - 1);
    final seconds = _durationFor(widget.state.taskId);

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text(
                    posts.isEmpty
                        ? 'Post yours to unlock everyone else\'s'
                        : 'How everyone else did on task 1',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                // THE FINALE for task 1 (starter montages are shared, so the
                // scope id is all it needs). Renders nothing until one exists.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: FinaleCard(
                    gameId: Montage.starterScope,
                    taskId: widget.state.taskId,
                  ),
                ),
                if (posts.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: PostCard(
                      key: ValueKey('tease-${posts[index].id}'),
                      post: posts[index],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Icon(Icons.lock_outline,
                            size: 16, color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Grading unlocks when you post yours.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (posts.length > 1)
                          TextButton(
                            onPressed: () => setState(
                                () => _index = (index + 1) % posts.length),
                            child: Text('Next (${index + 1}/${posts.length})'),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        Material(
          elevation: 8,
          color: theme.colorScheme.surface,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  key: const Key('arena-your-turn'),
                  onPressed: () => Navigator.of(context)
                      .pop(ArenaScreen.yourTurnResult),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.coral,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    seconds == null ? 'Your turn' : 'Your turn: $seconds s',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  static int? _durationFor(String taskId) {
    for (final t in StarterPackData.tasks()) {
      if (t.id == taskId) return t.durationSeconds;
    }
    return null;
  }
}

class _ArenaLoadedBody extends StatefulWidget {
  final ArenaLoaded state;

  const _ArenaLoadedBody({required this.state});

  @override
  State<_ArenaLoadedBody> createState() => _ArenaLoadedBodyState();
}

class _ArenaLoadedBodyState extends State<_ArenaLoadedBody> {
  // Tracks the queue index for which the ad slot has already been shown and
  // continued past, so it renders exactly once per cadence hit rather than
  // reappearing on every rebuild of the same index.
  int? _adConsumedForIndex;

  bool get _adsVisible => AppConfig.adsEnabled || AdSlotCard.debugAlwaysShow;

  bool _shouldShowAdFor(int index) {
    if (!_adsVisible) return false;
    final isCadenceHit = (index + 1) % ArenaLoaded.adEvery == 0;
    return isCadenceHit && _adConsumedForIndex != index;
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;

    if (state.isDone) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                "You've graded everything you've unlocked. Do the next "
                'task to unlock more.',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Back'),
              ),
            ],
          ),
        ),
      );
    }

    final index = state.index;
    if (_shouldShowAdFor(index)) {
      return SingleChildScrollView(
        child: AdSlotCard(
          onContinue: () => setState(() => _adConsumedForIndex = index),
        ),
      );
    }

    final post = state.current!;
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        key: ValueKey(post.id),
        children: [
          // The automatic finale for this task, when the server has rendered
          // one. Silent no-op otherwise.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: FinaleCard(
              gameId: post.gameId,
              taskId: post.taskId,
              taskTitle: post.taskTitle,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: PostCard(
              post: post,
              onTap: (atSecond) => context
                  .read<ArenaBloc>()
                  .add(TapCurrent(atSecond: atSecond)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Grade for: ${post.rubric ?? 'how it landed'}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 12),
                GradeBar(
                  onGrade: (score) =>
                      context.read<ArenaBloc>().add(GradeCurrent(score: score)),
                ),
                Center(
                  child: TextButton(
                    onPressed: () =>
                        context.read<ArenaBloc>().add(const SkipCurrent()),
                    child: const Text('Skip'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ArenaSkeleton extends StatelessWidget {
  const _ArenaSkeleton();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Shimmer.fromColors(
        baseColor: Colors.grey[300]!,
        highlightColor: Colors.grey[100]!,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 4 / 5,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(height: 16, width: 180, color: Colors.white),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(
                5,
                (_) => Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
