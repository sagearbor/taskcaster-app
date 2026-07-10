import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/features/ar_lab/presentation/widgets/ar_lab_log.dart';

// Smoke tests for the AR Lab diagnostic log pane ONLY. The AR Lab screen itself
// hosts a native ARView platform view (camera + ARCore) which cannot be
// instantiated in a widget test — that flow is device-only and verified on two
// physical phones per docs/cloud-anchors-spike.md. The log pane, however, is a
// pure Flutter widget, so we can exercise its rendering here.
void main() {
  testWidgets('empty log shows the placeholder hint', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ArLabLogPane(lines: []))),
    );

    expect(
      find.textContaining('Diagnostic log'),
      findsOneWidget,
    );
  });

  testWidgets('renders each log line with its timestamp', (tester) async {
    final lines = [
      ArLabLogLine('initGoogleCloudAnchorMode()', ArLabLogLevel.step),
      ArLabLogLine('onAnchorUploaded — cloud id abc123', ArLabLogLevel.success),
      ArLabLogLine('onError: Failed to host', ArLabLogLevel.error),
    ];

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ArLabLogPane(lines: lines))),
    );

    // Lines render as RichText (timestamp span + message span), so match spans.
    expect(find.textContaining('initGoogleCloudAnchorMode()', findRichText: true),
        findsOneWidget);
    expect(find.textContaining('onAnchorUploaded', findRichText: true),
        findsOneWidget);
    expect(find.textContaining('onError', findRichText: true), findsOneWidget);
    // Each line is prefixed by an HH:MM:SS.mmm clock stamp.
    expect(
        find.textContaining(RegExp(r'\d{2}:\d{2}:\d{2}\.\d{3}'),
            findRichText: true),
        findsNWidgets(3));
  });

  test('ArLabLogLine formats a zero-padded millisecond clock', () {
    final line = ArLabLogLine('x', ArLabLogLevel.info);
    expect(line.clock, matches(RegExp(r'^\d{2}:\d{2}:\d{2}\.\d{3}$')));
  });
}
