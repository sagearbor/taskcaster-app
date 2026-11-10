import 'dart:convert';

/// A guest's display name: one adjective and one noun, picked from the uid so
/// the same player is always the same "Damp Colander" on every device and in
/// every feed post.
///
/// Rules for the word lists (they reach every player, so keep them clean):
/// - Adjectives describe a mood or a manner, never a body, a mind, a group or
///   an identity (no "fat", "mad", "old", nationalities and so on).
/// - Nouns are household objects, food, instruments and animals. No people,
///   jobs, places or anything that could be read as a nickname for a person.
/// - One word each, so the name is always exactly two words.
/// `test/core/utils/funny_names_test.dart` checks them against a blocklist.
class FunnyNames {
  FunnyNames._();

  static const List<String> adjectives = [
    'Ambitious',
    'Apologetic',
    'Bashful',
    'Bewildered',
    'Ceremonial',
    'Chaotic',
    'Crumpled',
    'Damp',
    'Determined',
    'Dignified',
    'Disgruntled',
    'Dubious',
    'Earnest',
    'Flustered',
    'Frantic',
    'Furtive',
    'Gallant',
    'Haunted',
    'Heroic',
    'Ill-advised',
    'Indignant',
    'Inexplicable',
    'Jaunty',
    'Lavish',
    'Lukewarm',
    'Majestic',
    'Misunderstood',
    'Ominous',
    'Optimistic',
    'Overconfident',
    'Overdressed',
    'Peckish',
    'Pensive',
    'Plucky',
    'Pompous',
    'Precarious',
    'Quizzical',
    'Rattled',
    'Reluctant',
    'Resigned',
    'Restless',
    'Rogue',
    'Sheepish',
    'Sincere',
    'Smug',
    'Soggy',
    'Startled',
    'Stoic',
    'Suspicious',
    'Tenacious',
    'Tepid',
    'Theatrical',
    'Unbothered',
    'Underprepared',
    'Unflappable',
    'Unlicensed',
    'Unrepentant',
    'Unsupervised',
    'Wistful',
    'Wobbly',
  ];

  static const List<String> nouns = [
    'Accordion',
    'Badger',
    'Biscuit',
    'Blancmange',
    'Bollard',
    'Cardigan',
    'Colander',
    'Courgette',
    'Crouton',
    'Crumpet',
    'Custard',
    'Deckchair',
    'Doily',
    'Doorstop',
    'Ferret',
    'Flannel',
    'Footstool',
    'Gazebo',
    'Gnome',
    'Goose',
    'Haddock',
    'Hatstand',
    'Hedgehog',
    'Hovercraft',
    'Kazoo',
    'Kettle',
    'Kipper',
    'Ladle',
    'Lampshade',
    'Llama',
    'Meringue',
    'Otter',
    'Ottoman',
    'Pancake',
    'Parsnip',
    'Pelican',
    'Penguin',
    'Pigeon',
    'Pineapple',
    'Radish',
    'Saucepan',
    'Scone',
    'Slipper',
    'Spatula',
    'Sponge',
    'Spoon',
    'Sprout',
    'Teapot',
    'Teaspoon',
    'Thimble',
    'Toaster',
    'Trifle',
    'Trolley',
    'Trombone',
    'Tuba',
    'Turnip',
    'Umbrella',
    'Walrus',
    'Weathervane',
    'Wheelbarrow',
  ];

  /// The funny name for [uid]. Deterministic on every platform: it uses
  /// FNV-1a over the UTF-8 bytes rather than [String.hashCode], which differs
  /// between the VM and the web.
  static String forUid(String uid) {
    final h = fnv1a32(uid);
    final adjective = adjectives[h % adjectives.length];
    final noun = nouns[(h ~/ adjectives.length) % nouns.length];
    return '$adjective $noun';
  }

  /// True when [name] is a stand-in rather than something the player chose:
  /// empty, the old "Guest" / "User" placeholders, or one of our own funny
  /// names. Signing in with Google or Apple replaces a placeholder with the
  /// provider's name; a name the player typed is never replaced.
  static bool isPlaceholder(String? name) {
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) return true;
    final lower = trimmed.toLowerCase();
    if (lower == 'guest' || lower == 'user' || lower == 'player') return true;
    return isFunnyName(trimmed);
  }

  /// True when [name] is "<adjective> <noun>" from these lists.
  static bool isFunnyName(String name) {
    final parts = name.trim().split(' ');
    return parts.length == 2 &&
        adjectives.contains(parts[0]) &&
        nouns.contains(parts[1]);
  }

  /// 32-bit FNV-1a. Pure arithmetic below 2^53, so the web (where ints are
  /// doubles) gets the same answer as the VM.
  static int fnv1a32(String input) {
    const offsetBasis = 2166136261;
    const twoTo32 = 4294967296;
    var h = offsetBasis;
    for (final byte in utf8.encode(input)) {
      final low = h % 256;
      h = h - low + (low ^ byte);
      // h * 16777619 (2^24 + 403) mod 2^32, without overflowing 2^53.
      h = ((h % 256) * 16777216 + h * 403) % twoTo32;
    }
    return h;
  }
}
