import '../../../../core/models/task.dart';
import '../../../arena/domain/models/feed_post.dart' show Stamps;
import 'starter_pack_data.dart' show HouseEntry, StarterPackData;

/// The Daily Task (WP-6): one task a day, the same for everyone on Earth.
///
/// Thirty hand-written solo tasks. Each is doable alone, indoors, in two
/// minutes, with nothing more exotic than what is already in a kitchen
/// drawer, and each carries a twist that makes the obvious answer wrong.
/// Mostly photo and text (they are quick, and they read well in a feed),
/// with eight video tasks written so the last two seconds are the reveal.
///
/// **The day is the UTC date.** One global task per day keeps every player's
/// entry on one task id, so the Arena for that id fills up. Posting unlocks
/// the other entries exactly as it does for the Starter Pack (by task id).
///
/// Ids are `daily-01` .. `daily-30` and are never renumbered: posts key on
/// them. To retire a task, replace it under a NEW id (as the starter pack did
/// with its `-v2` ids) so old posts stay attached to the old wording.
class DailyTaskData {
  const DailyTaskData._();

  /// Library category every daily task carries.
  static const String category = 'Daily';

  /// Prefix of every daily task id, and of every daily game id.
  static const String taskIdPrefix = 'daily-';
  static const String gameIdPrefix = 'daily_';

  /// Offset into the pool, so launch day does not start on task 1 by accident
  /// of the epoch. Changing it reshuffles which task falls on which day for
  /// everyone at once, which is harmless, but do not change it mid-day.
  static const int poolOffset = 7;

  static Task _t({
    required String id,
    required String title,
    required String description,
    required String twist,
    required String rubric,
    required SubmissionType submissionType,
    required int durationSeconds,
  }) {
    return Task(
      id: id,
      title: title,
      description: description,
      // The gameplay engine (ordinary submit-and-judge), not the medium.
      taskType: TaskType.video,
      category: category,
      submissions: const [],
      submissionType: submissionType,
      rubric: rubric,
      twist: twist,
      durationSeconds: durationSeconds,
    );
  }

