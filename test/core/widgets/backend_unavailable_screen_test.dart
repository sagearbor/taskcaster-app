import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/widgets/backend_unavailable_screen.dart';

void main() {
  Widget wrap(Future<void> Function() onRetry) =>
      MaterialApp(home: BackendUnavailableScreen(onRetry: onRetry));

  final retry = find.byKey(const ValueKey('backend-unavailable-retry'));

  testWidgets('shows the error and a Retry button', (tester) async {
    await tester.pumpWidget(wrap(() async {}));

    expect(find.text("Can't reach TaskCaster"), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('Retry calls onRetry and disables itself while running',
      (tester) async {
    final completer = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(wrap(() {
      calls++;
      return completer.future;
    }));

    await tester.tap(retry);
    await tester.pump();
    expect(calls, 1);

    // Tapping again while the first attempt is in flight does nothing.
    await tester.tap(retry, warnIfMissed: false);
    await tester.pump();
    expect(calls, 1);

    completer.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('a failed retry keeps the screen up and re-enables Retry',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(wrap(() async {
      calls++;
      throw Exception('still down');
    }));

    await tester.tap(retry);
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.textContaining('Still no luck'), findsOneWidget);

    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(calls, 2);
  });
}
