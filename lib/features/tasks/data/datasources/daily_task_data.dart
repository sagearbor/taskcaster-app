import '../../../../core/models/task.dart';

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
