import '../../../../core/models/task.dart';

/// The prebuilt task library — the heart of the video-task party game.
///
/// Every task here is:
///  * filmable in under 5 minutes with zero special equipment,
///  * safe and family-friendly,
///  * written in an imperative, playful Taskmaster voice with a twist.
///
/// Tasks carry a stable, human-readable [Task.id] (e.g. `quick-03`) so that
/// selections survive repeated calls to [getAllTasks], and a [Task.category]
/// drawn from [categories] so the browser can group and filter them.
class PrebuiltTasksData {
  const PrebuiltTasksData._();

  // Category names. Keep in sync with [categories].
  static const String quickAndSilly = 'Quick & Silly';
  static const String getCreative = 'Get Creative';
  static const String physicalFeats = 'Physical Feats';
  static const String kitchenCapers = 'Kitchen Capers';
  static const String outdoorAnywhere = 'Outdoor & Anywhere';
  static const String familyFaceOff = 'Family Face-off';
  static const String wordAndWit = 'Word & Wit';

  /// All valid library categories, in display order.
  static const List<String> categories = [
    quickAndSilly,
    getCreative,
    physicalFeats,
    kitchenCapers,
    outdoorAnywhere,
    familyFaceOff,
    wordAndWit,
  ];

  /// The full library, grouped by category in [categories] order.
  static List<Task> getAllTasks() {
    return [
      ..._quickAndSillyTasks(),
      ..._getCreativeTasks(),
      ..._physicalFeatsTasks(),
      ..._kitchenCapersTasks(),
      ..._outdoorAnywhereTasks(),
      ..._familyFaceOffTasks(),
      ..._wordAndWitTasks(),
    ];
  }

  /// Tasks belonging to a single [category].
  static List<Task> getTasksByCategory(String category) {
    return getAllTasks().where((t) => t.category == category).toList();
  }

  static Task _t(String id, String category, String title, String description) {
    return Task(
      id: id,
      title: title,
      description: description,
      taskType: TaskType.video,
      category: category,
      submissions: const [],
    );
  }

