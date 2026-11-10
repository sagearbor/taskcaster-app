/// Party mode content: tasks that only work with everyone in the same room,
/// plus the secret missions handed out privately at the start.
///
/// Pure data, no Flutter. Copy rules: second person, short, dry, no
/// exclamation marks.
library;

/// How a party task plays out at the table.
enum PartyTaskKind {
  /// Everyone at once, one clock, the best result wins.
  headToHead,

  /// One player at a time performs to the room; the room judges.
  performance,

  /// A short fetch, then the twist nobody saw coming.
  gatherReveal,
}

extension PartyTaskKindLabel on PartyTaskKind {
  /// The badge on the task card.
  String get label => switch (this) {
        PartyTaskKind.headToHead => 'HEAD TO HEAD',
        PartyTaskKind.performance => 'PERFORMANCE',
        PartyTaskKind.gatherReveal => 'GO FETCH',
      };
}

class PartyTask {
  final String id;
  final String title;

  /// What the host reads aloud.
  final String prompt;
  final PartyTaskKind kind;

  /// Clock for the main part. For [PartyTaskKind.performance] it is per
  /// player (each performer gets their own turn on the clock).
  final int seconds;

  /// gather→reveal only: the twist shown once the fetch clock runs out.
  final String? twist;

  /// gather→reveal only: clock for the twist. When [twistPerPlayer] is true
  /// each player gets their own turn on that clock.
  final int twistSeconds;
  final bool twistPerPlayer;

  /// How the room decides, shown on the judging screen.
  final String judging;

  const PartyTask({
    required this.id,
    required this.title,
    required this.prompt,
    required this.kind,
    required this.seconds,
    required this.judging,
    this.twist,
    this.twistSeconds = 0,
    this.twistPerPlayer = false,
  });

  /// Performance tasks run one player at a time.
  bool get perPlayer => kind == PartyTaskKind.performance;

  bool get hasTwist => twist != null;
}

/// Points a completed secret mission is worth at the end.
const int kSecretMissionBonus = 3;

