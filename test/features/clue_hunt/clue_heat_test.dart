import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/features/clue_hunt/domain/clue_heat.dart';

void main() {
  group('tickIntervalMsForHeat', () {
    test('is silent when ice cold', () {
      expect(ClueHeat.tickIntervalMsForHeat(0.0), isNull);
      expect(ClueHeat.tickIntervalMsForHeat(ClueHeat.silentBelow - 0.001),
          isNull);
    });

    test('ticks fastest at full heat and slowest just above silence', () {
      expect(ClueHeat.tickIntervalMsForHeat(1.0), ClueHeat.fastestMs);
      expect(ClueHeat.tickIntervalMsForHeat(ClueHeat.silentBelow),
          closeTo(ClueHeat.slowestMs, 30));
    });

    test('the interval shortens monotonically as heat rises', () {
      final warm = ClueHeat.tickIntervalMsForHeat(0.4)!;
      final hot = ClueHeat.tickIntervalMsForHeat(0.9)!;
      expect(hot, lessThan(warm));
    });

    test('heat above 1.0 clamps to the fastest interval', () {
      expect(ClueHeat.tickIntervalMsForHeat(5.0), ClueHeat.fastestMs);
    });
  });

  group('bandForHeat', () {
    test('maps heat into silent/cold/warm/hot bands', () {
      expect(ClueHeat.bandForHeat(0.0), HeatBand.silent);
      expect(ClueHeat.bandForHeat(0.2), HeatBand.cold);
      expect(ClueHeat.bandForHeat(0.5), HeatBand.warm);
      expect(ClueHeat.bandForHeat(0.9), HeatBand.hot);
    });
  });
}
