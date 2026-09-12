import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shimmer/shimmer.dart';

import '../../../../core/config/environment.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/repositories/feed_repository.dart';
import '../bloc/arena_bloc.dart';
import '../bloc/arena_event.dart';
import '../bloc/arena_state.dart';
import '../widgets/ad_slot_card.dart';
import '../widgets/grade_bar.dart';
import '../widgets/post_card.dart';

/// The Arena: a watch-and-grade queue, one post at a time, gated to tasks the
/// viewer has already submitted (see docs/PRODUCT_DIRECTION.md §2.3).
///
/// Takes no parameters — it reads the signed-in viewer off [AuthBloc] and
/// builds its own [ArenaBloc] from [FeedRepository].
class ArenaScreen extends StatelessWidget {
  const ArenaScreen({super.key});

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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: PostCard(
              post: post,
              onTap: () => context.read<ArenaBloc>().add(const TapCurrent()),
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
