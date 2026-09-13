import '../../../../core/models/task.dart';

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
/// The ids are unchanged (`starter-01` … `starter-10`) so the deterministic
/// house-entry ids stay stable across the change.
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
    );
  }

  /// The ten tasks, in play order.
  static List<Task> tasks() => [
        _t(
          id: 'starter-01',
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
          id: 'starter-02',
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
          id: 'starter-05',
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
          id: 'starter-08',
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
        _t(
          id: 'starter-09',
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
          id: 'starter-10',
          title: 'Your autobiography: the trailer',
          description:
              'Hold up the cover of your autobiography. The title is the last '
              'thing you said out loud today. Read the first line of the book '
              'in a movie-trailer voice.',
          twist:
              'The cover must include a review quote from a household object.',
          rubric: 'Would you watch it.',
          submissionType: SubmissionType.video,
          durationSeconds: 30,
        ),
      ];

  /// One seeded entry per task, posted as [housePosterName], so a brand-new
  /// player always has something to grade the moment they unlock a task and
  /// the Arena never looks empty.
  ///
  /// For a video task this text is still written — it becomes the post's
  /// caption/fallback text, and it is what shows if the seeded clip is ever
  /// unavailable.
  static const Map<String, String> houseEntries = {
    'starter-01':
        'Egg made it 4 steps. Narration made it 30 seconds.',
    'starter-02': 'Seven objects, one shoe, 1.5 seconds of standing.',
    'starter-03':
        "The lamp is now The Understudy.\nSlogan: it waits, quietly, for the "
            'sun to fail.',
    'starter-04':
        'I am in this kitchen. I am the beige one. Take your time, there is no '
            'prize for finding me quickly and there is no prize for me either.',
    'starter-05': 'Pickle, custard, toast, regret. One bite.',
    'starter-06':
        'The Scream, performed by a tea towel, two grapes, and a man who '
            'cannot quite reach the good props.',
    'starter-07':
        'There are four yoghurts.\nI have bought three yoghurts in my life.\n'
            'Three.',
    'starter-08': 'Nine things. The colander was the mistake.',
    'starter-09': "Layer 4 was 'the cat is also in the oven'.",
    'starter-10':
        "'I said I'd be five minutes.' — reviewed by the kettle: 'a lie'",
  };
}
