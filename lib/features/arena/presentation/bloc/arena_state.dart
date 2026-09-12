import 'package:equatable/equatable.dart';

import '../../domain/models/feed_post.dart';

abstract class ArenaState extends Equatable {
  const ArenaState();

  @override
  List<Object?> get props => [];
}

class ArenaInitial extends ArenaState {
  const ArenaInitial();
}

class ArenaLoading extends ArenaState {
  const ArenaLoading();
}

class ArenaLoaded extends ArenaState {
  final List<FeedPost> queue;

  /// Pointer into [queue]. Posts before it have been graded or skipped.
  final int index;

  /// Grades the viewer has given since this screen opened — drives the
  /// "Grade 3 entries to jump the queue" progress.
  final int gradedThisSession;

  /// Grades the viewer has ever given.
  final int totalGradedByMe;

  const ArenaLoaded({
    required this.queue,
    required this.index,
    required this.gradedThisSession,
    required this.totalGradedByMe,
  });

  /// The UI shows an AdSlotCard before every 6th post.
  static const int adEvery = 6;

  FeedPost? get current =>
      index >= 0 && index < queue.length ? queue[index] : null;

  bool get isDone => index >= queue.length;

  /// True on exactly the grade that earns the boost, so the UI can celebrate
  /// once. The bloc itself calls `boostPostsOf` once, when the viewer's
  /// all-time grade count crosses 3.
  bool get justEarnedBoost => gradedThisSession == 3;

  ArenaLoaded copyWith({
    List<FeedPost>? queue,
    int? index,
    int? gradedThisSession,
    int? totalGradedByMe,
  }) {
    return ArenaLoaded(
      queue: queue ?? this.queue,
      index: index ?? this.index,
      gradedThisSession: gradedThisSession ?? this.gradedThisSession,
      totalGradedByMe: totalGradedByMe ?? this.totalGradedByMe,
    );
  }

  @override
  List<Object?> get props => [queue, index, gradedThisSession, totalGradedByMe];
}

class ArenaEmpty extends ArenaState {
  /// True when the viewer has not submitted anything yet, so there is nothing
  /// they are allowed to see: "Post yours to unlock everyone else's."
  /// False means they have unlocked tasks but the queue is currently empty
  /// (everything already graded).
  final bool nothingUnlocked;

  const ArenaEmpty({required this.nothingUnlocked});

  @override
  List<Object?> get props => [nothingUnlocked];
}

class ArenaError extends ArenaState {
  final String message;

  const ArenaError({required this.message});

  @override
  List<Object?> get props => [message];
}
