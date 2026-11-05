/// Pure share-link + caption building (audit WP-09). No plugin imports, so it
/// is unit-testable without platform channels.
///
/// Every URL here is served by the `sharePage` Cloud Function through the
/// Firebase Hosting rewrites in firebase.json (functions/src/share_page.js),
/// and `/p/`, `/t/`, `/c/` are also claimed as Universal Links / App Links,
/// so on a phone with the app they open the app (InviteLinks.parse routes
/// them) and anywhere else they render a tiny preview page.
library;

import '../invite/invite_link_parser.dart';

class ShareLinks {
  ShareLinks._();

  static const String _base = 'https://${InviteLinks.webHost}';

  /// One Arena attempt, framed as a dare: what "Share your attempt" sends.
  static String challengeUrl(String postId) =>
      '$_base/${InviteLinks.challengeSegment}/${Uri.encodeComponent(postId)}';

  /// One Arena attempt, plain.
  static String postUrl(String postId) =>
      '$_base/${InviteLinks.postSegment}/${Uri.encodeComponent(postId)}';

  /// A public (Starter Pack) task: the cold open on that task.
  static String taskUrl(String taskId, {String? fromPostId}) {
    final from = fromPostId == null || fromPostId.isEmpty
        ? ''
        : '?from=${Uri.encodeQueryComponent(fromPostId)}';
    return '$_base/${InviteLinks.taskSegment}/${Uri.encodeComponent(taskId)}$from';
  }

  /// THE FINALE of a task; [montageId] is `Montage.idFor(gameId, taskId)`.
  static String finaleUrl(String montageId) =>
      '$_base/f/${Uri.encodeComponent(montageId)}';

  /// True for the ten Starter Pack task ids (public by design). Mirrors
  /// `STARTER_TASK_IDS` in functions/src/contract.js via the `starter-` prefix
  /// the montage scope also keys on.
  static bool isPublicTask(String taskId) => taskId.startsWith('starter-');
}

/// The funny line that rides along with a shared link. Deterministic per
/// [seed] (the post id) so a retry shares the same words.
class ShareCaptions {
  ShareCaptions._();

  static const List<String> _attempt = [
    'I did this in {t}. Your turn — the clock starts when your camera opens.',
    'Judged by strangers. Beat me: {task}',
    'This is my best work and I am not okay. Your turn:',
    'Bet you can\'t do worse. (You can. Try it.)',
    'I had {t}. I used all of it. Your turn:',
  ];

  static const List<String> _finale = [
    'Every attempt. The last two seconds of each. I can\'t stop watching.',
    'THE FINALE dropped. Somebody please explain the third one.',
    'We were given one task. This is how it ended.',
  ];

  static String forAttempt({
    required String seed,
    required String taskTitle,
    int? elapsedSeconds,
    String? stamp,
  }) {
    final template = _attempt[_pick(seed, _attempt.length)];
    final t = elapsedSeconds == null ? 'one go' : '$elapsedSeconds s';
    final line = template
        .replaceAll('{t}', t)
        .replaceAll('{task}', _shorten(taskTitle, 70));
    return stamp == null || stamp.isEmpty ? line : '$stamp. $line';
  }

  static String forFinale({required String seed, required String taskTitle}) {
    final line = _finale[_pick(seed, _finale.length)];
    return taskTitle.isEmpty ? line : '$line\n"${_shorten(taskTitle, 80)}"';
  }

  static int _pick(String seed, int n) {
    var h = 0;
    for (final c in seed.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h % n;
  }

  static String _shorten(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max - 1).trimRight()}…';
}