  // ---------------------------------------------------------------------
  // Quick & Silly — doable in about 60 seconds, indoors, zero prep.
  // ---------------------------------------------------------------------
  static List<Task> _quickAndSillyTasks() {
    const c = quickAndSilly;
    return [
      _t('quick-01', c, 'Make the most dramatic entrance',
          'Enter the room as if you have just returned from a ten-year voyage and everyone thought you were lost at sea. Capes optional. Tears encouraged. Most theatrical entrance wins.'),
      _t('quick-02', c, 'Sneeze like three different animals',
          'Perform a convincing sneeze as a mouse, an elephant, and one animal of your choosing. The judge must be able to tell which is which. Bless you.'),
      _t('quick-03', c, 'Answer an important phone call from a potato',
          'A potato (or the roundest object nearby) is calling and the news is HUGE. Take the call. React accordingly. We never hear the potato — only you.'),
      _t('quick-04', c, 'Walk across the room like the floor is made of pudding',
          'Cross the room. The floor is knee-deep pudding. Commit to the physics. Most believable pudding-wading wins.'),
      _t('quick-05', c, 'Become a slowly deflating balloon',
          'You are a proud, fully inflated balloon. Somebody has untied your knot. Deflate over the course of 30 seconds, sound effects included.'),
      _t('quick-06', c, 'Deliver terrible news to a houseplant',
          'Sit a plant (or any leafy stand-in) down and gently break some devastating news to it. Be kind. It has been through a lot. Most tender delivery wins.'),
      _t('quick-07', c, 'React to the world\'s sourest invisible sweet',
          'Place an imaginary, catastrophically sour sweet on your tongue and let your face tell the whole story. No words allowed. Best face journey wins.'),
      _t('quick-08', c, 'Do your morning routine in 20 seconds',
          'Perform your entire morning routine — waking, stretching, brushing, breakfast — compressed into 20 frantic seconds. Fast-forward energy, no actual toothpaste required.'),
      _t('quick-09', c, 'Lose a staring contest to yourself in the mirror',
          'Challenge your reflection to a staring contest. Lose. Badly. Show us the exact moment of defeat and your gracious concession speech.'),
      _t('quick-10', c, 'Impersonate a washing machine on spin cycle',
          'Go through a full wash: fill, gentle wash, and a dramatic finale spin. Bonus points for an unbalanced-load wobble.'),
      _t('quick-11', c, 'Get startled by your own hand',
          'You are calmly minding your business when you notice your own hand — as if for the first time. Escalate. Most convincing betrayal wins.'),
      _t('quick-12', c, 'Wear as many items of clothing as possible in 60 seconds',
          'One minute on the clock. Layer up. Every item must be genuinely worn, not draped. Count them off proudly at the end.'),
      _t('quick-13', c, 'Perform a slow-motion replay of picking up a sock',
          'Pick up a sock. Now perform the broadcast slow-motion replay of that moment, complete with commentary-worthy intensity and a triumphant celebration.'),
      _t('quick-14', c, 'Ride an invisible escalator',
          'Enter frame on a perfectly smooth invisible escalator, ride it, and exit at the top. Legs hidden behind a couch or counter recommended. Smoothest glide wins.'),
      _t('quick-15', c, 'Have both sides of an argument with yourself',
          'Play two people locked in a heated disagreement about whether cereal is a soup. Switch positions, voices, and postures. Whoever you are, win.'),
      _t('quick-16', c, 'Make the best noise using only your body',
          'No props, no instruments — just you. Produce the most impressive, satisfying, or baffling noise your body can make. One take.'),
      _t('quick-17', c, 'Sit down as slowly as humanly possible',
          'Lower yourself into a chair over a full 30 seconds without ever stopping or plopping. The final contact should be gentle as a snowflake. Wobbling is part of the show.'),
      _t('quick-18', c, 'Discover you are in a shampoo commercial',
          'Mid-ordinary-moment, the wind machine kicks in and you realize you are the star of a glamorous shampoo advert. Hair flips mandatory, actual shampoo not.'),
      _t('quick-19', c, 'Become a sports mascot for your own household',
          'Invent a mascot for Team Your-House and debut its signature hype routine: the walk, the moves, the big finish. No costume needed — commitment is the costume.'),
      _t('quick-20', c, 'Say goodbye to a departing sock with full emotion',
          'A beloved sock is leaving forever. Give it the airport farewell scene it deserves: the run, the embrace, the long look back. One sock. All the feelings.'),
      _t('quick-21', c, 'Move like the room\'s gravity keeps changing',
          'Every five seconds, gravity shifts: heavier, lighter, sideways. Survive 30 seconds of it. Most convincing physics wins.'),
      _t('quick-22', c, 'Blow the world\'s most disappointing party horn',
          'Mime an enormous inhale and deliver the tiniest, saddest party-horn noise you can voice, then react to the anticlimax. Timing is everything.'),
    ];
  }

