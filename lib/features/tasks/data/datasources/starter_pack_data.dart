import '../../../../core/models/task.dart';
import '../../../arena/domain/models/feed_post.dart' show Stamps;

/// The Starter Pack: every new player's first game.
///
/// Ten hand-written tasks, in a fixed order, each doable alone, at home, with a
/// phone, in under three minutes — and funny whether you succeed or fail.
///
/// **Round 8: video is the default medium.** Six of the ten are now
/// [SubmissionType.video] and are written so that the *last two seconds are the
/// reveal* — that is the slice the automatic finale montage splices together.
/// Two stay [SubmissionType.text] (wordplay), and two stay
/// [SubmissionType.photo] on purpose, because for those the still IS the joke.
/// The six rewritten VIDEO tasks carry `-v2` ids (`starter-01-v2` …) because
/// the task itself changed: posts made against the old photo copy stay
/// attached to the old id and never surface under the new task. The four
/// unchanged photo/text tasks keep their original ids (and house entries).
///
/// Every task carries the three things the loop needs: a
/// [Task.submissionType] (so the task screen leads with "Film it", "Snap it"
/// or "Write it"), a [Task.rubric] (the one line a crowd grader scores
/// against) and a [Task.twist] (revealed after Start, and the first half of the
/// auto-caption). [Task.taskType] stays [TaskType.video] — that selects the
/// *gameplay engine* (the ordinary submit-and-judge flow), not the medium.
class StarterPackData {
  const StarterPackData._();

  /// The name of the starter game.
  static const String gameName = 'Your First Ten';

  /// Library category every starter task carries.
  static const String category = 'Starter Pack';

  /// Who the seeded house entries are posted as.
  static const String housePosterName = "Greg's assistant";

  /// Where the seeded house clips live in the bucket. Public-read objects with
  /// no download token, so the URL below is stable and shareable.
  static String houseVideoPath(String taskId) => 'house/$taskId.mp4';

  static String houseVideoUrl(String taskId) =>
      'https://firebasestorage.googleapis.com/v0/b/'
      'taskmaster-app-3d480.firebasestorage.app/o/'
      'house%2F$taskId.mp4?alt=media';

  static Task _t({
    required String id,
    required String title,
    required String description,
    required String twist,
    required String rubric,
    required SubmissionType submissionType,
    required int durationSeconds,
    String? gatherTitle,
    String? gatherPrompt,
    int? gatherSeconds,
  }) {
    return Task(
      id: id,
      title: title,
      description: description,
      taskType: TaskType.video,
      category: category,
      submissions: const [],
      submissionType: submissionType,
      rubric: rubric,
      twist: twist,
      durationSeconds: durationSeconds,
      gatherTitle: gatherTitle,
      gatherPrompt: gatherPrompt,
      gatherSeconds: gatherSeconds,
    );
  }