  /// The thirty tasks, in rotation order.
  static List<Task> tasks() => [
        _t(
          id: 'daily-01',
          title: 'Photograph the most suspicious object in your home',
          description:
              'Somewhere near you is an object that is clearly up to '
              'something. Find it. Photograph it so the crowd can feel it too.',
          twist:
              'Shoot it from below, as if it is about to address a rally.',
          rubric: 'How much you no longer trust it.',
          submissionType: SubmissionType.photo,
          durationSeconds: 90,
        ),
        _t(
          id: 'daily-02',
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
          id: 'daily-03',
          title: 'Introduce your left hand to your right hand',
          description:
              'Your hands have never formally met. Film the introduction. '
              'They should be polite, but wary.',
          twist:
              'One of them is hiding something and reveals it in the last '
              'two seconds.',
          rubric: 'Chemistry, then the secret.',
          submissionType: SubmissionType.video,
          durationSeconds: 60,
        ),
        _t(
          id: 'daily-04',
          title: 'A crime scene that fits on a plate',
          description:
              'Stage a crime scene on a single plate using whatever is in '
              'your kitchen. The victim and the suspect must both be present. '
              'Photograph it for the jury.',
          twist: 'The murder weapon must be something you would eat.',
          rubric: 'Could you name the culprit.',
          submissionType: SubmissionType.photo,
          durationSeconds: 120,
        ),
        _t(
          id: 'daily-05',
          title: 'Explain your job to a medieval peasant',
          description:
              'Describe what you do all day (job, school or neither) to '
              'someone from the year 1300. Two sentences.',
          twist:
              'No word invented after 1300. The crowd will check, badly.',
          rubric: 'Would the peasant have you burned.',
          submissionType: SubmissionType.text,
          durationSeconds: 90,
        ),
        _t(
          id: 'daily-06',
          title: 'Make the cheapest thing you own look expensive',
          description:
              'Find the cheapest-looking object in reach. Photograph it as '
              'the hero of a luxury-watch advert.',
          twist: 'Something in the shot must be dramatically out of focus, '
              'and it must not be the object.',
          rubric: 'What you would pay for it now.',
          submissionType: SubmissionType.photo,
          durationSeconds: 120,
        ),
        _t(
          id: 'daily-07',
          title: 'Win an argument with a door',
          description:
              'A door in your home has had the last word for years. Film the '
              'argument in which you finally win.',
          twist:
              "The door may only use its own noises, and it must get the "
              'final creak.',
          rubric: 'Who actually won.',
          submissionType: SubmissionType.video,
          durationSeconds: 90,
        ),
        _t(
          id: 'daily-08',
          title: 'A fairy-tale character sets an out-of-office reply',
          description:
              'Pick any fairy-tale character. Write the out-of-office email '
              'they set before the story starts. Under 50 words.',
          twist:
              'It must give an alternative contact who is clearly a worse '
              'option.',
          rubric: 'Would you email the alternative contact.',
          submissionType: SubmissionType.text,
          durationSeconds: 120,
        ),
        _t(
          id: 'daily-09',
          title: 'A formal portrait of you and a sock',
          description:
              'Take the kind of portrait that hangs in a stately home. You '
              'are in it. So is a sock, and the sock is important.',
          twist: 'You must look away from the camera. The sock must not.',
          rubric: 'Your dignity, then the sock\'s.',
          submissionType: SubmissionType.photo,
          durationSeconds: 90,
        ),
        _t(
          id: 'daily-10',
          title: 'The view from your window is an album cover',
          description:
              'Look out of the nearest window. That is the cover. Name the '
              'band, the album, and track one.',
          twist: 'Track one must be a complaint.',
          rubric: 'Would you listen past track one.',
          submissionType: SubmissionType.text,
          durationSeconds: 60,
        ),
        _t(
          id: 'daily-11',
          title: 'A dramatic reading of an ingredients list',
          description:
              'Take any packet from your kitchen. Read its ingredients aloud '
              'as the final speech of a dying king.',
          twist: 'You must weep on the last ingredient. Real tears optional; '
              'commitment is not.',
          rubric: 'Grief per ingredient.',
          submissionType: SubmissionType.video,
          durationSeconds: 90,
        ),
        _t(
          id: 'daily-12',
          title: 'An audience of objects hears something shocking',
          description:
              'Line up at least six objects, all facing one thing that has '
              'just said something unforgivable. Photograph the moment it '
              'lands.',
          twist: 'One member of the audience has clearly already left.',
          rubric: 'How bad was the thing they heard.',
          submissionType: SubmissionType.photo,
          durationSeconds: 120,
        ),
        _t(
          id: 'daily-13',
          title: 'The fortune cookie that should never have been opened',
          description:
              'Write the slip of paper inside a fortune cookie that should '
              'have stayed shut. One sentence.',
          twist:
              'It must include lucky numbers, and one of them must be '
              'negative.',
          rubric: 'How long it would ruin your day.',
          submissionType: SubmissionType.text,
          durationSeconds: 60,
        ),
        _t(
          id: 'daily-14',
          title: 'Silent film: you have lost your keys',
          description:
              'Act out losing your keys as a silent film. No words. Big '
              'eyebrows. End on the keys, wherever they turn up.',
          twist:
              'You must search at least one place that could not possibly '
              'hold keys, and search it thoroughly.',
          rubric: 'Eyebrow work, then where they were.',
          submissionType: SubmissionType.video,
          durationSeconds: 90,
        ),
        _t(
          id: 'daily-15',
          title: 'A self-portrait made of laundry',
          description:
              'Arrange clothes on a bed or the floor into a portrait of your '
              'face. Photograph it from above.',
          twist: 'Your nose must be made of something that is not clothing.',
          rubric: 'Would your family recognise you.',
          submissionType: SubmissionType.photo,
          durationSeconds: 120,
        ),
        _t(
          id: 'daily-16',
          title: 'Warn your past self about something that does not matter',
          description:
              'You can send one text to yourself ten years ago. Use it to warn '
              'them about something completely unimportant.',
          twist: 'It must sound like the fate of the world depends on it.',
          rubric: 'How little it matters x how urgent it sounds.',
          submissionType: SubmissionType.text,
          durationSeconds: 60,
        ),
        _t(
          id: 'daily-17',
          title: 'Three objects that are disappointed in you',
          description:
              'Arrange three ordinary objects into a face. It is a face that '
              'expected more of you. Photograph it.',
          twist: 'None of the three may be round.',
          rubric: 'How disappointed it looks.',
          submissionType: SubmissionType.photo,
          durationSeconds: 90,
        ),
        _t(
          id: 'daily-18',
          title: 'Sell us a glass of tap water',
          description:
              'You are on a shopping channel. You have one product: a glass of '
              'tap water. Sell it.',
          twist: 'End on the price. It must be alarming.',
          rubric: 'Would you pay it.',
          submissionType: SubmissionType.video,
          durationSeconds: 90,
        ),
        _t(
          id: 'daily-19',
          title: 'A haiku from whatever lives under your bed',
          description:
              'Look under your bed, or your sofa. Write a haiku (5-7-5) from '
              'the point of view of what is down there.',
          twist:
              'It must call you by a nickname you have never been called.',
          rubric: 'How unsettled you are, then the nickname.',
          submissionType: SubmissionType.text,
          durationSeconds: 90,
        ),
        _t(
          id: 'daily-20',
          title: 'Adopt a pet from one kitchen drawer',
          description:
              'Build a pet from the contents of a single drawer. Photograph '
              'the two of you at your closest.',
          twist: 'It must be doing something it has clearly been told not to.',
          rubric: 'Would you take it to the vet.',
          submissionType: SubmissionType.photo,
          durationSeconds: 120,
        ),
        _t(
          id: 'daily-21',
          title: "The world's slowest magic trick",
          description:
              'Perform a magic trick with a coin or a spoon. Build the '
              'tension for as long as you can. The reveal is the last two '
              'seconds.',
          twist: 'The trick must not quite work, and you must act as if it '
              'did.',
          rubric: 'Tension built, then how badly it failed.',
          submissionType: SubmissionType.video,
          durationSeconds: 120,
        ),
        _t(
          id: 'daily-22',
          title: 'Your last text message, by Shakespeare',
          description:
              'Take the last message you sent anyone. Rewrite it as a line '
              'from a Shakespeare play.',
          twist: 'It must end with a stage direction.',
          rubric: 'Drama added per word.',
          submissionType: SubmissionType.text,
          durationSeconds: 90,
        ),
        _t(
          id: 'daily-23',
          title: 'Prove you are on a beach',
          description:
              'Without leaving home, take a photo that would convince your '
              'boss you are on holiday somewhere hot.',
          twist:
              'One detail must give the game away to anyone who looks '
              'closely.',
          rubric: 'How convinced, then how quickly you spotted it.',
          submissionType: SubmissionType.photo,
          durationSeconds: 120,
        ),
        _t(
          id: 'daily-24',
          title: 'Teach us a dance move you invented just now',
          description:
              'Invent a dance move, name it, and teach it in three steps. '
              'Finish by doing it at full speed.',
          twist: 'It must be based on a household chore you are avoiding.',
          rubric: 'Would it clear a wedding dance floor, or fill one.',
          submissionType: SubmissionType.video,
          durationSeconds: 90,
        ),
        _t(
          id: 'daily-25',
          title: 'The warning label that should come with you',
          description:
              'Write the warning label printed on your packaging. Three '
              'short warnings.',
          twist: 'One of the three must be storage instructions.',
          rubric: 'Would you still take one home.',
          submissionType: SubmissionType.text,
          durationSeconds: 90,
        ),
        _t(
          id: 'daily-26',
          title: 'A film poster, starring a pillow',
          description:
              'Recreate any famous film poster. A pillow plays the lead. '
              'Photograph the poster.',
          twist: "You must play the pillow's love interest.",
          rubric: 'Could you name the film, then the chemistry.',
          submissionType: SubmissionType.photo,
          durationSeconds: 120,
        ),
        _t(
          id: 'daily-27',
          title: 'The most passive-aggressive fridge note ever written',
          description:
              'Write a note for a shared fridge about something nobody did. '
              'Under 30 words.',
          twist: 'It must be signed by an appliance.',
          rubric: 'How badly you would want to move out.',
          submissionType: SubmissionType.text,
          durationSeconds: 60,
        ),
        _t(
          id: 'daily-28',
          title: 'Sell the room you are in, as a desperate estate agent',
          description:
              'Give us a tour of the room you are sitting in, as an estate '
              'agent who needs this sale more than anything.',
          twist:
              'Sell one obvious flaw as a feature, and end the clip on it.',
          rubric: 'What you would offer, then the flaw.',
          submissionType: SubmissionType.video,
          durationSeconds: 120,
        ),
        _t(
          id: 'daily-29',
          title: 'An object having the worst day of its life',
          description:
              'Find an object that is clearly having a terrible day. Help it '
              'look the part, then take its photo.',
          twist: 'It must still be bravely trying.',
          rubric: 'Sympathy felt.',
          submissionType: SubmissionType.photo,
          durationSeconds: 90,
        ),
        _t(
          id: 'daily-30',
          title: 'Accept an award for the most ordinary thing you did today',
          description:
              'You have won a major award for something entirely ordinary you '
              'did today. Write the acceptance speech. Two sentences.',
          twist: 'You must thank someone who actively made it harder.',
          rubric: 'Gratitude, then the grudge.',
          submissionType: SubmissionType.text,
          durationSeconds: 90,
        ),
      ];

