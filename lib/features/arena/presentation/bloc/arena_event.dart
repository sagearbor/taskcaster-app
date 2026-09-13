import 'package:equatable/equatable.dart';

abstract class ArenaEvent extends Equatable {
  const ArenaEvent();

  @override
  List<Object?> get props => [];
}

/// Open the Arena for [viewerId]. The bloc derives what they have unlocked
/// from `FeedRepository.watchUnlockedTaskIds` and keeps the queue live.
class LoadArena extends ArenaEvent {
  final String viewerId;

  const LoadArena({required this.viewerId});

  @override
  List<Object?> get props => [viewerId];
}

/// Viewer "that's funny" tap on the current post. Never blocks, never fails
/// visibly, never advances the queue.
///
/// [atSecond] is the second of the clip the tap landed on (null for a post
/// with no timeline), which the repository folds into the post's `tapSeconds`
/// histogram alongside the plain counter.
class TapCurrent extends ArenaEvent {
  final int? atSecond;

  const TapCurrent({this.atSecond});

  @override
  List<Object?> get props => [atSecond];
}

/// Grade the current post 1..5 and advance.
class GradeCurrent extends ArenaEvent {
  final int score;

  const GradeCurrent({required this.score});

  @override
  List<Object?> get props => [score];
}

/// Advance without grading.
class SkipCurrent extends ArenaEvent {
  const SkipCurrent();
}