  // ---------------------------------------------------------------------
  // Get Creative — make, draw, build, invent.
  // ---------------------------------------------------------------------
  static List<Task> _getCreativeTasks() {
    const c = getCreative;
    return [
      _t('create-01', c, 'Build the tallest tower that survives ten seconds',
          'Using only things within arm\'s reach of where you\'re standing right now, build the tallest freestanding tower you can. It must survive ten full on-camera seconds. No leaning on walls. No glue. No mercy.'),
      _t('create-02', c, 'Draw your pet (real or imaginary) with your eyes closed',
          'Eyes shut the entire time. Draw your pet — or the pet you wish you had. Reveal it to the camera and defend the likeness with total confidence.'),
      _t('create-03', c, 'Make a hat that says "I am important"',
          'Construct a hat from household materials that would command respect in any boardroom. Wear it. Hold a brief press conference about your new position.'),
      _t('create-04', c, 'Design a flag for your bedroom',
          'Your bedroom is now a sovereign nation. Create its flag, present it with appropriate ceremony, and explain what each element represents. Anthems welcome.'),
      _t('create-05', c, 'Turn a family member or friend into a work of art',
          'Using only soft, safe things (scarves, cushions, paper), transform a willing volunteer into a museum piece. Unveil them with a title card and a curator\'s introduction.'),
      _t('create-06', c, 'Invent a musical instrument and perform its debut concert',
          'Build a playable instrument from things around you, name it, and perform its world-premiere piece. The piece may be short. The bow must be long.'),
      _t('create-07', c, 'Make the best paper aircraft and commentate its maiden flight',
          'Fold an aircraft, hype its maiden voyage like a rocket launch, then fly it. Stick the landing commentary no matter what actually happens.'),
      _t('create-08', c, 'Create a self-portrait using no art supplies',
          'No pens, pencils, paint, or paper allowed. Arrange objects, clothes, snacks — anything else — into your own face. Reveal it beside your actual face for comparison.'),
      _t('create-09', c, 'Build a five-star hotel for a small toy',
          'Choose a small toy or object as your VIP guest and construct its luxury accommodation. Give the camera the full grand tour: lobby, suite, and one absurd amenity.'),
      _t('create-10', c, 'Design the book cover of your autobiography',
          'Create the cover — title, dramatic pose, glowing review quote — for the story of your life. Reveal it like a bookstore unveiling and read the blurb aloud.'),
      _t('create-11', c, 'Make a puppet and let it interview you',
          'Build a puppet from a sock, spoon, or anything handy. The puppet is a hard-hitting journalist. You are its reluctant celebrity guest. Fur may fly.'),
      _t('create-12', c, 'Wrap a "gift" so badly it becomes beautiful',
          'Wrap any object using the wrong materials on purpose — foil, socks, junk mail — and present it as avant-garde luxury packaging. Sell us on the artistic vision.'),
      _t('create-13', c, 'Sculpt a famous landmark from laundry',
          'Using only clean laundry, recreate a world-famous landmark. Announce it like a tour guide welcoming visitors. Scale is negotiable; ambition is not.'),
      _t('create-14', c, 'Invent a brand-new sport playable in one room',
          'Devise a sport using only what\'s in the room, explain its rules in 30 seconds, then demonstrate a thrilling match highlight, including the controversial referee decision.'),
      _t('create-15', c, 'Create a movie poster starring yourself',
          'Stage and pose the poster for your blockbuster: title, tagline, dramatic lighting from a lamp. Hold the pose while narrating the trailer voice-over.'),
      _t('create-16', c, 'Build a marble run (marble optional)',
          'Construct a rolling-object run from books, tubes, and furniture, then send something small and round down it. The longer the journey, the bigger the glory. Narrate the descent.'),
      _t('create-17', c, 'Make a tiny museum of three household treasures',
          'Curate three ordinary objects into an exhibition. Give each a grand title and a plaque-worthy backstory. Conduct the opening-night tour with white-glove reverence.'),
      _t('create-18', c, 'Redesign your face using only things in the bathroom cabinet',
          'Cotton-ball eyebrows? Toothbrush moustache? Using safe, clean bathroom items (nothing near your eyes), give yourself a bold new look and debut it on the catwalk.'),
      _t('create-19', c, 'Construct wearable shoes out of anything but shoes',
          'Craft footwear from non-shoe materials and take them for an on-camera test walk. Judged on style, engineering, and how confidently you strut.'),
      _t('create-20', c, 'Make a stop-motion masterpiece in five minutes',
          'Using burst photos or tiny video clips, make objects move on their own: a snack that escapes, shoes that dance. Ten seconds of footage, one enormous artistic statement.'),
    ];
  }

