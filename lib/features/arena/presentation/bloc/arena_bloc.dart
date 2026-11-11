import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/config/e2e_mode.dart';
import '../../../../core/services/moderation/moderation_service.dart';
import '../../../../core/utils/friendly_errors.dart';
import '../../domain/models/feed_post.dart';
import '../../domain/repositories/feed_repository.dart';
import '../../../tasks/data/datasources/starter_pack_data.dart';
import 'arena_event.dart';
import 'arena_state.dart';

/// One snapshot of the Arena: what the viewer has unlocked, and the queue that
/// follows from it.
class _ArenaSnapshot {
  final Set<String> unlockedTaskIds;
  final List<FeedPost> posts;

  const _ArenaSnapshot(this.unlockedTaskIds, this.posts);
}

/// The tease's ranking: graded posts first, best mean grade first, then the
/// most-graded, then the most-tapped. Ungraded posts (the house entry, on a
/// quiet day) only fill the slots nobody graded.
int _teaseOrder(FeedPost a, FeedPost b) {
  final am = a.meanGrade;
  final bm = b.meanGrade;
  if (am != null && bm == null) return -1;
  if (am == null && bm != null) return 1;
  if (am != null && bm != null && am != bm) return bm.compareTo(am);
  if (a.gradeCount != b.gradeCount) return b.gradeCount.compareTo(a.gradeCount);
  return b.tapCount.compareTo(a.tapCount);
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

  /// The longest the Arena waits for the device's cached block list before
  /// showing the queue anyway.
  static const Duration moderationLoadTimeout = Duration(seconds: 2);

  /// How many posts the zero-post tease shows.
  static const int teaserSize = 3;

  /// The task the tease is about: task 1 of the Starter Pack, i.e. the one a
  /// player who has posted nothing is about to be asked to do.
  final String teaserTaskId;

  String _viewerId = '';
  List<FeedPost> _queue = const [];
  int _index = 0;
  int _gradedThisSession = 0;
  int _totalGradedByMe = 0;
  bool _boostRequested = false;
  Set<String> _unlockedTaskIds = const {};

  /// Report / block (App Store 1.2). Null: nothing is filtered (tests that
  /// don't care about moderation).
  final ModerationService? moderation;
  StreamSubscription<void>? _moderationSub;

  /// The last snapshot from the store, kept so a report or block can re-filter
  /// the queue without waiting for the next Firestore emit.
  _ArenaSnapshot? _lastSnapshot;

  ArenaBloc({
    required this.feedRepository,
    String? teaserTaskId,
    this.moderation,
  })  : teaserTaskId = teaserTaskId ?? StarterPackData.tasks().first.id,
        super(const ArenaInitial()) {
    on<LoadArena>(_onLoadArena);
    on<GradeCurrent>(_onGradeCurrent);
    on<SkipCurrent>(_onSkipCurrent);
    on<TapCurrent>(_onTapCurrent);
    on<ModerationChanged>(_onModerationChanged);
    _moderationSub =
        moderation?.changes.listen((_) => add(const ModerationChanged()));
  }

  @override
  Future<void> close() async {
    await _moderationSub?.cancel();
    return super.close();
  }

  /// Taken down, reported by this viewer, or by someone they blocked.
  bool _hidden(FeedPost post) =>
      post.hidden || (moderation?.hides(post) ?? false);

  void _onModerationChanged(
    ModerationChanged event,
    Emitter<ArenaState> emit,
  ) {
    final snapshot = _lastSnapshot;
    if (snapshot == null) return;
    final s = state;
    if (s is! ArenaLoaded && s is! ArenaTeaser && s is! ArenaEmpty) return;
    emit(_stateFor(snapshot));
  }

  Future<void> _onLoadArena(LoadArena event, Emitter<ArenaState> emit) async {
    _viewerId = event.viewerId;
    _queue = const [];
    _index = 0;
    _gradedThisSession = 0;
    _boostRequested = false;
    _lastSnapshot = null;
    emit(const ArenaLoading());

    // The device's cached block list first, so the very first queue emit is
    // already filtered; the account's list follows live.
    // Bounded: a device cache that never answers must not hold the Arena
    // on its skeleton (the live list still applies when it lands).
    try {
      await moderation?.load(event.viewerId).timeout(moderationLoadTimeout);
    } catch (e) {
      debugPrint('ArenaBloc could not load moderation state: $e');
    }

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
      // Nothing unlocked yet: read task 1's entries anyway, for the tease
      // (WP-05). The snapshot still carries the EMPTY unlocked set, which is
      // what keeps grading gated.
      final queryIds = ids.isEmpty ? {teaserTaskId} : ids;
      innerSub = feedRepository
          .watchQueue(viewerId: viewerId, unlockedTaskIds: queryIds)
          .listen(
        (posts) => controller.add(_ArenaSnapshot(ids, posts)),
        onError: (Object error, StackTrace stack) {
          if (ids.isEmpty) {
            // The tease is a nicety: a newcomer whose tease read fails
            // (offline, a missing index) gets the empty tease (finale +
            // "Your turn"), never an error page.
            debugPrint('ArenaBloc tease read failed: $error');
            controller.add(_ArenaSnapshot(ids, const []));
            return;
          }
          controller.addError(error, stack);
        },
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

  ArenaState _stateFor(_ArenaSnapshot raw) {
    _lastSnapshot = raw;
    _unlockedTaskIds = raw.unlockedTaskIds;
    final snapshot = _ArenaSnapshot(
      raw.unlockedTaskIds,
      raw.posts.where((p) => !_hidden(p)).toList(),
    );

    if (snapshot.unlockedTaskIds.isEmpty) {
      // The tease: the funniest few entries for task 1, watch-only. The
      // grading queue stays empty, so GradeCurrent / SkipCurrent / TapCurrent
      // are all no-ops in this state.
      _queue = const [];
      _index = 0;
      final top = snapshot.posts.where((p) => p.taskId == teaserTaskId).toList()
        ..sort(_teaseOrder);
      return ArenaTeaser(
        taskId: teaserTaskId,
        posts: List.unmodifiable(top.take(teaserSize)),
      );
    }

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

    // An automated walk (E2eMode) grades like a player — the reveal is worked
    // out locally on the screen — but never writes the grade or the boost:
    // its grades would land on real people's posts (fun audit follow-up).
    if (E2eMode.isOn) {
      debugPrint('ArenaBloc: E2E mode — grade for ${post.id} not written');
      return;
    }

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
    // E2E walks leave no taps on real posts either.
    if (E2eMode.isOn) return;
    // Fire-and-forget: a tap must never block or fail visibly.
    try {
      await feedRepository.tapPost(post.id, atSecond: event.atSecond);
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
