import 'package:fake_async/fake_async.dart';
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

  group('GeigerTicker (finding 6 — the geiger must not go silent while steered)',
      () {
    test(
        'continuous 250ms heat updates at constant heat still tick at the '
        'expected cadence', () {
      fakeAsync((async) {
        var ticks = 0;
        final ticker = GeigerTicker(
          onTick: () => ticks++,
          clock: () => async.elapsed.inMilliseconds,
        );
        // Warm heat: interval ≈ 505 ms, but the hider streams heat every 250 ms.
        const heat = 0.5;
        final interval = ClueHeat.tickIntervalMsForHeat(heat)!;
        ticker.start(heat);

        // Feed heat every 250 ms for 3 s, exactly like a live hider steering.
        const totalMs = 3000;
        const feedEvery = 250;
        for (var t = feedEvery; t <= totalMs; t += feedEvery) {
          async.elapse(const Duration(milliseconds: feedEvery));
          ticker.setHeat(heat);
        }

        // A naïve "cancel + full fresh interval on every update" would starve to
        // ZERO ticks (each 250 ms update pushes the 505 ms tick out of reach).
        // Re-arming keeps the cadence: ~ totalMs / interval ticks.
        final expected = totalMs ~/ interval;
        expect(ticks, greaterThanOrEqualTo(expected - 1),
            reason: 'the geiger keeps ticking while heat streams in');
        expect(ticks, isNot(0));
        ticker.dispose();
        async.flushTimers();
      });
    });

    test('a shorter interval (heat rising) pulls the next tick in sooner', () {
      fakeAsync((async) {
        var ticks = 0;
        final ticker = GeigerTicker(
          onTick: () => ticks++,
          clock: () => async.elapsed.inMilliseconds,
        );
        ticker.start(0.1); // cold → long interval
        async.elapse(const Duration(milliseconds: 100));
        ticker.setHeat(1.0); // hot → fastest interval (110 ms)
        // The tick should fire at the pulled-in deadline, not the original.
        async.elapse(const Duration(milliseconds: 120));
        expect(ticks, greaterThanOrEqualTo(1));
        ticker.dispose();
        async.flushTimers();
      });
    });

    test('heat dropping to silence cancels ticking', () {
      fakeAsync((async) {
        var ticks = 0;
        final ticker = GeigerTicker(
          onTick: () => ticks++,
          clock: () => async.elapsed.inMilliseconds,
        );
        ticker.start(0.8);
        expect(ticker.isTicking, isTrue);
        ticker.setHeat(0.0); // freezing
        expect(ticker.isTicking, isFalse);
        async.elapse(const Duration(seconds: 2));
        expect(ticks, 0);
        ticker.dispose();
      });
    });
  });
}