  // ---- House entries -----------------------------------------------------

  /// Two seeded house entries per daily task, so the first player of the day
  /// who unlocks it sees a small crowd rather than an empty Arena.
  ///
  /// Entry 0 is always [StarterPackData.housePosterName]; entry 1 rotates
  /// through the starter pack's personas by task number: daily-01 is
  /// [StarterPackData.auntPam], daily-02 [StarterPackData.theIntern],
  /// daily-03 [StarterPackData.daveFromAccounts], and round again. Every
  /// daily house entry is a TEXT post, video tasks included (there are no
  /// seeded clips for the daily pool).
  ///
  /// Seeded on Firestore by functions/scripts/seed_house_posts.js from
  /// functions/scripts/house_posts.json, which
  /// test/features/arena/data/house_posts_seed_test.dart keeps in step.
  static const Map<String, List<HouseEntry>> houseEntries = {
    'daily-01': [
      HouseEntry(
        posterName: StarterPackData.housePosterName,
        text: 'The toaster. Shot from below, it looks ready to promise '
            'lower taxes and deliver crumbs.',
        stamp: Stamps.art,
        gradeCount: 21,
        gradeSum: 86,
      ),
      HouseEntry(
        posterName: StarterPackData.auntPam,
        text: 'I photographed the cat from below. She was not '
            'addressing a rally. She was addressing me, and I have '
            'agreed to her terms.',
        stamp: Stamps.dontAsk,
        gradeCount: 9,
        gradeSum: 29,
      ),
    ],
    'daily-02': [
      HouseEntry(
        posterName: StarterPackData.housePosterName,
        text: '★☆☆☆☆ Sits on me for nine hours, then goes to bed. Eats '
            'over me. Loses coins in me as if I were a bank. I will '
            'admit the posture is excellent, because I am doing all '
            'of it.',
        stamp: Stamps.nailedIt,
        gradeCount: 24,
        gradeSum: 97,
      ),
      HouseEntry(
        posterName: StarterPackData.theIntern,
        text: '★☆☆☆☆ Sorted my cushions by colour, then by firmness, '
            'then by colour again. Grudgingly: hoovers under me '
            'weekly, with a spreadsheet.',
        stamp: Stamps.technically,
        gradeCount: 13,
        gradeSum: 48,
      ),
    ],
    'daily-03': [
      HouseEntry(
        posterName: StarterPackData.housePosterName,
        text: 'Left: \'Charmed.\' Right: \'Likewise.\' Two seconds from the '
            'end the right hand opens. It has been holding the remote '
            'this whole time.',
        stamp: Stamps.sendHelp,
        gradeCount: 19,
        gradeSum: 74,
      ),
      HouseEntry(
        posterName: StarterPackData.daveFromAccounts,
        text: 'They shook. The secret was that they are the same '
            'person.',
        stamp: Stamps.noRegrets,
        gradeCount: 7,
        gradeSum: 19,
      ),
    ],
    'daily-04': [
      HouseEntry(
        posterName: StarterPackData.housePosterName,
        text: 'Victim: one fish finger, face down in ketchup. Suspect: '
            'the other fish finger, still warm. Weapon: a breadstick, '
            'half eaten. He destroyed the evidence the only way he '
            'knew how.',
        stamp: Stamps.art,
        gradeCount: 22,
        gradeSum: 91,
      ),
      HouseEntry(
        posterName: StarterPackData.auntPam,
        text: 'Victim: a grape. Suspect: another grape. I could not '
            'tell them apart afterwards, so I let them both go. The '
            'weapon was a biscuit and I ate it to be safe.',
        stamp: Stamps.dontAsk,
        gradeCount: 10,
        gradeSum: 31,
      ),
    ],
    'daily-05': [
      HouseEntry(
        posterName: StarterPackData.housePosterName,
        text: 'I sit before a glowing slate and move small words from '
            'one box into another box. The lord pays me in coin and '
            'in meetings.',
        stamp: Stamps.technically,
        gradeCount: 18,
        gradeSum: 69,
      ),
      HouseEntry(
        posterName: StarterPackData.theIntern,
        text: 'I am a scribe of the counting house, keeper of the great '
            'ledger. I have written the same letter four times '
            'because the abbot changed his mind. I also make the '
            'abbot\'s ale.',
        stamp: Stamps.nailedIt,
        gradeCount: 15,
        gradeSum: 58,
      ),
    ],
    'daily-06': [
      HouseEntry(
        posterName: StarterPackData.housePosterName,
        text: 'A single paperclip on black velvet (a sock). The blur in '
            'the foreground is my thumb, which the crowd has agreed '
            'is couture.',
        stamp: Stamps.art,
        gradeCount: 20,
        gradeSum: 83,
      ),
      HouseEntry(
        posterName: StarterPackData.daveFromAccounts,
        text: 'A teabag. The blur is the rest of my life.',
        stamp: Stamps.noRegrets,
        gradeCount: 11,
        gradeSum: 40,
      ),
    ],
    'daily-07': [
      HouseEntry(
        posterName: StarterPackData.housePosterName,
        text: 'Forty seconds of excellent points, made with real '
            'passion. The door waited, then closed itself very '
            'slowly. Creak. The door won.',
        stamp: Stamps.sendHelp,
        gradeCount: 21,
        gradeSum: 80,
      ),
      HouseEntry(
        posterName: StarterPackData.auntPam,
        text: 'I apologised to the door halfway through, which I think '
            'was a mistake. It creaked in a way I took as '
            'forgiveness. My husband says it was the wind.',
        stamp: Stamps.technically,
        gradeCount: 9,
        gradeSum: 27,
      ),
    ],
    'daily-08': [
      HouseEntry(
        posterName: StarterPackData.housePosterName,
        text: 'Little Red Riding Hood is visiting her grandmother and '
            'has no signal in the woods. For anything urgent, please '
            'contact Grandmother, who has been acting strangely and '
            'has very big ears.',
        stamp: Stamps.nailedIt,
        gradeCount: 26,
        gradeSum: 108,
      ),
      HouseEntry(
        posterName: StarterPackData.theIntern,
        text: 'Rapunzel is out of the tower until further notice. For '
            'access requests, contact the witch. I have attached an '
            'FAQ, an org chart and a ladder.',
        stamp: Stamps.dontAsk,
        gradeCount: 12,
        gradeSum: 45,
      ),
    ],
    'daily-09': [
      HouseEntry(
        posterName: StarterPackData.housePosterName,
        text: 'The lord of the house gazes into the middle distance. '
            'The sock, his heir, stares straight down the lens, as if '
            'it already knows about the will.',
        stamp: Stamps.art,
        gradeCount: 23,
        gradeSum: 95,
      ),
      HouseEntry(
        posterName: StarterPackData.daveFromAccounts,
        text: 'Me, looking at the wall. The sock, looking at you. It '
            'has been like that since Tuesday.',
        stamp: Stamps.technically,
        gradeCount: 8,
        gradeSum: 23,
      ),
    ],
    'daily-10': [
      HouseEntry(
        posterName: StarterPackData.housePosterName,
        text: 'Band: The Neighbour\'s Bins. Album: Wednesday, Probably. '
            'Track one: \'Who Parks Like That\'.',
        stamp: Stamps.nailedIt,
        gradeCount: 22,
        gradeSum: 88,
      ),
      HouseEntry(
        posterName: StarterPackData.auntPam,
        text: 'Band: A Lovely Tree. Album: Nice Day for It. Track one: '
            '\'The Gutter Wants Doing (and You Said You Would Do It in '
            'March)\'.',
        stamp: Stamps.noRegrets,
        gradeCount: 10,
        gradeSum: 34,
      ),
    ],
    'daily-11': [
      HouseEntry(
        posterName: StarterPackData.housePosterName,
        text: '\'Wheat flour... palm oil... sugar...\' He made it as far '
            'as \'emulsifier E471\' before collapsing. The last '
            'ingredient was salt, and so were the tears.',
        stamp: Stamps.sendHelp,
        gradeCount: 20,
        gradeSum: 79,
      ),
      HouseEntry(
        posterName: StarterPackData.theIntern,
        text: 'Read all 34 ingredients of a stock cube in a cape. Wept '
            'on cue at \'yeast extract\'. Also did the French side, '
            'unprompted.',
        stamp: Stamps.nailedIt,
        gradeCount: 14,
        gradeSum: 55,
      ),
    ],
    'daily-12': [
      HouseEntry(
        posterName: StarterPackData.housePosterName,
        text: 'Six mugs turned towards the kettle, which has just '
            'admitted it never liked tea. A gap in the second row '
            'where a seventh mug walked out.',
        stamp: Stamps.art,
        gradeCount: 19,
        gradeSum: 77,
      ),
      HouseEntry(
        posterName: StarterPackData.daveFromAccounts,
        text: 'Six forks facing the calculator. One fork has gone home.',
        stamp: Stamps.dontAsk,
        gradeCount: 9,
        gradeSum: 30,
      ),
    ],
    'daily-13': [
      HouseEntry(
        posterName: StarterPackData.housePosterName,
        text: 'You will finally find what you were looking for, and it '
            'will be smaller than you remember. Lucky numbers: 4, 11, '
            '-2, 38.',
        stamp: Stamps.technically,
        gradeCount: 21,
        gradeSum: 83,
      ),
      HouseEntry(
        posterName: StarterPackData.auntPam,
        text: 'A stranger will bring you news of a parcel. Do not let '
            'them in. Lucky numbers: 7, 14, -1 (this is your bank '
            'balance, dear).',
        stamp: Stamps.noRegrets,
        gradeCount: 11,
        gradeSum: 36,
      ),
    ],
    'daily-14': [
      HouseEntry(
        posterName: StarterPackData.housePosterName,
        text: 'Eyebrows to the ceiling. Searched the fridge, the bread '
            'bin and, very thoroughly, the inside of a single grape. '
            'The keys were in the door the whole time.',
        stamp: Stamps.sendHelp,
        gradeCount: 24,
        gradeSum: 94,
      ),
      HouseEntry(
        posterName: StarterPackData.theIntern,
        text: 'Four acts, title cards, a piano score I hummed myself. '
            'Searched the freezer drawer by drawer. The keys were in '
            'my hand, which was the twist I set up in act one.',
        stamp: Stamps.nailedIt,
        gradeCount: 13,
        gradeSum: 51,
      ),
    ],
    'daily-15': [
      HouseEntry(
        posterName: StarterPackData.housePosterName,
        text: 'Jeans for a jaw, a striped jumper for hair and a satsuma '
            'for a nose. Mother says the likeness is uncanny. Mother '
            'has not called since.',
        stamp: Stamps.art,
        gradeCount: 22,
        gradeSum: 90,
      ),
      HouseEntry(
        posterName: StarterPackData.daveFromAccounts,
        text: 'Grey T-shirt. Grey T-shirt. Remote control for a nose. '
            'It is me.',
        stamp: Stamps.technically,
        gradeCount: 10,
        gradeSum: 33,
      ),
    ],
    'daily-16': [
      HouseEntry(
        posterName: StarterPackData.housePosterName,
        text: 'Listen carefully. In 2019 you will be offered the middle '
            'seat on a train to Didcot. Do not take it. Stand. '
            'Everything depends on this.',
        stamp: Stamps.noRegrets,
        gradeCount: 20,
        gradeSum: 82,
      ),
      HouseEntry(
        posterName: StarterPackData.auntPam,
        text: 'Darling, the blue Tupperware lid does not fit the blue '
            'Tupperware. It never will. Buy the green one. Tell no '
            'one I contacted you.',
        stamp: Stamps.dontAsk,
        gradeCount: 12,
        gradeSum: 41,
      ),
    ],
    'daily-17': [
      HouseEntry(
        posterName: StarterPackData.housePosterName,
        text: 'Two clothes pegs for eyebrows and a fork for a mouth, '
            'angled down. It looks at me the way my driving '
            'instructor did.',
        stamp: Stamps.art,
        gradeCount: 21,
        gradeSum: 85,
      ),
      HouseEntry(
        posterName: StarterPackData.theIntern,
        text: 'Twelve iterations. Final face: two USB sticks and a '
            'bookmark, mouth at precisely 14 degrees of '
            'disappointment. I asked it for feedback. It had some.',
        stamp: Stamps.technically,
        gradeCount: 11,
        gradeSum: 39,
      ),
    ],
    'daily-18': [
      HouseEntry(
        posterName: StarterPackData.housePosterName,
        text: '\'Locally sourced. Hand-poured. Clear as the day it left '
            'the pipe.\' Ninety seconds of charm, then the price: '
            '£2,400, or four easy payments of £900.',
        stamp: Stamps.nailedIt,
        gradeCount: 25,
        gradeSum: 101,
      ),
      HouseEntry(
        posterName: StarterPackData.daveFromAccounts,
        text: '\'Water.\' Holds up glass. \'Eleven thousand pounds.\'',
        stamp: Stamps.noRegrets,
        gradeCount: 9,
        gradeSum: 31,
      ),
    ],
    'daily-19': [
      HouseEntry(
        posterName: StarterPackData.housePosterName,
        text: 'I have your left sock,\nthe pen you swore was '
            'stolen.\nSleep well, Big Kevin.',
        stamp: Stamps.sendHelp,
        gradeCount: 23,
        gradeSum: 92,
      ),
      HouseEntry(
        posterName: StarterPackData.auntPam,
        text: 'Under my bed lives\nonly a hoover and some\nleaflets. '
            'Night, Chuckles.',
        stamp: Stamps.dontAsk,
        gradeCount: 10,
        gradeSum: 30,
      ),
    ],
    'daily-20': [
      HouseEntry(
        posterName: StarterPackData.housePosterName,
        text: 'Meet Bolt: a whisk for a body, four corkscrew legs, an '
            'egg-timer heart. Photographed chewing the oven manual. '
            'He has been told.',
        stamp: Stamps.art,
        gradeCount: 22,
        gradeSum: 87,
      ),
      HouseEntry(
        posterName: StarterPackData.theIntern,
        text: 'Built a fully poseable dog from the cutlery drawer, with '
            'a tea-towel blanket and a microchip (a SIM card). Caught '
            'on the sofa. Vet booked for Tuesday.',
        stamp: Stamps.nailedIt,
        gradeCount: 12,
        gradeSum: 46,
      ),
    ],
    'daily-21': [
      HouseEntry(
        posterName: StarterPackData.housePosterName,
        text: 'One minute fifty of swirling a coin and staring '
            'meaningfully. In the last two seconds the coin falls out '
            'of my sleeve. I bowed anyway.',
        stamp: Stamps.sendHelp,
        gradeCount: 22,
        gradeSum: 85,
      ),
      HouseEntry(
        posterName: StarterPackData.daveFromAccounts,
        text: 'Spoon. Two minutes. Still a spoon. Bowed.',
        stamp: Stamps.technically,
        gradeCount: 9,
        gradeSum: 28,
      ),
    ],
    'daily-22': [
      HouseEntry(
        posterName: StarterPackData.housePosterName,
        text: '\'What news of the milk? Hath it been fetched, or doth it '
            'linger yet in yonder Co-op?\' [Exit, pursued by a reply '
            'that just says \'k\'.]',
        stamp: Stamps.nailedIt,
        gradeCount: 24,
        gradeSum: 99,
      ),
      HouseEntry(
        posterName: StarterPackData.auntPam,
        text: '\'Good morrow, my son. Didst thou receive the photo of '
            'the dog? It is the same dog as yesterday.\' [She sends it '
            'again.]',
        stamp: Stamps.noRegrets,
        gradeCount: 11,
        gradeSum: 38,
      ),
    ],
    'daily-23': [
      HouseEntry(
        posterName: StarterPackData.housePosterName,
        text: 'Feet in a washing-up bowl of sand, a beach towel, '
            'sunglasses on the cat. In the corner, quite clearly, a '
            'radiator.',
        stamp: Stamps.technically,
        gradeCount: 21,
        gradeSum: 80,
      ),
      HouseEntry(
        posterName: StarterPackData.theIntern,
        text: 'Ring light at 5600K, a sand-coloured duvet, wave sounds '
            'on the laptop and a cocktail umbrella I folded myself. '
            'Left my lanyard on. It says Swindon.',
        stamp: Stamps.dontAsk,
        gradeCount: 13,
        gradeSum: 49,
      ),
    ],
    'daily-24': [
      HouseEntry(
        posterName: StarterPackData.housePosterName,
        text: 'The Hoover Shuffle: push, pull, apologise to the '
            'skirting board. At full speed it looks like grief, but '
            'in a good way.',
        stamp: Stamps.nailedIt,
        gradeCount: 20,
        gradeSum: 78,
      ),
      HouseEntry(
        posterName: StarterPackData.daveFromAccounts,
        text: 'The Dishwasher. Bend. Stare. Close it again. It cleared '
            'the floor.',
        stamp: Stamps.noRegrets,
        gradeCount: 8,
        gradeSum: 25,
      ),
    ],
    'daily-25': [
      HouseEntry(
        posterName: StarterPackData.housePosterName,
        text: 'Warning: may contain opinions about parking. Do not '
            'operate before coffee. Store in a cool, dark room with '
            'the curtains shut until noon.',
        stamp: Stamps.technically,
        gradeCount: 23,
        gradeSum: 90,
      ),
      HouseEntry(
        posterName: StarterPackData.auntPam,
        text: 'Warning: will tell you about her knee. Contains nuts '
            '(the family). Store upright in a warm kitchen, near the '
            'biscuit tin.',
        stamp: Stamps.sendHelp,
        gradeCount: 12,
        gradeSum: 40,
      ),
    ],
    'daily-26': [
      HouseEntry(
        posterName: StarterPackData.housePosterName,
        text: 'Titanic. The pillow at the bow, arms out (its corners). '
            'Me behind it, holding on, gazing at the horizon of my '
            'hallway.',
        stamp: Stamps.art,
        gradeCount: 24,
        gradeSum: 98,
      ),
      HouseEntry(
        posterName: StarterPackData.theIntern,
        text: 'A full Notting Hill recreation: matching font, credits '
            'block, a five-star quote I wrote myself. The pillow got '
            'top billing. I got the note \'more chemistry\'.',
        stamp: Stamps.nailedIt,
        gradeCount: 14,
        gradeSum: 53,
      ),
    ],
    'daily-27': [
      HouseEntry(
        posterName: StarterPackData.housePosterName,
        text: 'To whoever keeps opening me \'just to look\': I am not a '
            'television. There is nothing new. There was nothing new '
            'an hour ago. Regards, The Fridge.',
        stamp: Stamps.nailedIt,
        gradeCount: 26,
        gradeSum: 105,
      ),
      HouseEntry(
        posterName: StarterPackData.daveFromAccounts,
        text: 'Someone knows. (Toaster)',
        stamp: Stamps.dontAsk,
        gradeCount: 10,
        gradeSum: 34,
      ),
    ],
    'daily-28': [
      HouseEntry(
        posterName: StarterPackData.housePosterName,
        text: '\'Bijou. Characterful. South-facing, if you turn round.\' '
            'Ends on the damp patch: \'and here, a feature wall that '
            'changes with the seasons.\'',
        stamp: Stamps.technically,
        gradeCount: 22,
        gradeSum: 86,
      ),
      HouseEntry(
        posterName: StarterPackData.auntPam,
        text: 'I got so carried away I made an offer on my own spare '
            'room. The flaw is the boiler. I called it vintage, then '
            'I cried a little.',
        stamp: Stamps.sendHelp,
        gradeCount: 10,
        gradeSum: 32,
      ),
    ],
    'daily-29': [
      HouseEntry(
        posterName: StarterPackData.housePosterName,
        text: 'A banana with one bruise for every bad decision, propped '
            'up beside the fruit bowl it was not invited into. Still '
            'smiling (felt tip).',
        stamp: Stamps.noRegrets,
        gradeCount: 21,
        gradeSum: 84,
      ),
      HouseEntry(
        posterName: StarterPackData.theIntern,
        text: 'Brought a stapler out of retirement and gave it a tiny '
            'cup of coffee and a badge that says \'Here to help\'. It '
            'is out of staples. It is still here to help.',
        stamp: Stamps.sendHelp,
        gradeCount: 15,
        gradeSum: 57,
      ),
    ],
    'daily-30': [
      HouseEntry(
        posterName: StarterPackData.housePosterName,
        text: 'I accept this award for Putting the Bins Out, which I '
            'did today, mostly on time. I would like to thank my '
            'neighbour, who parked in the exact spot I needed and '
            'then stood there watching.',
        stamp: Stamps.nailedIt,
        gradeCount: 23,
        gradeSum: 93,
      ),
      HouseEntry(
        posterName: StarterPackData.daveFromAccounts,
        text: 'For making toast. Thanks to the toaster, for nothing.',
        stamp: Stamps.technically,
        gradeCount: 9,
        gradeSum: 29,
      ),
    ],
  };

