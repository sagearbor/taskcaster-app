import '../../../../core/models/task.dart';

/// The Starter Pack: every new player's first game.
///
/// Ten hand-written tasks, in a fixed order, each doable alone, at home, with a
/// phone, in under three minutes — and funny whether you succeed or fail. The
/// copy is the product spec's copy verbatim (docs/PRODUCT_DIRECTION.md §5).
///
/// Every task carries the three things the new loop needs: a
/// [Task.submissionType] (so the task screen offers "Snap it" or "Write it"),
/// a [Task.rubric] (the one line a crowd grader scores against) and a
/// [Task.twist] (revealed after Start, and the first half of the auto-caption).
/// [Task.taskType] stays [TaskType.video] — that selects the *gameplay engine*
/// (the ordinary submit-and-judge flow), not the medium.
class StarterPackData {
  const StarterPackData._();

  /// The name of the starter game.
  static const String gameName = 'Your First Ten';

  /// Library category every starter task carries.
  static const String category = 'Starter Pack';

  /// Who the seeded house entries are posted as.
  static const String housePosterName = "Greg's assistant";

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
          title: 'A vegetable that has just received terrible news',
          description:
              'Find a vegetable. If you have no vegetables, find the most '
              'vegetable-adjacent thing in your home and do not tell us what '
              'it is. Photograph it at the exact moment it receives '
              'devastating news. Lighting, angle and emotional truth all '
              'count.',
          twist:
              'The news must be implied by the photo alone; no text on the '
              'vegetable.',
          rubric: 'Emotional truth of the vegetable.',
          submissionType: SubmissionType.photo,
          durationSeconds: 90,
        ),
        _t(
          id: 'starter-02',
          title:
              'The tallest tower of things that were never meant to be stacked',
          description:
              'Build the tallest freestanding tower you can from objects that '
              'have no business being stacked. It must stand on its own for '
              'the photo. A shoe must be involved somewhere.',
          twist: 'Nothing in the tower may be a box.',
          rubric: 'Height x how much you fear for it.',
          submissionType: SubmissionType.photo,
          durationSeconds: 120,
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
          title: 'The worst sandwich that is still technically food',
          description:
              'Assemble the worst sandwich you can from what is in your '
              'kitchen. Every ingredient must be edible. Photograph it with '
              'pride and list the ingredients in the caption. Do not eat it. '
              'We are not asking you to eat it.',
          twist: 'It must be cut in half for the photo.',
          rubric: 'Horror, then plausibility that it is food.',
          submissionType: SubmissionType.photo,
          durationSeconds: 180,
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
              'tied, not held. Take the photo one moment before disaster.',
          twist: 'Count them in the caption; the crowd will check.',
          rubric: 'Number of things x your dignity.',
          submissionType: SubmissionType.photo,
          durationSeconds: 60,
        ),
        _t(
          id: 'starter-09',
          title: 'The face of someone who has just remembered the oven is on '
              '— in another country',
          description:
              'Selfie. You have just remembered that you left the oven on. You '
              'are currently in a different country. It is 3 a.m. there. Show '
              'us every layer of that realisation in one face.',
          twist: 'No hands in the photo.',
          rubric: 'Number of distinct regrets visible.',
          submissionType: SubmissionType.photo,
          durationSeconds: 30,
        ),
        _t(
          id: 'starter-10',
          title: 'Your autobiography',
          description:
              'Hold up the cover of your autobiography. The title is the last '
              'thing you said out loud today. Make the cover: pose, props, '
              'expression. Put the title in the caption.',
          twist:
              'The cover must include a review quote from a household object.',
          rubric: 'Would you read it.',
          submissionType: SubmissionType.photo,
          durationSeconds: 90,
        ),
      ];

    /// One seeded text entry per task, posted as [housePosterName], so a
    /// brand-new player always has something to grade the moment they unlock a
    /// task and the Arena never looks empty.
  static const Map<String, String> houseEntries = {
    'starter-01':
        'A courgette. I told it the fridge was being repossessed. It has not '
            'blinked since.',
    'starter-02':
        'Four mugs, a bag of rice, one shoe and the smoke alarm. It stood for '
            'nine seconds. I have not stood for nine seconds today.',
    'starter-03':
        "The lamp is now The Understudy.\nSlogan: it waits, quietly, for the "
            'sun to fail.',
    'starter-04':
        'I am in this kitchen. I am the beige one. Take your time, there is no '
            'prize for finding me quickly and there is no prize for me either.',
    'starter-05':
        'Bread, cold beans, one slice of cheese, a single olive, more bread. '
            'Cut in half. Both halves apologised.',
    'starter-06':
        'The Scream, performed by a tea towel, two grapes, and a man who '
            'cannot quite reach the good props.',
    'starter-07':
        'There are four yoghurts.\nI have bought three yoghurts in my life.\n'
            'Three.',
    'starter-08':
        'Eleven. Nine if you only count the ones still up there when the photo '
            'was taken. Dignity: not applicable.',
    'starter-09':
        'I am told my face achieved seven distinct regrets. I can only name '
            'five. The other two belong to the oven.',
    'starter-10':
        '"Where Are My Keys", by me. On the cover I am holding a colander. The '
            'kettle says: a triumph, and he never found them.',
  };
}
