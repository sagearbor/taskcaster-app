import 'dart:math';

/// The vibe a hunt prompt gives off — used to keep an auto-dealt hand varied
/// and to let the UI colour-code prompts later. Purely descriptive; it never
/// affects how a prompt becomes a task.
enum HuntVibe {
  silly, // goofy poses, dress-up, showing off
  cozy, // soft, warm, comforting things
  curious, // clever finds that make you think
  treasure, // shiny, precious, brag-worthy
  adventurous, // a little gross / hidden / brave
}

extension HuntVibeLabel on HuntVibe {
  String get label {
    switch (this) {
      case HuntVibe.silly:
        return 'Silly';
      case HuntVibe.cozy:
        return 'Cozy';
      case HuntVibe.curious:
        return 'Curious';
      case HuntVibe.treasure:
        return 'Treasure';
      case HuntVibe.adventurous:
        return 'Adventurous';
    }
  }
}

/// A single House Hunt prompt: one short, concrete, family-safe thing to hunt
/// down anywhere in a home. The [prompt] text is the whole instruction — punchy
/// and kid-readable — and becomes a task title verbatim.
class HouseHuntPrompt {
  const HouseHuntPrompt(this.id, this.prompt, this.vibe);

  /// Stable, human-readable id (e.g. `hh-01`) so a dealt hand can dedupe and
  /// swaps can avoid repeats.
  final String id;

  /// The full, ready-to-read instruction (e.g. "Find something RED and strike a
  /// pose with it").
  final String prompt;

  final HuntVibe vibe;
}

/// The House Hunt prompt deck — the curated heart of the remote/async hunt.
///
/// Every prompt is:
///  * findable in ANY home (no special stuff required),
///  * short, concrete and readable by a kid,
///  * family-safe and kind.
///
/// Follows the same static-library shape as `PrebuiltTasksData`.
class HouseHuntPrompts {
  const HouseHuntPrompts._();

  /// How many prompts make up one hunt.
  static const int huntSize = 5;