  /// The ten tasks, in play order.
  ///
  /// **The order is the onboarding (WP-05).** Task 1 must be doable in the
  /// next 30 seconds with nothing but a face (the oven selfie), task 2 is a
  /// sit-still text joke, task 3 a photo, and task 4 is the first gather ->
  /// reveal misdirect (gather shapes for 60 s, THEN learn it is a tower).
  /// Ids are deliberately NOT renumbered when the order changes: posts,
  /// montages and the server's STARTER_TASK_IDS (functions/src/contract.js)
  /// key on the id, so only the position moves. A task whose wording changes
  /// gets a new id (`-v3`, or the next free number for a task moved in from
  /// the daily pool) and the old one moves to [retiredTasks]. Starter games
  /// already created keep their old tasks and order (they hold them inline).
  static List<Task> tasks() => [
        _t(
          id: 'starter-09-v3',
          title: 'Selfie: you just remembered the oven is on',
          description:
              'Selfie video. You are a long way from home and you have just '
              'remembered that the oven is on. Let it land on your face '
              'slowly, one stage of panic at a time.',
          twist: 'No hands in the shot, and you may say exactly one word.',
          rubric: 'Stages of panic you could count, then the word.',
          submissionType: SubmissionType.video,
          durationSeconds: 30,
        ),
        _t(
          id: 'starter-03',
          title: 'Rename a household object',
          description:
              'Pick any object in the room. Give it the name it clearly should '
              'have had all along, and a one-line slogan to sell it. Type '
              'both.',
          twist:
              "The name must not contain any part of the object's real name.",
          rubric: 'Would you buy it.',
          submissionType: SubmissionType.text,
          durationSeconds: 60,
        ),
        _t(
          id: 'starter-04',
          title: 'Hide in plain sight',
          description:
              'Take a photo of a room with you in it. The crowd must need at '
              'least three seconds to find you. Being fully hidden is '
              'cheating; that is just a photo of a room.',
          twist: 'Some part of your face must be visible.',
          rubric: 'Seconds to find you, then style points.',
          submissionType: SubmissionType.photo,
          durationSeconds: 120,
        ),
        _t(
          id: 'starter-02-v3',
          title: 'The tallest tower, using only what you gathered',
          description:
              'Build the tallest freestanding tower you can, using only the '
              'things you just gathered. Nothing else from the house. Film '
              'the last three objects going on.',
          twist: 'The last object goes on with one hand, and you must say '
              '"and that\'s the tower" before you let go.',
          rubric: 'Height x how long it stands after you let go.',
          submissionType: SubmissionType.video,
          durationSeconds: 90,
          gatherTitle: 'Gather different shapes',
          gatherPrompt: 'You have 60 s. Gather as many objects with different '
              'shapes or numbers of sides as you can. Go.',
          gatherSeconds: 60,
        ),
        _t(
          id: 'starter-11',
          title: 'The one-star review your sofa would leave you',
          description:
              'Your sofa has been given a voice and an account on a review '
              'site. Write its review of you as an owner. Three sentences at '
              'most.',
          twist: 'It must grudgingly praise exactly one thing about you.',
          rubric: 'How personally attacked you felt reading it.',
          submissionType: SubmissionType.text,
          durationSeconds: 90,
        ),
        _t(
          id: 'starter-06',
          title: 'A famous painting, using only what is within arm\'s reach',
          description:
              'Without moving from where you are, recreate a famous painting '
              'with whatever you can reach. You may be in it. Name the '
              'painting in the caption.',
          twist:
              'No phones or screens in the picture except the one taking it.',
          rubric: 'Could you name the painting before reading the caption.',
          submissionType: SubmissionType.photo,
          durationSeconds: 180,
        ),
        _t(
          id: 'starter-07',
          title: 'A three-line horror story about your fridge',
          description:
              'Write a horror story about your fridge in exactly three lines. '
              'It must be based on something actually in your fridge right '
              'now.',
          twist: 'The last line must be a single word.',
          rubric: 'Chills, then the word.',
          submissionType: SubmissionType.text,
          durationSeconds: 90,
        ),
        _t(
          id: 'starter-12',
          title: 'Win an argument with a door',
          description:
              'A door in your home has had the last word for years. Film the '
              'argument in which you finally win. Make your case out loud.',
          twist:
              "The door may only use its own noises, and it must get the "
              'final creak.',
          rubric: 'Who actually won.',
          submissionType: SubmissionType.video,
          durationSeconds: 90,
        ),
        _t(
          id: 'starter-13',
          title: 'Sell us a glass of tap water',
          description:
              'You are on a shopping channel. You have one product: a glass of '
              'tap water. Sell it like the phone lines are about to close.',
          twist: 'End on the price. It must be alarming.',
          rubric: 'Would you pay it.',
          submissionType: SubmissionType.video,
          durationSeconds: 90,
        ),
        _t(
          id: 'starter-08-v2',
          title: 'Wear as many things on your head as possible',
          description:
              'Balance as many objects as you can on your head. Balanced, not '
              'tied, not held. Film yourself adding them one at a time and '
              'keep filming until they fall.',
          twist: 'Count out loud as each one goes on; the crowd will check.',
          rubric: 'Number of things x your dignity when they go.',
          submissionType: SubmissionType.video,
          durationSeconds: 60,
        ),
      ];