  // ---- Days ---------------------------------------------------------------

  /// Whole UTC days since 1970-01-01 for [date] (any time zone in, UTC out).
  static int daysSinceEpochUtc(DateTime date) {
    final u = date.toUtc();
    return DateTime.utc(u.year, u.month, u.day)
            .difference(DateTime.utc(1970))
            .inDays;
  }

  /// `yyyyMMdd` of [date]'s UTC day. Same shape as the server's
  /// `guards.dayKey` and storage.rules' day folders.
  static String dayKey(DateTime date) {
    final u = date.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${u.year}${two(u.month)}${two(u.day)}';
  }

  /// The UTC midnight a [dayKey] starts at. Throws [FormatException] for
  /// anything that is not eight digits.
  static DateTime dayStart(String dayKey) {
    if (!RegExp(r'^\d{8}$').hasMatch(dayKey)) {
      throw FormatException('Not a yyyyMMdd day key', dayKey);
    }
    return DateTime.utc(
      int.parse(dayKey.substring(0, 4)),
      int.parse(dayKey.substring(4, 6)),
      int.parse(dayKey.substring(6, 8)),
    );
  }

  /// Today's task for everyone, on [date]'s UTC day.
  static Task taskFor(DateTime date) {
    final pool = tasks();
    final i = (daysSinceEpochUtc(date) + poolOffset) % pool.length;
    return pool[i];
  }

