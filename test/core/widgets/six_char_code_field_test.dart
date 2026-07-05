import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/widgets/six_char_code_field.dart';

void main() {
  Future<void> pumpField(
    WidgetTester tester, {
    TextEditingController? controller,
    ValueChanged<String>? onCompleted,
    ValueChanged<String>? onChanged,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SixCharCodeField(
              controller: controller,
              onCompleted: onCompleted,
              onChanged: onChanged,
            ),
          ),
        ),
      ),
    );
  }

  group('SixCharCodeField.normalizeInput', () {
    test('uppercases and strips separators from a typed/pasted code', () {
      expect(SixCharCodeField.normalizeInput('abc234'), 'ABC234');
      expect(SixCharCodeField.normalizeInput(' ab-c 23.4 '), 'ABC234');
      expect(SixCharCodeField.normalizeInput('abc234xyz'), 'ABC234');
    });

    test('extracts the code from a full invite URL', () {
      expect(
        SixCharCodeField.normalizeInput(
            'https://taskmaster-app-3d480.web.app/join/?code=ABC234'),
        'ABC234',
      );
    });

    test('extracts the code from a taskcaster:// deep link', () {
      expect(
        SixCharCodeField.normalizeInput('taskcaster://join?code=qrs234'),
        'QRS234',
      );
    });

    test('extracts the code from a foreign URL with a code query param', () {
      expect(
        SixCharCodeField.normalizeInput('https://example.com/x?code=WXY234'),
        'WXY234',
      );
    });

    test('extracts the code from an install-referrer style fragment', () {
      expect(
        SixCharCodeField.normalizeInput('invite_code=ABC234&utm_source=share'),
        'ABC234',
      );
    });

    test('a URL without a code does not leak URL characters into the cells',
        () {
      expect(SixCharCodeField.normalizeInput('https://example.com/nothing'),
          '');
    });
  });

  group('SixCharCodeField widget', () {
    testWidgets('typing fills the cells uppercased and reports changes',
        (tester) async {
      final changes = <String>[];
      await pumpField(tester, onChanged: changes.add);

      await tester.enterText(find.byType(TextField), 'ab3');
      await tester.pump();

      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(changes.last, 'AB3');
    });

    testWidgets('auto-submits exactly once when the 6th character lands',
        (tester) async {
      final completions = <String>[];
      await pumpField(tester, onCompleted: completions.add);

      await tester.enterText(find.byType(TextField), 'abc23');
      await tester.pump();
      expect(completions, isEmpty);

      await tester.enterText(find.byType(TextField), 'abc234');
      await tester.pump();
      expect(completions, ['ABC234']);
    });

    testWidgets('pasting a bare code fills all six cells and auto-submits',
        (tester) async {
      final completions = <String>[];
      final controller = TextEditingController();
      await pumpField(tester,
          controller: controller, onCompleted: completions.add);

      // enterText replaces the whole value, which is what a paste does.
      await tester.enterText(find.byType(TextField), 'qrs234');
      await tester.pump();

      expect(controller.text, 'QRS234');
      expect(completions, ['QRS234']);
    });

    testWidgets('pasting a full invite URL fills the code and auto-submits',
        (tester) async {
      final completions = <String>[];
      final controller = TextEditingController();
      await pumpField(tester,
          controller: controller, onCompleted: completions.add);

      await tester.enterText(
        find.byType(TextField),
        'https://taskmaster-app-3d480.web.app/join/?code=ABC234',
      );
      await tester.pump();

      expect(controller.text, 'ABC234');
      expect(completions, ['ABC234']);
      expect(find.text('A'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
    });

    testWidgets('backspace empties the last cell and can re-complete',
        (tester) async {
      final completions = <String>[];
      final controller = TextEditingController();
      await pumpField(tester,
          controller: controller, onCompleted: completions.add);

      await tester.enterText(find.byType(TextField), 'ABC234');
      await tester.pump();
      expect(completions, ['ABC234']);

      // Backspace removes the 6th char (the field keeps focus from enterText).
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(controller.text, 'ABC23');
      expect(find.text('4'), findsNothing);

      // Re-typing the last char completes again (a fresh, distinct entry).
      await tester.enterText(find.byType(TextField), 'ABC235');
      await tester.pump();
      expect(completions, ['ABC234', 'ABC235']);
    });

    testWidgets('input is capped at six characters', (tester) async {
      final controller = TextEditingController();
      await pumpField(tester, controller: controller);

      await tester.enterText(find.byType(TextField), 'abcdefgh');
      await tester.pump();

      expect(controller.text, 'ABCDEF');
    });
  });
}