  /// Starter tasks that are no longer dealt to new players (round 9 cut the
  /// egg, the sandwich and the trailer, and rewrote the oven and the tower).
  /// Starter games created before then still hold these tasks inline, and
  /// their posts, montages and share links still key on these ids, so they
  /// must keep resolving: [byId], [allTasks] and the server's
  /// STARTER_TASK_IDS / starter_tasks.js all include them.
  static List<Task> retiredTasks() => [
        _t(
          id: 'starter-09-v2',
          title: 'The face of someone who has just remembered the oven is on '
              '— in another country',
          description:
              'Selfie video. You have just remembered that you left the oven '
              'on. You are currently in a different country. It is 3 a.m. '
              'there. Show us every layer of that realisation arriving, one at '
              'a time.',
          twist: 'No hands in the shot, and you may say exactly one word.',
          rubric: 'Number of distinct regrets visible, then the word.',
          submissionType: SubmissionType.video,
          durationSeconds: 30,
        ),
        _t(
          id: 'starter-10-v2',
          title: 'Your autobiography: the trailer',
          description:
              'Your autobiography is out. Its title is the last thing you said '
              'out loud today. Announce the title, then read the first line of '
              'the book in a movie-trailer voice.',
          twist: 'End on a review quote from a household object, read out loud '
              'in its voice.',
          rubric: 'Would you watch it.',
          submissionType: SubmissionType.video,
          durationSeconds: 30,
        ),
        _t(
          id: 'starter-01-v2',
          title: 'Egg on a spoon, to the far wall and back',
          description:
              'Put an egg (or the roundest thing in your kitchen) on a spoon. '
              'Walk to the farthest wall in the room and back without touching '
              'the egg. Film the whole trip; end on the egg, wherever it ends '
              'up.',
          twist: 'You must narrate it like a nature documentary.',
          rubric: 'Distance covered before disaster, then narration.',
          submissionType: SubmissionType.video,
          durationSeconds: 30,
        ),
        _t(
          id: 'starter-02-v2',
          title:
              'The tallest tower of things that were never meant to be stacked',
          description:
              'Build the tallest freestanding tower you can from objects that '
              'have no business being stacked. Film the last three objects '
              'going on. A shoe must be involved somewhere.',
          twist:
              'The final object goes on with one hand, on camera, and you must '
              'say "and that\'s the tower" before you let go.',
          rubric: 'Height x how long it stands after you let go.',
          submissionType: SubmissionType.video,
          durationSeconds: 60,
        ),
        _t(
          id: 'starter-05-v2',
          title:
              'The worst sandwich that is still technically food — and one bite',
          description:
              'Assemble the worst sandwich you can from what is in your '
              'kitchen. Every ingredient must be edible. Film the assembly, '
              'then take exactly one bite. The clip ends on your face.',
          twist: 'Name every ingredient out loud as it goes on.',
          rubric: 'Horror of the sandwich, then the face.',
          submissionType: SubmissionType.video,
          durationSeconds: 90,
        ),
      ];

  /// Every starter task that has ever been dealt: the current ten, then the
  /// retired ones.
  static List<Task> allTasks() => [...tasks(), ...retiredTasks()];

