/// A small, kid-friendly bank of drawing prompts used by the "Same prompt"
/// modes (everyone draws the SAME thing). Picking is deterministic given a seed
/// so a session converges on the same prompt across every device and so tests
/// are reproducible — see [TelephoneSession.started] / [TelephoneSession.playAgain].
class TelephonePrompts {
  const TelephonePrompts._();

  static const List<String> all = [
    'A cat riding a skateboard on the moon',
    'A dragon who is afraid of broccoli',
    'A robot baking a birthday cake',
    'A penguin hosting a cooking show',
    'A wizard losing a fight with an umbrella',
    'A dinosaur trying to use a smartphone',
    'A banana riding a unicycle uphill',
    'A ghost who is scared of the dark',
    'A snail winning an Olympic gold medal',
    'A shark wearing roller skates',
    'A grumpy cloud raining on a picnic',
    'An octopus playing every instrument in a band',
    'A superhero whose power is making toast',
    'A frog driving a monster truck',
    'A pirate searching for the TV remote',
    'A unicorn at a fancy tea party',
    'A bear who really wants to be a ballerina',
    'A spaceship made entirely of cheese',
    'A turtle in a hurry to catch a bus',
    'A vampire who only drinks tomato soup',
    'A llama wearing a tiny top hat',
    'A monkey teaching a yoga class',
    'A hedgehog rolling down a giant hill',
    'A whale trying to fit into a swimming pool',
  ];

  /// A stable prompt for [seed]. Same seed → same prompt, on every device.
  static String pick(int seed) => all[seed.abs() % all.length];
}