  // ---------------------------------------------------------------------
  // Physical Feats — safe, no equipment, all bodies welcome.
  // ---------------------------------------------------------------------
  static List<Task> _physicalFeatsTasks() {
    const c = physicalFeats;
    return [
      _t('phys-01', c, 'Balance the most things on your head while reciting the alphabet',
          'Stack objects on your head, then recite A to Z without a single item falling. One letter per second. If it all tumbles, so does your score.'),
      _t('phys-02', c, 'Stand on one leg while doing three other things',
          'One foot on the ground, then layer on three simultaneous activities of your choice — singing, folding a shirt, patting your head. Hold it all together for 20 seconds.'),
      _t('phys-03', c, 'Cross the room without touching the floor',
          'Get from one side of a room to the other using cushions, furniture, and cunning — never the floor. Plan your route, announce it, survive it. Lava rules apply.'),
      _t('phys-04', c, 'Do the slowest jumping jack ever performed',
          'One single jumping jack, stretched over 30 excruciating seconds, with the focus of an Olympic final. Both feet may leave the floor only once. Stick the landing.'),
      _t('phys-05', c, 'Throw a paper ball into a container behind you',
          'Crumple some paper, place any container behind your back, and sink the no-look trick shot. Unlimited attempts within your video — but the celebration must match the difficulty.'),
      _t('phys-06', c, 'Walk heel-to-toe along an imaginary tightrope over a canyon',
          'Tape or imagine a line on the floor. You are 300 metres above a gorge. Wobble, recover, nearly perish, and make it across. Sell the peril.'),
      _t('phys-07', c, 'Hop on one foot while spelling your name backwards',
          'Simple: hop continuously on one foot and spell your full name in reverse, one letter per hop. Mess up a letter, start the word again. Dizziness is part of the sport.'),
      _t('phys-08', c, 'Carry five soft items across the room in one trip',
          'Gather five pillows, plushies, or rolled socks. Move them all across the room in a single trip without dropping any. Creative stacking, clamping, and chin usage encouraged.'),
      _t('phys-09', c, 'Perform the world\'s most gentle high-speed chase',
          'Chase an imaginary suspect around your living room entirely in slow motion, including the dramatic dive and the arrest. Nothing may be knocked over. Justice, gently.'),
      _t('phys-10', c, 'Keep a balloon (or rolled sock) airborne using no hands',
          'Keep something soft and light off the ground for 30 seconds using heads, knees, elbows, feet — anything but hands. Style points for unnecessary flair.'),
      _t('phys-11', c, 'Sit against the wall until your legs file a complaint',
          'Take up an invisible chair against a wall and stay there as long as you can while narrating your inner monologue as your legs slowly begin negotiations. Longest dignified hold wins.'),
      _t('phys-12', c, 'Do ten steps of a brand-new walk you just invented',
          'Debut a never-before-seen way of walking — name it, demonstrate ten full steps of it, and explain when society should use it. Judged on originality and commitment.'),
      _t('phys-13', c, 'Touch five different door handles in the fastest time',
          'On your marks: sprint (safely) to touch five different door or cupboard handles in your home as fast as possible. Time yourself on camera. Announce your world record.'),
      _t('phys-14', c, 'Perform a synchronized routine with your own shadow or reflection',
          'Find a shadow or mirror and perform a perfectly synchronized duet: waves, spins, dramatic pauses. Judged on synchronization, which — to be fair — should be excellent.'),
      _t('phys-15', c, 'Spin around five times then walk a perfectly straight line',
          'Five gentle spins, then attempt to walk your straightest possible line along a hallway. Arms out, dignity optional. Have a soft landing zone and a spotter-couch nearby.'),
      _t('phys-16', c, 'Move a cushion across the floor using only your feet',
          'Hands behind your back or in your pockets: transport a cushion across the room using feet alone. Kicking is legal. Flinging is legendary.'),
      _t('phys-17', c, 'Hold a dramatic action-movie pose for 30 seconds',
          'Freeze mid-explosion-escape: one knee down, hair seemingly wind-blown, face set to "determined". Hold absolutely still for 30 seconds while narrating the scene around you.'),
      _t('phys-18', c, 'Crawl like a crab while balancing something on your tummy',
          'Assume the crab position, place a soft object on your midsection, and travel as far as you can before it slides off. Distance and crab-like menace both count.'),
    ];
  }

