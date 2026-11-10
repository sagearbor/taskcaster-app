import '../../arena/domain/models/feed_post.dart';

/// Greg's assistant reacts to your entry on the Posted screen (fun audit
/// WP-5): one dry line under the polaroid, so the first laugh after posting
/// is guaranteed instead of left to whatever happens to be in the Arena.
///
/// Canned and client-side on purpose. It is the house voice, never a grade:
/// the lines comment on the stamp (how the attempt went) or on the task, and
/// never on the quality of the entry, which the app cannot see. A future
/// `AITaskService` could replace [pick]; nothing else needs to change.
///
/// Copy rules: second person, short, dry, no exclamation marks.
class HouseReactions {
  const HouseReactions._();

  /// Who is speaking. Rendered as the label in front of the line.
  static const String speaker = "Greg's assistant";

  /// Lines per stamp. Every value of [Stamps.values] has at least six.
  static const Map<String, List<String>> byStamp = {
    Stamps.nailedIt: [
      'Fast. Suspiciously fast. Greg has asked me to check your pockets.',
      'Done with time to spare. Greg finds this unsettling and has gone for '
          'a lie down.',
      "Efficient. I have written 'efficient' on a card and underlined it "
          'twice.',
      'You finished before I had found my pen.',
      'A clean attempt. I have nothing to add, which is a first for me.',
      'Greg says it is too early to be impressed. I am impressed on his '
          'behalf.',
      'Quick and correct. I will be telling my mother about this.',
      'Under a third of the time. I have stopped the stopwatch. And, '
          'briefly, my heart.',
    ],
    Stamps.technically: [
      'Within the rules. Only just. Greg is consulting a lawyer.',
      "The clock says yes. Everything else says 'we'll see'.",
      'I checked the rules twice. You are, annoyingly, fine.',
      'A photo finish. I have the photo. I wish I did not.',
      'Legal, in the way a car with one wheel in the space is parked.',
      'You used all of the time, and some of mine.',
      'Greg asked me to find a loophole. I found you instead.',
      'Submitted with seconds to spare. The seconds would like a word.',
    ],
    Stamps.sendHelp: [
      'Late. I have marked it in red, which is the only pen I brought.',
      'The clock ran out. You did not. Admirable. Also against the rules.',
      'Greg has been waiting. He has aged. We all have.',
      'It arrived after the deadline, like a lot of good things and most '
          'bad ones.',
      'Late, but here. That is more than can be said for the deadline.',
      'I have sent help. Help is also late.',
      'You were given a time limit. You treated it as a suggestion. Noted, '
          'in ink.',
    ],
    Stamps.art: [
      'Greg does not understand it, which, legally, makes it art.',
      'I have hung this in the corridor. Someone has already walked past it '
          'slowly.',
      'Bold. Considered. Possibly a cry for help. Art.',
      'I read it twice. The second time was worse, in a good way.',
      'Greg asked what it means. I told him it means whatever he is afraid '
          'of.',
      'This would sell for millions to someone who had lost a bet.',
      'There is a lot going on here. Most of it on purpose.',
    ],
    Stamps.noRegrets: [
      'You did it. Whether you should have is a question for a later, '
          'quieter time.',
      'No regrets. Greg has several, on your behalf.',
      'That is an attempt. It is definitely an attempt. I checked.',
      'Committed. Fully. Slightly too fully.',
      'You have done a thing and it cannot be undone. I have saved a copy.',
      'Bold choices were made. I have written them all down.',
      'It is on the record now. The record has gone quiet.',
    ],
    Stamps.dontAsk: [
      'I asked. I wish I had not.',
      'People keep tapping this. I have stopped asking why.',
      'Greg has asked me not to ask. I am not asking.',
      'Some things are better left unexplained. This is all of them.',
      'I have a question. I am going to keep it.',
      'The crowd has seen it. The crowd is not ready to talk about it.',
    ],
  };