  /// The full deck. Keep every [HouseHuntPrompt.id] and [HouseHuntPrompt.prompt]
  /// unique — `assert`ed by the deck-integrity test.
  static const List<HouseHuntPrompt> all = [
    // ---- Silly -------------------------------------------------------------
    HouseHuntPrompt('hh-01',
        'Find something RED and strike your best superhero pose with it.',
        HuntVibe.silly),
    HouseHuntPrompt('hh-02',
        'Something that makes a great hat that is NOT a hat — wear it proudly.',
        HuntVibe.silly),
    HouseHuntPrompt('hh-03',
        'Pull your silliest face in the nearest mirror and hold it.',
        HuntVibe.silly),
    HouseHuntPrompt('hh-04',
        'Find an object and give it a dramatic movie-villain voice.',
        HuntVibe.silly),
    HouseHuntPrompt('hh-05',
        'Wear three things at once that really do not belong together.',
        HuntVibe.silly),
    HouseHuntPrompt('hh-06',
        'Find something and make it "dance" for five whole seconds.',
        HuntVibe.silly),
    HouseHuntPrompt('hh-07',
        'Balance something on your head and spin around once without dropping it.',
        HuntVibe.silly),
    HouseHuntPrompt('hh-08',
        'Find the goofiest photo or drawing in the house and copy the pose.',
        HuntVibe.silly),

    // ---- Cozy --------------------------------------------------------------
    HouseHuntPrompt('hh-09',
        'Something soft enough to nap on right now — flop onto it.',
        HuntVibe.cozy),
    HouseHuntPrompt('hh-10',
        'The coziest blanket in the house — wrap up like a burrito.',
        HuntVibe.cozy),
    HouseHuntPrompt('hh-11',
        'Something that smells amazing — take a big happy sniff.', HuntVibe.cozy),
    HouseHuntPrompt('hh-12',
        'Your comfiest chair — flop into it as dramatically as you can.',
        HuntVibe.cozy),
    HouseHuntPrompt('hh-13',
        'Something warm and fuzzy — give it a great big hug.', HuntVibe.cozy),
    HouseHuntPrompt('hh-14',
        'The softest thing you own — hold it up to the camera.', HuntVibe.cozy),

    // ---- Curious -----------------------------------------------------------
    HouseHuntPrompt('hh-15',
        'The oldest thing you can find — tell us how old it is.',
        HuntVibe.curious),
    HouseHuntPrompt(
        'hh-16', 'A treasure older than YOU — and prove it!', HuntVibe.curious),
    HouseHuntPrompt('hh-17',
        'Something with a hidden button, switch, or zipper — show it off.',
        HuntVibe.curious),
    HouseHuntPrompt('hh-18',
        'Something that tells the time that is NOT a phone.', HuntVibe.curious),
    HouseHuntPrompt('hh-19',
        'Something with more than ten of something on it — count them out loud.',
        HuntVibe.curious),
    HouseHuntPrompt('hh-20',
        'Something that makes a cool sound when you tap it.', HuntVibe.curious),
    HouseHuntPrompt('hh-21',
        'Something perfectly round — hunt one down.', HuntVibe.curious),
    HouseHuntPrompt('hh-22',
        'Two things that are an exact matching pair — hold them together.',
        HuntVibe.curious),
    HouseHuntPrompt('hh-23',
        'The heaviest thing you can safely lift with one hand.',
        HuntVibe.curious),

    // ---- Treasure ----------------------------------------------------------
    HouseHuntPrompt('hh-24',
        'Your best hiding spot — show us where you would hide!',
        HuntVibe.treasure),
    HouseHuntPrompt('hh-25',
        'The tiniest thing you own — can we even see it?', HuntVibe.treasure),
    HouseHuntPrompt('hh-26',
        'The biggest thing in the room — give it a friendly knock.',
        HuntVibe.treasure),
    HouseHuntPrompt('hh-27',
        'Something shiny that could pass for real treasure.',
        HuntVibe.treasure),
    HouseHuntPrompt('hh-28',
        'Something you made yourself — tell us the story behind it.',
        HuntVibe.treasure),
    HouseHuntPrompt('hh-29',
        'Your favorite book — read us the very first line.', HuntVibe.treasure),
    HouseHuntPrompt('hh-30',
        'The most colorful thing you can find — wave it around.',
        HuntVibe.treasure),
    HouseHuntPrompt('hh-31',
        'The fanciest thing you own — model it for us.', HuntVibe.treasure),
    HouseHuntPrompt('hh-32',
        'Something that sparkles or shines in the light.', HuntVibe.treasure),
    HouseHuntPrompt('hh-33',
        'Something you would grab FIRST from a treasure chest.',
        HuntVibe.treasure),

    // ---- Adventurous -------------------------------------------------------
    HouseHuntPrompt('hh-34',
        'Something a little bit gross but totally safe — ewww!',
        HuntVibe.adventurous),
    HouseHuntPrompt('hh-35',
        'The dustiest, most forgotten treasure in a corner.',
        HuntVibe.adventurous),
    HouseHuntPrompt('hh-36',
        'Something squishy — give it a big satisfying squeeze.',
        HuntVibe.adventurous),
    HouseHuntPrompt('hh-37',
        'A thing that lives at the very back of a drawer.',
        HuntVibe.adventurous),
    HouseHuntPrompt('hh-38',
        'The yummiest snack in the kitchen — no eating it yet!',
        HuntVibe.adventurous),
    HouseHuntPrompt('hh-39',
        'A tiny piece of nature you brought indoors — a leaf, shell, or rock.',
        HuntVibe.adventurous),
    HouseHuntPrompt('hh-40',
        'Something you can hide a small toy inside — then hide it!',
        HuntVibe.adventurous),
    HouseHuntPrompt('hh-41',
        'The bravest thing to reach for on a high-up shelf (stay safe!).',
        HuntVibe.adventurous),
  ];

  /// Deal [count] distinct prompts at random, never repeating and never
  /// re-dealing anything in [exclude]. Returns fewer than [count] only if the
  /// deck genuinely runs out (it never does for a five-card hand).
  static List<HouseHuntPrompt> deal({
    int count = huntSize,
    Random? random,
    Iterable<HouseHuntPrompt> exclude = const [],
  }) {
    final rng = random ?? Random();
    final excludeIds = exclude.map((p) => p.id).toSet();
    final pool = all.where((p) => !excludeIds.contains(p.id)).toList()
      ..shuffle(rng);
    return pool.take(count).toList();
  }

  /// Pick one random prompt whose id is NOT in [excludeIds] — the swap-one
  /// primitive behind "give me a different prompt". Falls back to any prompt if
  /// every id happens to be excluded.
  static HouseHuntPrompt randomExcluding(
    Set<String> excludeIds, {
    Random? random,
  }) {
    final rng = random ?? Random();
    final pool = all.where((p) => !excludeIds.contains(p.id)).toList();
    final from = pool.isNotEmpty ? pool : all;
    return from[rng.nextInt(from.length)];
  }
}
