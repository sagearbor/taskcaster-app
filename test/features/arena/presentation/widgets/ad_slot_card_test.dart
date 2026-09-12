import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/config/environment.dart';
import 'package:taskcaster_app/features/arena/presentation/widgets/ad_slot_card.dart';

void main() {
  tearDown(() {
    AdSlotCard.debugAlwaysShow = false;
  });

  testWidgets('renders nothing when ads are disabled and debug override is '
      'off', (tester) async {
    expect(AppConfig.adsEnabled, isFalse,
        reason: 'ads are deliberately not wired up this round — see '
            'docs/PRODUCT_DIRECTION.md §2.6/§7');

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AdSlotCard())),
    );

    expect(find.text('Sponsored'), findsNothing);
    expect(find.byType(SizedBox), findsWidgets);
  });

  testWidgets('renders the placeholder card when debugAlwaysShow is set',
      (tester) async {
    AdSlotCard.debugAlwaysShow = true;

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AdSlotCard())),
    );

    expect(find.text('Sponsored'), findsOneWidget);
    expect(find.text('Ad'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Continue'), findsOneWidget);
  });

  testWidgets('Continue button invokes onContinue', (tester) async {
    AdSlotCard.debugAlwaysShow = true;
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AdSlotCard(onContinue: () => tapped = true)),
      ),
    );

    await tester.tap(find.text('Continue'));
    await tester.pump();

    expect(tapped, isTrue);
  });

  group('Arena ad cadence (adEvery = 6)', () {
    // Mirrors ArenaLoaded.adEvery: show the ad before every 6th post, i.e.
    // when (index + 1) % 6 == 0.
    bool shouldShowAdBefore(int index, {int adEvery = 6}) =>
        (index + 1) % adEvery == 0;

    test('shows before the 6th, 12th, 18th... post (0-based index)', () {
      expect(shouldShowAdBefore(5), isTrue); // 6th post
      expect(shouldShowAdBefore(11), isTrue); // 12th post
      expect(shouldShowAdBefore(17), isTrue); // 18th post
    });

    test('does not show on other posts', () {
      for (final i in [0, 1, 2, 3, 4, 6, 7, 8, 9, 10]) {
        expect(shouldShowAdBefore(i), isFalse, reason: 'index $i');
      }
    });
  });
}