  /// The starter task with [id] (current or retired), or null.
  static Task? byId(String id) {
    for (final t in allTasks()) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// The task whose seeded clip a video task's house entry 0 plays. A video
  /// task missing from this map gets a TEXT entry 0 instead of a broken
  /// video: new clips are a prod upload (scripts/house_clips/), not a code
  /// change. The v3 oven reuses the v2 clip, because the clip carries only
  /// the house line and a 30 s countdown (never the task title), and both
  /// stayed the same.
  static const Map<String, String> houseClipTaskIds = {
    'starter-09-v3': 'starter-09-v2',
    'starter-08-v2': 'starter-08-v2',
  };

  /// The recurring house personas. [housePosterName] is entry 0 on every task;
  /// these three post the other three takes.
  static const String auntPam = 'Aunt Pam';
  static const String theIntern = 'The Intern';
  static const String daveFromAccounts = 'Dave from Accounts';

  /// The house: four seeded entries per task, so a brand-new player who
  /// unlocks a task sees a small crowd, not a placeholder.
  ///
  /// * Entry 0 is always [housePosterName] with the copy it has always had;
  ///   on a video task with a clip in [houseClipTaskIds] it is that seeded
  ///   clip at [houseVideoPath], otherwise a text post. Its document
  ///   id (`house-<taskId>`) never changes, so the grades it has collected in
  ///   prod survive a re-seed.
  /// * Entries 1-3 are text takes from the recurring personas:
  ///   [auntPam] (earnest, slightly wrong), [theIntern] (overachiever) and
  ///   [daveFromAccounts] (deadpan minimalist), always in that order.
  ///
  /// Each entry carries a stamp (distinct within a task, never ART on a video)
  /// and a starting crowd grade, so the Arena's "the crowd said" reveal has a
  /// number to show from day one.
  ///
  /// The text of a video entry is still written: it becomes the post's
  /// fallback text and shows if the seeded clip is ever unavailable.
  static const Map<String, List<HouseEntry>> houseEntries = {
    'starter-09-v3': [
      HouseEntry(
        posterName: housePosterName,
        text: "Layer 4 was 'the cat is also in the oven'.",
        stamp: Stamps.sendHelp,
        gradeCount: 23,
        gradeSum: 92,
      ),
      HouseEntry(
        posterName: auntPam,
        text: 'I do not have a passport, so I went to my sister\'s in Leeds. '
            'Remembered at 3 a.m. The one word was "Gerald". Gerald is the '
            'oven.',
        stamp: Stamps.dontAsk,
        gradeCount: 11,
        gradeSum: 34,
      ),
      HouseEntry(
        posterName: theIntern,
        text: 'Seventeen layers, colour-coded. Layer 12 is me mentally calling '
            'the Portuguese fire service. I have since learned Portuguese.',
        stamp: Stamps.nailedIt,
        gradeCount: 17,
        gradeSum: 66,
      ),
      HouseEntry(
        posterName: daveFromAccounts,
        text: "One layer. The word was 'oh'.",
        stamp: Stamps.technically,
        gradeCount: 8,
        gradeSum: 21,
      ),
    ],
    'starter-03': [
      HouseEntry(
        posterName: housePosterName,
        text: "The lamp is now The Understudy.\nSlogan: it waits, quietly, for "
            'the sun to fail.',
        stamp: Stamps.art,
        gradeCount: 26,
        gradeSum: 113,
      ),
      HouseEntry(
        posterName: auntPam,
        text: 'The fridge is now The Cold Fridge.\nSlogan: like a fridge, but '
            'you know where you stand.',
        stamp: Stamps.sendHelp,
        gradeCount: 14,
        gradeSum: 33,
      ),
      HouseEntry(
        posterName: theIntern,
        text: 'The stapler is now Commitment.\nSlogan: for when a paperclip '
            "isn't serious enough.\nTrademark filed on my lunch break.",
        stamp: Stamps.nailedIt,
        gradeCount: 19,
        gradeSum: 75,
      ),
      HouseEntry(
        posterName: daveFromAccounts,
        text: 'The chair is now Floor 2.\nSlogan: higher floor.',
        stamp: Stamps.technically,
        gradeCount: 12,
        gradeSum: 44,
      ),
    ],
    'starter-04': [
      HouseEntry(
        posterName: housePosterName,
        text: 'I am in this kitchen. I am the beige one. Take your time, there '
            'is no prize for finding me quickly and there is no prize for me '
            'either.',
        stamp: Stamps.noRegrets,
        gradeCount: 21,
        gradeSum: 80,
      ),
      HouseEntry(
        posterName: auntPam,
        text: 'Found a lovely spot in the airing cupboard and shut the door. '
            'Nobody found me for two hours, so I think I won.',
        stamp: Stamps.sendHelp,
        gradeCount: 9,
        gradeSum: 20,
      ),
      HouseEntry(
        posterName: theIntern,
        text: 'Camouflage rating: 94 per cent. I repainted the bookshelf to '
            'match my cardigan, then wore the cardigan. Left eyebrow, top '
            'shelf, as per the twist.',
        stamp: Stamps.nailedIt,
        gradeCount: 15,
        gradeSum: 62,
      ),
      HouseEntry(
        posterName: daveFromAccounts,
        text: 'I am the coat on the hook. I have been the coat since Tuesday.',
        stamp: Stamps.technically,
        gradeCount: 10,
        gradeSum: 37,
      ),
    ],
    'starter-02-v3': [
      HouseEntry(
        posterName: housePosterName,
        text: 'Gathered a lemon, a die, a hexagonal pencil and a traffic cone '
            'I cannot explain. 31 cm. Stood for two seconds.',
        stamp: Stamps.technically,
        gradeCount: 19,
        gradeSum: 66,
      ),
      HouseEntry(
        posterName: auntPam,
        text: 'I gathered eleven round things because I thought it was a ball '
            'game. The tower was one orange. It stood beautifully.',
        stamp: Stamps.noRegrets,
        gradeCount: 13,
        gradeSum: 43,
      ),
      HouseEntry(
        posterName: theIntern,
        text: 'Fourteen shapes, sorted by number of sides before the reveal, '
            'just in case. Triangle base, sphere on top for drama. 58 cm.',
        stamp: Stamps.nailedIt,
        gradeCount: 16,
        gradeSum: 65,
      ),
      HouseEntry(
        posterName: daveFromAccounts,
        text: "Gathered one cushion. Put it down. And that's the tower.",
        stamp: Stamps.dontAsk,
        gradeCount: 10,
        gradeSum: 33,
      ),
    ],
    'starter-11': [
      HouseEntry(
        posterName: housePosterName,
        text: '★☆☆☆☆ Sits on me for nine hours, then goes to bed. Eats '
            'over me. Loses coins in me as if I were a bank. I will '
            'admit the posture is excellent, because I am doing all '
            'of it.',
        stamp: Stamps.nailedIt,
        gradeCount: 24,
        gradeSum: 97,
      ),
      HouseEntry(
        posterName: auntPam,
        text: '★☆☆☆☆ She talks to me. I am a sofa. She tells me about '
            'Sandra. Grudgingly: lovely cushions, she made them herself.',
        stamp: Stamps.dontAsk,
        gradeCount: 12,
        gradeSum: 40,
      ),
      HouseEntry(
        posterName: theIntern,
        text: '★☆☆☆☆ Sorted my cushions by colour, then by firmness, '
            'then by colour again. Grudgingly: hoovers under me '
            'weekly, with a spreadsheet.',
        stamp: Stamps.technically,
        gradeCount: 13,
        gradeSum: 48,
      ),
      HouseEntry(
        posterName: daveFromAccounts,
        text: '★☆☆☆☆ Sits. Grudgingly: light.',
        stamp: Stamps.noRegrets,
        gradeCount: 9,
        gradeSum: 31,
      ),
    ],
    'starter-06': [
      HouseEntry(
        posterName: housePosterName,
        text: 'The Scream, performed by a tea towel, two grapes, and a man who '
            'cannot quite reach the good props.',
        stamp: Stamps.art,
        gradeCount: 24,
        gradeSum: 99,
      ),
      HouseEntry(
        posterName: auntPam,
        text: 'The Moaning Lisa, by me and a hand towel. My son says that is '
            'not what she is called. Look at her face. She is moaning.',
        stamp: Stamps.noRegrets,
        gradeCount: 12,
        gradeSum: 36,
      ),
      HouseEntry(
        posterName: theIntern,
        text: 'The Last Supper: thirteen mugs, labelled, seating plan to scale. '
            'I could not reach a window, so I am the window.',
        stamp: Stamps.nailedIt,
        gradeCount: 20,
        gradeSum: 84,
      ),
      HouseEntry(
        posterName: daveFromAccounts,
        text: 'Girl with a Pearl Earring. I had a peanut.',
        stamp: Stamps.technically,
        gradeCount: 15,
        gradeSum: 63,
      ),
    ],
    'starter-07': [
      HouseEntry(
        posterName: housePosterName,
        text: 'There are four yoghurts.\nI have bought three yoghurts in my '
            'life.\nThree.',
        stamp: Stamps.sendHelp,
        gradeCount: 28,
        gradeSum: 125,
      ),
      HouseEntry(
        posterName: auntPam,
        text: 'There is a lasagne at the back.\nI do not remember making a '
            'lasagne.\nLovely though.',
        stamp: Stamps.noRegrets,
        gradeCount: 11,
        gradeSum: 37,
      ),
      HouseEntry(
        posterName: theIntern,
        text: 'One lemon, best before 2024.\nI have labelled it, photographed '
            'it and filed a report.\nGrowing.',
        stamp: Stamps.nailedIt,
        gradeCount: 17,
        gradeSum: 67,
      ),
      HouseEntry(
        posterName: daveFromAccounts,
        text: 'Opened it.\nClosed it.\nNo.',
        stamp: Stamps.technically,
        gradeCount: 13,
        gradeSum: 50,
      ),
    ],
    'starter-12': [
      HouseEntry(
        posterName: housePosterName,
        text: 'Forty seconds of excellent points, made with real '
            'passion. The door waited, then closed itself very '
            'slowly. Creak. The door won.',
        stamp: Stamps.sendHelp,
        gradeCount: 22,
        gradeSum: 88,
      ),
      HouseEntry(
        posterName: auntPam,
        text: 'I apologised to the door halfway through, which I think '
            'was a mistake. It creaked in a way I took as '
            'forgiveness. My husband says it was the wind.',
        stamp: Stamps.technically,
        gradeCount: 11,
        gradeSum: 36,
      ),
      HouseEntry(
        posterName: theIntern,
        text: 'Prepared a twelve-slide deck. The door opened on slide four '
            'and let the cat in. Point conceded, minutes taken.',
        stamp: Stamps.nailedIt,
        gradeCount: 15,
        gradeSum: 59,
      ),
      HouseEntry(
        posterName: daveFromAccounts,
        text: "Said 'no'. Door: creak. Fair.",
        stamp: Stamps.dontAsk,
        gradeCount: 8,
        gradeSum: 27,
      ),
    ],
    'starter-13': [
      HouseEntry(
        posterName: housePosterName,
        text: '\'Locally sourced. Hand-poured. Clear as the day it left '
            'the pipe.\' Ninety seconds of charm, then the price: '
            '£2,400, or four easy payments of £900.',
        stamp: Stamps.nailedIt,
        gradeCount: 23,
        gradeSum: 95,
      ),
      HouseEntry(
        posterName: auntPam,
        text: 'Added a slice of lemon to make it posh. Then a teabag. Sold '
            'it as tea for £3. My son says I missed the point.',
        stamp: Stamps.dontAsk,
        gradeCount: 12,
        gradeSum: 39,
      ),
      HouseEntry(
        posterName: theIntern,
        text: 'Tasting notes, a certificate of authenticity and a limited '
            'run of one. Price: my student loan, plus postage.',
        stamp: Stamps.technically,
        gradeCount: 14,
        gradeSum: 52,
      ),
      HouseEntry(
        posterName: daveFromAccounts,
        text: '\'Water.\' Holds up glass. \'Eleven thousand pounds.\'',
        stamp: Stamps.noRegrets,
        gradeCount: 10,
        gradeSum: 38,
      ),
    ],
    'starter-08-v2': [
      HouseEntry(
        posterName: housePosterName,
        text: 'Nine things. The colander was the mistake.',
        stamp: Stamps.dontAsk,
        gradeCount: 20,
        gradeSum: 77,
      ),
      HouseEntry(
        posterName: auntPam,
        text: "Six things and the fascinator from Sandra's wedding. Does the "
            'fascinator count. It is made for heads.',
        stamp: Stamps.technically,
        gradeCount: 11,
        gradeSum: 30,
      ),
      HouseEntry(
        posterName: theIntern,
        text: 'Twenty-three. I trained my neck for this. My neck has a LinkedIn '
            'now.',
        stamp: Stamps.nailedIt,
        gradeCount: 18,
        gradeSum: 74,
      ),
      HouseEntry(
        posterName: daveFromAccounts,
        text: 'One hat. It stayed on.',
        stamp: Stamps.noRegrets,
        gradeCount: 4,
        gradeSum: 9,
      ),
    ],
  };
}

/// One seeded house entry: who posted it, what it says, the stamp it wears and
/// the crowd grade it starts with.
class HouseEntry {
  final String posterName;
  final String text;

  /// One of `Stamps.values`; never `Stamps.art` on a video entry.
  final String stamp;

  /// The starting crowd grade: [gradeSum] / [gradeCount] is the mean shown
  /// before any real player grades it.
  final int gradeCount;
  final int gradeSum;

  const HouseEntry({
    required this.posterName,
    required this.text,
    required this.stamp,
    required this.gradeCount,
    required this.gradeSum,
  });

  double get meanGrade => gradeSum / gradeCount;
}