  // ---------------------------------------------------------------------
  // Kitchen Capers — ordinary kitchen stuff, no cooking skills needed.
  // ---------------------------------------------------------------------
  static List<Task> _kitchenCapersTasks() {
    const c = kitchenCapers;
    return [
      _t('kitchen-01', c, 'Butter a slice of bread wearing oven mitts',
          'Both hands in oven mitts (or thick socks). Butter one slice of bread edge to edge. Most elegant technique wins. Chef\'s composure required throughout.'),
      _t('kitchen-02', c, 'Make a face out of food and give it a name',
          'Arrange whatever is in your kitchen into a face on a plate. Introduce it to the camera by name and tell us one fact about its life. Do not let it see you eat later.'),
      _t('kitchen-03', c, 'Host a cooking show making a glass of water',
          'Present the preparation of a simple glass of water as if it were a five-star signature dish. Technique, plating, tasting notes — the works. Michelin is watching.'),
      _t('kitchen-04', c, 'Build the tallest stack of kitchen items that holds for ten seconds',
          'Tupperware, cups, boxes — build the highest tower of unbreakable kitchen things and step away for a ten-second hold. Any wobble adds suspense; any collapse ends the dream.'),
      _t('kitchen-05', c, 'Conduct a blind taste test on yourself and guess dramatically',
          'Have someone hand you three safe, known-to-you foods while your eyes are closed. Guess each one like a detective solving a murder. Confidence matters more than accuracy.'),
      _t('kitchen-06', c, 'Sort dry pasta, rice, or cereal by size using chopsticks or two spoons',
          'Pour out a small mixed pile and sort it into groups using only chopsticks or two teaspoons. You have two minutes. Precision under pressure. Tweezers are for cowards.'),
      _t('kitchen-07', c, 'Give a tour of your fridge like a nature documentary',
          'Open the fridge and, in your best hushed documentary voice, introduce its inhabitants: the elusive condiments, the ancient leftovers, the majestic milk. Respect the ecosystem.'),
      _t('kitchen-08', c, 'Peel a fruit or vegetable in one unbroken piece',
          'Orange, banana, clementine — your pick. Remove the peel in one continuous, unbroken piece and hold it up like a trophy. Slow and steady wins; snapped peels haunt forever.'),
      _t('kitchen-09', c, 'Set a fancy dinner table for a teddy bear in 90 seconds',
          'A very important stuffed guest is arriving. Lay the most formal place setting you can in 90 seconds, seat them, and welcome them like royalty.'),
      _t('kitchen-10', c, 'Transport water between two cups using only a spoon',
          'One cup full, one cup empty, one spoon, one minute. Move as much water as possible. Spillage will be silently judged.'),
      _t('kitchen-11', c, 'Invent a sandwich named after yourself and pitch it',
          'Create The [Your Name] using whatever\'s available, then pitch it to the camera as the next global sensation: origin story, tasting notes, slogan. You must take one proud bite.'),
      _t('kitchen-12', c, 'Perform a percussion piece on pots and pans',
          'Assemble a drum kit of cookware and perform an original 30-second composition. Wooden spoons recommended. A dramatic cymbal finish (pot lid) is basically mandatory.'),
      _t('kitchen-13', c, 'Eat a snack with the most elaborate cutlery technique',
          'Consume a simple snack — a cracker, a grape, a slice of toast — using full formal cutlery technique and the manners of a Victorian aristocrat. Pinkies up. Narrate the etiquette.'),
      _t('kitchen-14', c, 'Balance a spoon on your nose for ten seconds while smiling',
          'Classic. Spoon. Nose. Ten seconds. But you must also hold a warm, natural smile the entire time, as though this is completely normal. Cutlery charisma wins.'),
      _t('kitchen-15', c, 'Arrange your snacks into a rainbow',
          'Raid the cupboard and arrange foods into the most complete color rainbow you can. Present each color like a weather reporter unveiling tomorrow\'s forecast.'),
      _t('kitchen-16', c, 'Unpack groceries (or restock a shelf) in reverse',
          'Film yourself carefully placing items one by one onto the counter or shelf with reversed-looking movements, so the video looks like time flowing backwards. Walk backwards out of frame. Cinema.'),
    ];
  }

