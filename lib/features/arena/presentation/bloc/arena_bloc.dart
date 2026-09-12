import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/friendly_errors.dart';
import '../../domain/models/feed_post.dart';
import '../../domain/repositories/feed_repository.dart';
import 'arena_event.dart';
import 'arena_state.dart';

/// One snapshot of the Arena: what the viewer has unlocked, and the queue that
/// follows from it.
class _ArenaSnapshot {
  final Set<String> unlockedTaskIds;
  final List<FeedPost> posts;

  const _ArenaSnapshot(this.unlockedTaskIds, this.posts);
}

/// Drives the watch-and-grade queue.
///
/// The queue is live (a new post from anyone shows up without a reload), which
/// means it re-emits under the viewer's feet. To keep grading from jumping
/// around, the posts the viewer has already consumed stay pinned at the front
/// of [ArenaLoaded.queue] in their original order and [ArenaLoaded.index] keeps
/// pointing just past them; only genuinely new posts are appended.
class ArenaBloc extends Bloc<ArenaEvent, ArenaState> {
  final FeedRepository feedRepository;

  /// Grades needed before the viewer's own posts get boosted.
  static const int boostThreshold = 3;

  String _viewerId = '';
  List<FeedPost> _queue = const [];
  int _index = 0;
  int _gradedThisSession = 0;
  int _totalGradedByMe = 0;
  bool _boostRequested = false;
  Set<String> _unlockedTaskIds = const {};

  ArenaBloc({required this.feedRepository}) : super(const ArenaInitial()) {
    on<LoadArena>(_onLoadArena);
    on<GradeCurrent>(_onGradeCurrent);
    on<SkipCurrent>(_onSkipCurrent);
    on<TapCurrent>(_onTapCurrent);
  }

  Future<void> _onLoadArena(LoadArena event, Emitter<ArenaState> emit) async {
    _viewerId = event.viewerId;
    _queue = const [];
    _index = 0;
    _gradedThisSession = 0;
    _boostRequested = false;
    emit(const ArenaLoading());

    try {
      _totalGradedByMe = await feedRepository.gradedCountBy(event.viewerId);
      // Already past the threshold from an earlier session: never re-boost.
      if (_totalGradedByMe >= boostThreshold) _boostRequested = true;
    } catch (e) {
      debugPrint('ArenaBloc could not read grade count: $e');
      _totalGradedByMe = 0;
    }

    await emit.forEach<_ArenaSnapshot>(
      _snapshots(event.viewerId),
      onData: _stateFor,
      onError: (error, _) {
        debugPrint('ArenaBloc queue stream error: $error');
        return ArenaError(
          message: FriendlyErrors.action(
            error,
            fallback: "Couldn't load the Arena. Please try again.",
          ),
        );
      },
    );
  }

  /// `watchUnlockedTaskIds` switched onto `watchQueue` by hand: when the set of
  /// unlocked tasks changes (the viewer just posted something new), the old
  /// queue subscription is dropped and a fresh one opened. `asyncExpand` can't
  /// do this — it waits for the inner stream to finish, and a query stream
  /// never finishes.
  Stream<_ArenaSnapshot> _snapshots(String viewerId) {
    late final StreamController<_ArenaSnapshot> controller;
    StreamSubscription<Set<String>>? outerSub;
    StreamSubscription<List<FeedPost>>? innerSub;
    Set<String>? currentIds;

    void listenToQueue(Set<String> ids) {
      innerSub?.cancel();
      innerSub = feedRepository
          .watchQueue(viewerId: viewerId, unlockedTaskIds: ids)
          .listen(
        (posts) => controller.add(_ArenaSnapshot(ids, posts)),
        onError: controller.addError,
      );
    }

    controller = StreamController<_ArenaSnapshot>(
      onListen: () {
        outerSub = feedRepository.watchUnlockedTaskIds(viewerId).listen(
          (ids) {
            if (currentIds != null && setEquals(currentIds, ids)) return;
            currentIds = ids;
            listenToQueue(ids);
          },
          onError: controller.addError,
        );
      },
      onCancel: () async {
        await innerSub?.cancel();
        await outerSub?.cancel();
      },
    );

    return controller.stream;
  }

  ArenaState _stateFor(_ArenaSnapshot snapshot) {
    _unlockedTaskIds = snapshot.unlockedTaskIds;

    // Keep everything the viewer has already been through pinned at the front
    // so [index] keeps meaning the same thing across re-emits.
    final consumed = _queue.take(_index).toList();
    final consumedIds = consumed.map((p) => p.id).toSet();
    final fresh =
        snapshot.posts.where((p) => !consumedIds.contains(p.id)).toList();
    _queue = [...consumed, ...fresh];

    if (_queue.isEmpty) {
      return ArenaEmpty(nothingUnlocked: snapshot.unlockedTaskIds.isEmpty);
    }

    return ArenaLoaded(
      queue: List.unmodifiable(_queue),
      index: _index,
      gradedThisSession: _gradedThisSession,
      totalGradedByMe: _totalGradedByMe,
    );
  }

  ArenaLoaded _loaded() => ArenaLoaded(
        queue: List.unmodifiable(_queue),
        index: _index,
        gradedThisSession: _gradedThisSession,
        totalGradedByMe: _totalGradedByMe,
      );

  Future<void> _onGradeCurrent(
    GradeCurrent event,
    Emitter<ArenaState> emit,
  ) async {
    final post = _current();
    if (post == null) return;

    // Advance optimistically: grading must feel instant, and a rejected grade
    // (own post, already graded) is a post we should move past anyway.
    _index++;
    _gradedThisSession++;
    _totalGradedByMe++;
    emit(_loaded());

    try {
      await feedRepository.gradePost(
        postId: post.id,
        graderId: _viewerId,
        score: event.score,
      );
    } on StateError catch (e) {
      // Own post or already graded — nothing to fix, just keep going.
      debugPrint('ArenaBloc grade rejected for ${post.id}: ${e.message}');
    } catch (e) {
      debugPrint('ArenaBloc grade failed for ${post.id}: $e');
    }

    if (!_boostRequested && _totalGradedByMe >= boostThreshold) {
      _boostRequested = true;
      try {
        await feedRepository.boostPostsOf(_viewerId);
      } catch (e) {
        debugPrint('ArenaBloc boost failed: $e');
      }
    }
  }

  Future<void> _onSkipCurrent(
    SkipCurrent event,
    Emitter<ArenaState> emit,
  ) async {
    if (_current() == null) return;
    _index++;
    emit(_loaded());
  }

  Future<void> _onTapCurrent(
    TapCurrent event,
    Emitter<ArenaState> emit,
  ) async {
    final post = _current();
    if (post == null) return;
    // Fire-and-forget: a tap must never block or fail visibly.
    try {
      await feedRepository.tapPost(post.id);
    } catch (e) {
      debugPrint('ArenaBloc tap failed for ${post.id}: $e');
    }
  }

  FeedPost? _current() {
    if (state is! ArenaLoaded) return null;
    if (_index < 0 || _index >= _queue.length) return null;
    return _queue[_index];
  }

  /// Task ids the viewer has unlocked, as of the last snapshot. Exposed for
  /// screens that want to explain the gate.
  Set<String> get unlockedTaskIds => _unlockedTaskIds;
}
