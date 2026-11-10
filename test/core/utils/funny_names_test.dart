import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/utils/funny_names.dart';

void main() {
  group('FunnyNames.forUid', () {
    test('the same uid always gets the same name', () {
      const uid = 'aB3xY9kLmN0pQrStUvWxYz12';
      expect(FunnyNames.forUid(uid), FunnyNames.forUid(uid));
    });

    test('uses real 32-bit FNV-1a so names never drift between platforms', () {
      // Published FNV-1a 32-bit reference vectors.
      expect(FunnyNames.fnv1a32(''), 0x811c9dc5);
      expect(FunnyNames.fnv1a32('a'), 0xe40c292c);
      expect(FunnyNames.fnv1a32('foobar'), 0xbf9cf968);
    });

    test('is always exactly two words from the lists', () {
      for (var i = 0; i < 500; i++) {
        final name = FunnyNames.forUid('uid-$i');
        expect(name.split(' '), hasLength(2), reason: name);
        expect(FunnyNames.isFunnyName(name), isTrue, reason: name);
      }
    });

    test('spreads uids across many names', () {
      final names = <String>{};
      final adjectives = <String>{};
      final nouns = <String>{};
      for (var i = 0; i < 2000; i++) {
        final name = FunnyNames.forUid('user_$i');
        names.add(name);
        adjectives.add(name.split(' ')[0]);
        nouns.add(name.split(' ')[1]);
      }
      // 3600 combinations; 2000 draws should land on well over 1000.
      expect(names.length, greaterThan(1000));
      expect(adjectives.length, FunnyNames.adjectives.length);
      expect(nouns.length, FunnyNames.nouns.length);
    });
  });

  group('word lists', () {
    test('are about sixty unique, capitalised single words each', () {
      for (final list in [FunnyNames.adjectives, FunnyNames.nouns]) {
        expect(list.length, greaterThanOrEqualTo(55));
        expect(list.toSet().length, list.length, reason: 'duplicates');
        for (final w in list) {
          expect(w.contains(' '), isFalse, reason: w);
          expect(w[0], w[0].toUpperCase(), reason: w);
        }
      }
    });

    test('the longest name still fits a feed card header', () {
      final longestAdj = FunnyNames.adjectives
          .reduce((a, b) => a.length >= b.length ? a : b);
      final longestNoun =
          FunnyNames.nouns.reduce((a, b) => a.length >= b.length ? a : b);
      expect('$longestAdj $longestNoun'.length, lessThanOrEqualTo(26));
    });

    // Whole words that must never appear: remarks about bodies, minds or
    // identities, nationalities, swearing, toilet words, violence.
    const blockedWords = {
      'fat', 'thin', 'skinny', 'ugly', 'old', 'bald', 'short', 'tall',
      'smelly', 'sweaty', 'hairy', 'stupid', 'dumb', 'idiot', 'moron',
      'crazy', 'insane', 'mad', 'psycho', 'lame', 'mental', 'nutter',
      'retard', 'retarded', 'gay', 'queer', 'black', 'white', 'brown',
      'yellow', 'red', 'swede', 'french', 'dutch', 'turkey', 'welsh',
      'scotch', 'irish', 'english', 'gypsy', 'tranny', 'lesbian', 'blind',
      'deaf', 'dumpling', 'pig', 'cow', 'cabbage', 'nun', 'vicar', 'priest',
      'damn', 'hell', 'bloody', 'bugger', 'sod', 'ass', 'arse', 'butt',
      'bum', 'boob', 'boobs', 'willy', 'dick', 'cock', 'balls', 'nuts',
      'poo', 'pee', 'wee', 'fart', 'plunger', 'toilet', 'loo', 'sex', 'sexy',
      'naked', 'drunk', 'kill', 'dead', 'killer', 'gun', 'bomb',
    };
    // Fragments that must not appear anywhere, even inside a longer word.
    const blockedFragments = [
      'fuck', 'shit', 'cunt', 'twat', 'wank', 'slut', 'whore', 'bitch',
      'nig', 'fag', 'rape', 'piss', 'spaz', 'spastic', 'paki', 'chink',
      'kike', 'homo', 'dyke',
    ];

    test('every word passes the blocklist', () {
      for (final w in [...FunnyNames.adjectives, ...FunnyNames.nouns]) {
        final lower = w.toLowerCase();
        for (final part in lower.split('-')) {
          expect(blockedWords.contains(part), isFalse, reason: w);
        }
        for (final f in blockedFragments) {
          expect(lower.contains(f), isFalse, reason: '$w contains $f');
        }
      }
    });
  });

  group('FunnyNames.isPlaceholder', () {
    test('treats empty, Guest and our own names as placeholders', () {
      expect(FunnyNames.isPlaceholder(null), isTrue);
      expect(FunnyNames.isPlaceholder('  '), isTrue);
      expect(FunnyNames.isPlaceholder('Guest'), isTrue);
      expect(FunnyNames.isPlaceholder('guest'), isTrue);
      expect(FunnyNames.isPlaceholder(FunnyNames.forUid('x')), isTrue);
    });

    test('never treats a name the player chose as a placeholder', () {
      expect(FunnyNames.isPlaceholder('Sophie'), isFalse);
      expect(FunnyNames.isPlaceholder('Damp Sophie'), isFalse);
      expect(FunnyNames.isPlaceholder('Greg Davies'), isFalse);
    });
  });
}
