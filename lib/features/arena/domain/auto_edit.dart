import '../../../core/models/submission.dart';
import 'models/feed_post.dart';

/// The automatic "edit" pass. There is NO manual edit UI anywhere in the app:
/// snap or write, and the stamp and caption are computed from how the attempt
/// actually went.
class AutoEdit {
  const AutoEdit._();

  /// The grace, in seconds, a player gets past the task timer before a
  /// submission is flagged LATE. Mirrors the product rule "timer + 30 s".
  static const int graceSeconds = 30;

  /// Pick one of [Stamps.values] from the attempt.
  ///
  /// Priority, in the order the product spec lists them:
  ///  1. finished inside the first third of the timer -> `NAILED IT`
  ///  2. finished in the last third (and not late)     -> `TECHNICALLY`
  ///  3. late                                          -> `SEND HELP`
  ///  4. a text entry                                  -> `ART`
  ///  5. anything else                                 -> `NO REGRETS`
  ///
  /// (`DON'T ASK` is not chosen here — the feed applies it once a post has
  /// collected [Stamps.dontAskTaps] viewer taps; see [FeedPost.displayStamp].)
  ///
  /// A null [elapsedSeconds] or [timerSeconds] (the player never tapped Start,
  /// or the task has no timer) simply skips the timing rules.
  static String stamp({
    required SubmissionMediaType mediaType,
    required int? elapsedSeconds,
    required int? timerSeconds,
    required bool isLate,
  }) {
    final hasTiming =
        elapsedSeconds != null && timerSeconds != null && timerSeconds > 0;

    if (!isLate && hasTiming && elapsedSeconds <= timerSeconds / 3) {
      return Stamps.nailedIt;
    }
    if (!isLate && hasTiming && elapsedSeconds > (2 * timerSeconds) / 3) {
      return Stamps.technically;
    }
    if (isLate) return Stamps.sendHelp;
    if (mediaType == SubmissionMediaType.text) return Stamps.art;
    return Stamps.noRegrets;
  }

  /// The caption rendered on the post: `"<twist> · Done in 41 s"`, or
  /// `"<twist> · LATE by 12 s"` when the player blew past the grace deadline.
  ///
  /// "LATE by" counts seconds past the grace deadline (`timer + 30 s`) — that
  /// is the moment the entry actually became late, so the smallest possible
  /// value is 1 s rather than 31 s.
  ///
  /// A null [twist] leaves just the timing half; no timing at all leaves just
  /// the twist; neither leaves an empty string.
  static String caption({
    required String? twist,
    required int? elapsedSeconds,
    required int? timerSeconds,
    required bool isLate,
  }) {
    final parts = <String>[];
    if (twist != null && twist.trim().isNotEmpty) parts.add(twist.trim());

    if (elapsedSeconds != null) {
      if (isLate && timerSeconds != null) {
        final over = elapsedSeconds - timerSeconds - graceSeconds;
        parts.add('LATE by ${over > 0 ? over : 1} s');
      } else {
        parts.add('Done in $elapsedSeconds s');
      }
    }

    return parts.join(' · ');
  }
}