  // ---------------------------------------------------------------------
  // Outdoor & Anywhere — garden, park, driveway, or wherever you are.
  // ---------------------------------------------------------------------
  static List<Task> _outdoorAnywhereTasks() {
    const c = outdoorAnywhere;
    return [
      _t('outdoor-01', c, 'Find the most interesting thing within 20 steps',
          'You have 20 steps in any direction. Return with the most fascinating object you can find and deliver a passionate 30-second museum lecture about it. Return it afterwards, professor.'),
      _t('outdoor-02', c, 'Interview a tree, lamppost, or fence about local news',
          'Take the microphone (any stick or spoon) to a tall local resident and conduct a hard-hitting interview about neighborhood gossip. You must also voice their answers. Stay professional.'),
      _t('outdoor-03', c, 'Recreate a famous statue using yourself and the landscape',
          'Pick a famous statue or monument and become it, using whatever scenery is around you. Hold the pose while a narrator (also you) explains its historical significance.'),
      _t('outdoor-04', c, 'Give a live weather report from your window, doorstep, or garden',
          'Report the current weather with the intensity of a reporter in a category-five hurricane — even if it is mildly pleasant. Grip something for stability. Fight for your life.'),
      _t('outdoor-05', c, 'Race two leaves, sticks, or pebbles and commentate the finish',
          'Set up a race between two found objects — dropped, rolled, or floated — and deliver breathless photo-finish commentary. Interview the winner afterwards.'),
      _t('outdoor-06', c, 'Walk to the nearest corner as five different characters',
          'Same short route, five walks: a spy, a superstar, someone very late, someone in zero gravity, and one of your invention. Judged on how different the five journeys feel.'),
      _t('outdoor-07', c, 'Draw a masterpiece on the ground with water, chalk, or a stick',
          'Using water on pavement, chalk, or a stick in dirt, create a large-scale artwork and unveil it to the camera from your grandest angle. Title it something profound.'),
      _t('outdoor-08', c, 'Build a tiny home for a bug (no bugs required to move in)',
          'Construct a desirable insect residence from leaves, twigs, and pebbles, then film the real-estate tour: entrance, living quarters, and a garden feature. Location, location, location.'),
      _t('outdoor-09', c, 'Perform an extremely local tour guide routine',
          'Give an enthusiastic guided tour of a five-meter radius: "And on your LEFT, an absolutely historic bush." Everything is a landmark if you believe. Judged on unearned enthusiasm.'),
      _t('outdoor-10', c, 'Balance a stick, leaf, or pebble on your open palm while walking',
          'Place something found and awkward flat on your open palm and walk ten steps without it falling. If it drops, restart the walk on camera. Grace under pressure.'),
      _t('outdoor-11', c, 'Throw something soft into something distant',
          'Choose a soft projectile and a distant target — bucket, hoop, gap between trees. Sink the shot from the most impressive distance you dare, and celebrate like it won the World Cup.'),
      _t('outdoor-12', c, 'Film a nature documentary about a human (your camera operator or a volunteer)',
          'Narrate a wildlife documentary where the featured animal is a person doing something mundane. "Here we observe the human, foraging for snacks..." Whisper. Always whisper.'),
      _t('outdoor-13', c, 'Make the most satisfying pile of things',
          'Collect and stack found objects — stones, pinecones, leaves — into the neatest, most satisfying arrangement you can. Reveal it with a slow cinematic pan and a single word: "Perfection."'),
      _t('outdoor-14', c, 'Stage a dramatic slow-motion run toward the camera',
          'From a distance, run toward the camera in glorious slow motion as if reuniting with a long-lost friend. Wind in your hair, emotion on your face. The friend can be a sandwich.'),
    ];
  }