  /// The task for a `yyyyMMdd` [dayKey].
  static Task taskForDayKey(String dayKey) => taskFor(dayStart(dayKey));

  /// How long until the next UTC midnight (when the task changes).
  static Duration untilNextTask(DateTime now) {
    final u = now.toUtc();
    final next = DateTime.utc(u.year, u.month, u.day + 1);
    return next.difference(u);
  }

  /// "5 h 12 m", "12 m", "under a minute": short enough for one hero line.
  static String formatUntil(Duration d) {
    final mins = d.inMinutes;
    if (mins < 1) return 'under a minute';
    final h = mins ~/ 60;
    final m = mins % 60;
    if (h == 0) return '$m m';
    return '$h h $m m';
  }

  // ---- Games --------------------------------------------------------------

  /// The deterministic id of [uid]'s daily game for [dayKey]:
  /// `daily_<uid>_<yyyyMMdd>`. Deterministic, so starting twice reuses it.
  static String gameIdFor(String uid, String dayKey) =>
      '$gameIdPrefix${uid}_$dayKey';

  /// The daily game's name, e.g. "Daily task, 9 Nov".
  static String gameNameFor(String dayKey) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final d = dayStart(dayKey);
    return 'Daily task, ${d.day} ${months[d.month - 1]}';
  }

  /// True for a daily task id (`daily-NN`).
  static bool isDailyTaskId(String taskId) => taskId.startsWith(taskIdPrefix);
}
