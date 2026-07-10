import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/features/house_hunt/data/house_hunt_prompts.dart';

void main() {
  group('HouseHuntPrompts deck integrity', () {
    test('has a healthy, family-sized deck (>= 40 prompts)', () {
      expect(HouseHuntPrompts.all.length, greaterThanOrEqualTo(40));
    });

    test('every id is unique', () {
      final ids = HouseHuntPrompts.all.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('every prompt text is unique', () {
      final texts = HouseHuntPrompts.all.map((p) => p.prompt).toList();
      expect(texts.toSet().length, texts.length);
    });

    test('every prompt is non-empty, trimmed, and short/kid-readable', () {
      for (final p in HouseHuntPrompts.all) {
        expect(p.id.trim(), isNotEmpty, reason: 'id blank for "${p.prompt}"');
        expect(p.prompt.trim(), isNotEmpty, reason: 'blank prompt ${p.id}');
        expect(p.prompt, equals(p.prompt.trim()),
            reason: 'untrimmed prompt ${p.id}');
        expect(p.prompt.length, lessThanOrEqualTo(120),
            reason: 'prompt too long: ${p.id}');
      }
    });

    test('every vibe is represented', () {
      final vibes = HouseHuntPrompts.all.map((p) => p.vibe).toSet();
      expect(vibes, containsAll(HuntVibe.values));
    });
  });

  group('deal', () {
    test('deals exactly huntSize distinct prompts', () {
      final hand = HouseHuntPrompts.deal(random: Random(1));
      expect(hand.length, HouseHuntPrompts.huntSize);
      expect(hand.map((p) => p.id).toSet().length, hand.length);
    });

    test('is deterministic for a fixed seed (reshuffle stability)', () {
      final a = HouseHuntPrompts.deal(random: Random(42));
      final b = HouseHuntPrompts.deal(random: Random(42));
      expect(a.map((p) => p.id), b.map((p) => p.id));
    });

    test('reshuffling with a different seed generally changes the hand', () {
      final a = HouseHuntPrompts.deal(random: Random(1));
      final b = HouseHuntPrompts.deal(random: Random(2));
      expect(a.map((p) => p.id).toList(), isNot(b.map((p) => p.id).toList()));
    });

    test('never deals a prompt in the exclude set', () {
      final first = HouseHuntPrompts.deal(random: Random(7));
      final second =
          HouseHuntPrompts.deal(random: Random(9), exclude: first);
      final firstIds = first.map((p) => p.id).toSet();
      expect(second.any((p) => firstIds.contains(p.id)), isFalse);
    });

    test('respects a custom count', () {
      final hand = HouseHuntPrompts.deal(count: 3, random: Random(3));
      expect(hand.length, 3);
    });
  });

  group('randomExcluding (swap-one)', () {
    test('returns a prompt whose id is not excluded', () {
      final hand = HouseHuntPrompts.deal(random: Random(5));
      final ids = hand.map((p) => p.id).toSet();
      // Swap slot 0: the replacement must differ from every current slot.
      final replacement = HouseHuntPrompts.randomExcluding(ids, random: Random(5));
      expect(ids.contains(replacement.id), isFalse);
    });

    test('falls back to a valid prompt when everything is excluded', () {
      final allIds = HouseHuntPrompts.all.map((p) => p.id).toSet();
      final replacement =
          HouseHuntPrompts.randomExcluding(allIds, random: Random(1));
      expect(HouseHuntPrompts.all.contains(replacement), isTrue);
    });
  });
}