  /// Task-specific lines for the ten Starter Pack tasks, keyed by task id
  /// (see `StarterPackData.tasks`). These do not depend on the stamp.
  static const Map<String, List<String>> byTask = {
    // The oven face, in another country.
    'starter-09-v2': [
      'I counted the layers of realisation. I got to six, then I also '
          'remembered the oven.',
      'That face has crossed a border. The oven has not.',
      'Greg has phoned your oven. It is fine. It is lonely.',
    ],
    // Rename a household object.
    'starter-03': [
      'A strong rebrand. The object has been told and is taking it well.',
      'I would buy it. I would then return it, but I would buy it.',
      'I have relabelled my own kettle. Greg says I am not allowed to do '
          'that at work.',
    ],
    // Hide in plain sight.
    'starter-04': [
      'I found you in two seconds. Greg is still looking. Do not tell him.',
      'Greg found the lamp before he found you. He is very pleased with the '
          'lamp.',
      'I have circled you in pen. I have also circled a cushion, just in '
          'case.',
    ],
    // Your autobiography: the trailer.
    'starter-10-v2': [
      'In a world where nobody asked, one person made a trailer.',
      'Greg would watch it. Greg would also leave halfway through for '
          'snacks.',
      "The household object's review has been verified. It stands by every "
          'word.',
    ],
    // A famous painting, from arm's reach.
    'starter-06': [
      'The gallery has been informed. They have asked us to stop informing '
          'them.',
      'I recognised it immediately. I will not say as what. I will wait for '
          'the caption.',
      'Somewhere a curator has felt a cold draught and does not know why.',
    ],
    // Egg on a spoon.
    'starter-01-v2': [
      'The egg has been told its result. It took it better than the floor '
          'did.',
      'A nature documentary in which the endangered species was the egg.',
      'I measured the distance in my own feet. I am not saying whose feet.',
    ],
    // A three-line horror story about your fridge.
    'starter-07': [
      'I have opened my own fridge since reading this. I have closed it '
          'again.',
      'Greg has moved his lunch to a different fridge. In a different '
          'building.',
      'Three lines. One word. I am sleeping with the light on.',
    ],
    // The tallest tower of unstackable things.
    'starter-02-v2': [
      'The shoe was the hero. The shoe is always the hero.',
      'An architect would call this ambitious. An engineer would call it a '
          'witness statement.',
      'I measured it before and during the collapse. Both count.',
    ],
    // The worst sandwich, and one bite.
    'starter-05-v2': [
      'Technically food. Spiritually, a cry for help.',
      'Greg has asked for the recipe so he can make sure nobody ever makes '
          'it.',
      'I watched you take the bite. A small part of me took it too.',
    ],
    // As many things on your head as possible.
    'starter-08-v2': [
      'I counted along. We disagree about the hat. The hat knows what it '
          'did.',
      'Your dignity left before the first object did. It was the right call.',
      'Greg has added this to his list of things heads are not for.',
    ],
  };

  /// The line for one post. Deterministic in ([postId], [stamp], [taskId]):
  /// the same post always gets the same line, on every device and platform
  /// (it hashes with FNV-1a, not `String.hashCode`, which differs between the
  /// Dart VM and the web).
  ///
  /// A starter task's own lines win two times in three; otherwise the line
  /// comes from the stamp's bucket. An unknown or missing stamp reads as
  /// `NO REGRETS`.
  static String pick({
    required String postId,
    required String? stamp,
    String? taskId,
  }) {
    final bucketKey =
        (stamp != null && byStamp.containsKey(stamp)) ? stamp : Stamps.noRegrets;
    final h = _fnv1a('$postId|$bucketKey|${taskId ?? ''}');
    final specials = taskId == null ? null : byTask[taskId];
    if (specials != null && specials.isNotEmpty && h % 3 != 0) {
      return specials[(h ~/ 3) % specials.length];
    }
    final lines = byStamp[bucketKey]!;
    return lines[(h ~/ 3) % lines.length];
  }

  /// 32-bit FNV-1a over UTF-16 code units, kept positive and below 2^31 so
  /// it behaves identically when compiled to JavaScript.
  static int _fnv1a(String s) {
    var h = 0x811c9dc5;
    for (final unit in s.codeUnits) {
      h ^= unit;
      // h * 0x01000193, split so no intermediate passes 2^53 (JS doubles).
      h = (((h << 24) & 0xffffffff) + h * 0x193) & 0xffffffff;
    }
    return h & 0x7fffffff;
  }
}