  // ---------------------------------------------------------------------
  // Family Face-off — head-to-head tasks that need a partner or rival.
  // ---------------------------------------------------------------------
  static List<Task> _familyFaceOffTasks() {
    const c = familyFaceOff;
    return [
      _t('family-01', c, 'Win a compliment battle',
          'Face off with a partner: trade increasingly extravagant compliments back and forth. First to laugh, repeat a compliment, or run dry loses. Film the whole glorious duel.'),
      _t('family-02', c, 'Mirror each other for 30 seconds without laughing',
          'Stand face to face. One leads, one mirrors, then swap halfway. Any giggle is a penalty. Slow-motion face stretches are legal and encouraged.'),
      _t('family-03', c, 'Feed each other a snack blindfolded (spotters on)',
          'Both partners close their eyes (or wear loose blindfolds) and attempt to feed each other one small, safe snack. Slowly. Judged on teamwork, accuracy, and dignity lost.'),
      _t('family-04', c, 'Guess the drawing on your back',
          'One person "draws" a simple picture on the other\'s back with a finger; the receiver must guess it. Three rounds, swap roles. Document every outrageous wrong guess.'),
      _t('family-05', c, 'Hold a two-person plank bridge card game',
          'Both partners hold a plank (knees allowed!) facing each other while playing one quick round of rock-paper-scissors best-of-five. Collapse = concede. Trash talk permitted.'),
      _t('family-06', c, 'Have a whisper-shout argument about something tiny',
          'Stage a furious argument about something utterly trivial — the correct way to hang a towel — but you may only whisper. Full fury, minimum volume. Most intense hush wins.'),
      _t('family-07', c, 'Complete a three-legged kitchen errand',
          'Tie ankles loosely together (a scarf works) and complete a simple errand as one four-legged creature: fetch a snack, deliver a cup, return safely. Coordination will be mocked. By us.'),
      _t('family-08', c, 'Recreate a famous painting using each other',
          'One of you is the artwork, one is the pushy museum director arranging it. Recreate a famous painting, then swap. Judged on likeness and how bossy the director gets.'),
      _t('family-09', c, 'Play emotional ping-pong',
          'Face each other. Player one "serves" an emotion (huge joy); player two must return a bigger one (cosmic despair). Rally back and forth until someone breaks. No words, all face.'),
      _t('family-10', c, 'Do a trust walk narrated like a nature documentary',
          'One partner closes their eyes; the other guides them safely around the room using only voice commands — while ALSO narrating the journey like a wildlife documentary. Swap and repeat.'),
      _t('family-11', c, 'Have a staring contest where you\'re both allowed to talk',
          'Eyes locked. No blinking. But here\'s the twist: you must maintain polite small talk about the weather the entire time. First blink or laugh loses. Utterly civilized. Utterly brutal.'),
      _t('family-12', c, 'Style each other\'s hair in 60 seconds, then walk the runway',
          'Sixty seconds each to give your partner a bold new hairstyle using clips, gel-free sculpting, or accessories. Then both walk the catwalk and announce your looks. Own it.'),
      _t('family-13', c, 'Teach your partner a made-up handshake, then perform it at speed',
          'Invent a secret handshake with at least six moves, teach it on camera, then perform it three times, getting faster each time. The final attempt should be dangerously quick.'),
      _t('family-14', c, 'Sing a duet where you alternate every single word',
          'Pick a song everyone knows and sing it together — alternating every single word between you. Keep the tune going no matter what. Trainwrecks are worth full points if you commit.'),
      _t('family-15', c, 'Guess the household object by touch alone',
          'One partner closes their eyes and must identify three safe mystery objects by touch, while the other selects them and gives unhelpful hints. Swap roles. Confidence beats correctness.'),
      _t('family-16', c, 'Stage the world\'s politest sword fight',
          'Duel with rolled-up newspapers or paper-towel tubes, but every strike must be accompanied by an apology and every parry by a thank-you. Bow before and after. En garde, sorry.'),
    ];
  }