/// 25 tasks that need a room, some objects and witnesses.
const List<PartyTask> kPartyTasks = [
  // ---- Head to head ------------------------------------------------------
  PartyTask(
    id: 'sock-mug',
    title: 'Sock in a mug',
    prompt: 'Land a rolled-up sock in a mug from as far away as possible. '
        'Three throws each. The mug may not be moved.',
    kind: PartyTaskKind.headToHead,
    seconds: 120,
    judging: 'Furthest successful throw wins.',
  ),
  PartyTask(
    id: 'pocket-tower',
    title: 'Pocket tower',
    prompt: 'Build the tallest freestanding tower using only what is in your '
        'pockets or bag right now. It must stand for five seconds.',
    kind: PartyTaskKind.headToHead,
    seconds: 90,
    judging: 'Tallest tower still standing wins.',
  ),
  PartyTask(
    id: 'blind-portrait',
    title: 'Blind portrait',
    prompt: 'Draw the person on your left without looking at your paper. '
        'Not once. We are watching.',
    kind: PartyTaskKind.headToHead,
    seconds: 60,
    judging: 'Best likeness wins. The subjects may not vote for themselves.',
  ),
  PartyTask(
    id: 'coin-edge',
    title: 'Edge of glory',
    prompt: 'Slide a coin across the table so it stops as close to the far '
        'edge as possible. Three attempts. Coins that fall off are dead to us.',
    kind: PartyTaskKind.headToHead,
    seconds: 90,
    judging: 'Closest to the edge without falling wins.',
  ),
  PartyTask(
    id: 'one-hand-plane',
    title: 'One-handed aviation',
    prompt: 'Make a paper aeroplane with one hand behind your back, then '
        'fly it.',
    kind: PartyTaskKind.headToHead,
    seconds: 120,
    judging: 'Longest flight wins. Style is noted, then ignored.',
  ),
  PartyTask(
    id: 'hand-stack',
    title: 'The back of your hand',
    prompt: 'Balance as many objects as you can on the back of one hand. '
        'Hold it for five seconds.',
    kind: PartyTaskKind.headToHead,
    seconds: 90,
    judging: 'Most objects held for five seconds wins.',
  ),
  PartyTask(
    id: 'longest-note',
    title: 'One long note',
    prompt: 'Everyone sing one note, starting together, for as long as you '
        'can. Breathing in counts as stopping.',
    kind: PartyTaskKind.headToHead,
    seconds: 60,
    judging: 'Last voice standing wins.',
  ),
  PartyTask(
    id: 'coaster-reach',
    title: 'Long reach',
    prompt: 'Without moving your feet from where you stand, place a coaster '
        'as far away from you as possible.',
    kind: PartyTaskKind.headToHead,
    seconds: 60,
    judging: 'Furthest coaster wins. Feet are checked.',
  ),
  PartyTask(
    id: 'spoon-face',
    title: 'Spoon face',
    prompt: 'Hang a spoon from your face. Nose, chin, forehead, all legal. '
        'Hands off once it hangs.',
    kind: PartyTaskKind.headToHead,
    seconds: 90,
    judging: 'Longest hang wins.',
  ),
  PartyTask(
    id: 'statues',
    title: 'Statues',
    prompt: 'Strike a pose and hold it. Anyone who moves, laughs or blinks '
        'theatrically is out.',
    kind: PartyTaskKind.headToHead,
    seconds: 90,
    judging: 'Last statue standing wins.',
  ),

  // ---- Performance (one at a time) ---------------------------------------
  PartyTask(
    id: 'advert',
    title: 'The advert',
    prompt: 'Sell the room the nearest object to your left. It is a TV '
        'advert. It has a jingle.',
    kind: PartyTaskKind.performance,
    seconds: 30,
    judging: 'Most persuasive advert wins.',
  ),
  PartyTask(
    id: 'museum-tour',
    title: 'Museum tour',
    prompt: 'Give a confident guided tour of this room as if it were a famous '
        'museum. Every object has a history.',
    kind: PartyTaskKind.performance,
    seconds: 30,
    judging: 'Most convincing guide wins.',
  ),
  PartyTask(
    id: 'nature-doc',
    title: 'Nature documentary',
    prompt: 'Narrate the player on your right as if they were a rare animal '
        'being filmed in the wild. Whisper.',
    kind: PartyTaskKind.performance,
    seconds: 30,
    judging: 'Best documentary wins. The animal gets a vote.',
  ),
  PartyTask(
    id: 'slow-mo',
    title: 'Slow motion',
    prompt: 'Re-enact the most dramatic moment of your week in slow motion. '
        'No words.',
    kind: PartyTaskKind.performance,
    seconds: 30,
    judging: 'Most dramatic wins.',
  ),
  PartyTask(
    id: 'late-excuse',
    title: 'The excuse',
    prompt: 'The room hands you three objects. Explain why you were late '
        'using all of them.',
    kind: PartyTaskKind.performance,
    seconds: 30,
    judging: 'Most believable excuse wins.',
  ),
  PartyTask(
    id: 'impression',
    title: 'Someone in this room',
    prompt: 'Do an impression of someone in this room. Do not say who. Keep '
        'going until they guess.',
    kind: PartyTaskKind.performance,
    seconds: 30,
    judging: 'Most accurate impression wins. The victim may abstain.',
  ),
  PartyTask(
    id: 'weather-dance',
    title: 'The forecast',
    prompt: "Perform tomorrow's weather forecast as an interpretive dance.",
    kind: PartyTaskKind.performance,
    seconds: 30,
    judging: 'Most informative dance wins.',
  ),
  PartyTask(
    id: 'object-wedding',
    title: 'The toast',
    prompt: 'Two objects on the table are getting married. You are the best '
        'man. Raise a glass.',
    kind: PartyTaskKind.performance,
    seconds: 30,
    judging: 'Most moving toast wins.',
  ),

  // ---- Gather → reveal ---------------------------------------------------
  PartyTask(
    id: 'impressive-object',
    title: 'Most impressive object',
    prompt: 'Fetch the most impressive object you can find.',
    kind: PartyTaskKind.gatherReveal,
    seconds: 60,
    twist: 'Now sell it to the person on your right. They are a tough '
        'customer.',
    twistSeconds: 30,
    twistPerPlayer: true,
    judging: 'Best sales pitch wins. The object is irrelevant now.',
  ),
  PartyTask(
    id: 'something-yellow',
    title: 'Something yellow',
    prompt: 'Bring back something yellow.',
    kind: PartyTaskKind.gatherReveal,
    seconds: 45,
    twist: 'Explain why it is your most treasured possession. Tears are '
        'welcome.',
    twistSeconds: 30,
    twistPerPlayer: true,
    judging: 'Most heartfelt tribute wins.',
  ),
  PartyTask(
    id: 'hidden-object',
    title: 'Behind your back',
    prompt: 'Find one object and hide it behind your back. Nobody may see '
        'it.',
    kind: PartyTaskKind.gatherReveal,
    seconds: 45,
    twist: 'It is now a musical instrument. Play the room a short song on it.',
    twistSeconds: 20,
    twistPerPlayer: true,
    judging: 'Best performance wins.',
  ),
  PartyTask(
    id: 'smallest-thing',
    title: 'Smallest thing',
    prompt: 'Find the smallest thing you can.',
    kind: PartyTaskKind.gatherReveal,
    seconds: 45,
    twist: 'Give it a name, a backstory and one tragic flaw.',
    twistSeconds: 30,
    twistPerPlayer: true,
    judging: 'Best story wins. Size no longer matters.',
  ),
  PartyTask(
    id: 'hat',
    title: 'Possible hat',
    prompt: 'Find something that could be a hat.',
    kind: PartyTaskKind.gatherReveal,
    seconds: 45,
    twist: 'Wear it. Walk the runway and describe the collection.',
    twistSeconds: 20,
    twistPerPlayer: true,
    judging: 'Best show wins.',
  ),
  PartyTask(
    id: 'softest',
    title: 'Softest object',
    prompt: 'Find the softest object you can.',
    kind: PartyTaskKind.gatherReveal,
    seconds: 45,
    twist: 'Throw it at a cup on the floor, from the doorway. Softness was '
        'never the point.',
    twistSeconds: 60,
    judging: 'Closest to the cup wins.',
  ),
  PartyTask(
    id: 'perfect-pair',
    title: 'Perfect pair',
    prompt: 'Bring back two objects that go together.',
    kind: PartyTaskKind.gatherReveal,
    seconds: 60,
    twist: 'Swap one of them with the player on your left. Explain why your '
        'new pair is better.',
    twistSeconds: 30,
    twistPerPlayer: true,
    judging: 'Most convincing pair wins.',
  ),
];

/// Hidden missions, one per player, done sneakily during the party.
const List<String> kSecretMissions = [
  'Get someone to say "banana".',
  'Make everyone stand up at the same time.',
  'Get someone to high-five you.',
  'Say "magnificent" three times without anyone calling it out.',
  'Get someone to hand you a spoon.',
  'Get another player to touch their nose.',
  'Convince someone to swap seats with you.',
  'Get someone to ask you "what?"',
  'Hum the same tune three times without anyone asking why.',
  'Get someone to say "purple".',
  'Compliment someone\'s shoes and get a thank you.',
  'Get someone to tell you the time.',
  'Start a debate about whether a hot dog is a sandwich.',
  'Get two people to clap at the same time, for anything.',
  'Make someone take a sip of their drink right after you do.',
  'Get someone to say your name in an accent.',
];