  // ---------------------------------------------------------------------
  // Word & Wit — talking-to-camera tasks. Just you and your brain.
  // ---------------------------------------------------------------------
  static List<Task> _wordAndWitTasks() {
    const c = wordAndWit;
    return [
      _t('word-01', c, 'Deliver a passionate sales pitch for air',
          'Sixty seconds to sell AIR to the camera. Features, benefits, testimonials, limited-time offer. By the end we should genuinely be reaching for our wallets.'),
      _t('word-02', c, 'Give an acceptance speech for an award you did not win',
          'You have just won Best Person at Standing In This Room. Deliver the tearful acceptance speech: thank your family, your rivals, and one inanimate object that believed in you.'),
      _t('word-03', c, 'Explain how to make toast to an alien',
          'An alien with no concept of bread, heat, or breakfast needs toast instructions. Leave nothing to assumption. One missed step and the invasion begins.'),
      _t('word-04', c, 'Narrate your last hour like a sports commentator',
          'Recap the previous hour of your life with the roaring urgency of a cup-final commentator. "AND THEY\'VE OPENED THE FRIDGE — UNBELIEVABLE SCENES!"'),
      _t('word-05', c, 'Speak for 45 seconds without saying "um", "uh", or "like"',
          'Pick any topic and talk fluently for 45 seconds. One filler word and you must start the whole thing again, on camera, with your shame included in the submission.'),
      _t('word-06', c, 'Tell a gripping bedtime story about your least interesting object',
          'Find the most boring object you own and tell its epic bedtime saga: humble origins, great trials, eventual triumph. End with "the end" and a meaningful stare.'),
      _t('word-07', c, 'Deliver a movie-trailer voice-over for your day tomorrow',
          'In your deepest trailer voice: "In a world... where laundry waits for no one..." Preview tomorrow like a summer blockbuster. Include a dramatic twist and a release date.'),
      _t('word-08', c, 'Give a TED talk on why socks disappear',
          'Two minutes maximum. Present your unified theory of sock loss with visual aids, statistics you invented, and a moving personal anecdote. Change how we think forever.'),
      _t('word-09', c, 'Rhyme everything you say for 60 seconds',
          'Talk about your day, but every sentence must rhyme with the one before it. Pausing to think is fine; breaking the rhyme is defeat. Bonus swagger if it becomes a rap.'),
      _t('word-10', c, 'Read a shopping or to-do list like Shakespeare',
          'Take your most mundane list and perform it as a devastating Shakespearean monologue. "O milk! Semi-skimmed, and yet... whole of heart." Real tears welcome.'),
      _t('word-11', c, 'Host a game show where every answer is "spoon"',
          'You are host AND all three contestants. Ask increasingly difficult quiz questions. The answer is always "spoon". The host must never acknowledge this. Play it completely straight.'),
      _t('word-12', c, 'Argue passionately for breakfast\'s most underrated item',
          'Pick the most overlooked component of breakfast — the humble crumb, the jam-jar lid — and deliver a courtroom-style closing argument in its defense. The jury is the camera.'),
      _t('word-13', c, 'Teach a masterclass in a skill you invented today',
          'Welcome, students, to Advanced Cushion Diplomacy (or whatever you invent). Teach a structured lesson with a warm-up, a demonstration, and homework. Absolute authority required.'),
      _t('word-14', c, 'Describe your home like an over-the-top real estate listing',
          'Walk one room and pitch it like a luxury property agent: "This corridor OOZES potential." Every flaw is a feature. Every wall is a lifestyle. Close with an outrageous asking price.'),
      _t('word-15', c, 'Answer rapid-fire questions as your own evil twin',
          'Introduce your evil twin (same face, worse manners) and answer ten quick questions about yourself IN CHARACTER: favorite food, hobbies, opinion of the real you. Commit to the bit.'),
      _t('word-16', c, 'Give a eulogy for a piece of expired food or a dead pen',
          'Gather us together to remember a pen that will write no more, or a yogurt gone before its time. Somber music optional (hum it yourself). Not a dry eye in the house.'),
      _t('word-17', c, 'Do a weather forecast for your emotions this week',
          'Present next week\'s emotional forecast with full meteorological professionalism: "Monday brings scattered grumpiness, clearing to mild delight by lunch." Include a five-day outlook.'),
      _t('word-18', c, 'Recite the alphabet as a slowly boiling kettle of rage',
          'Start at A perfectly calm. By M, mildly irritated. By Z, operatic fury. Just letters — the emotional journey does all the work. Then exhale, smile, and say "thank you".'),
      _t('word-19', c, 'Convince us you invented a common household object',
          'Choose something ordinary — the clothes peg, the doorstop — and tell the stirring true-ish story of the day YOU invented it. Include the setbacks, the doubters, the breakthrough moment.'),
      _t('word-20', c, 'Commentate your own attempt at a simple task, in two voices',
          'Do something simple — stack three cups, fold a shirt — while providing BOTH the play-by-play commentator and the skeptical pundit analyzing your performance. Argue with yourself.'),
    ];
  }
}
