import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/di/service_locator.dart';
import 'package:taskcaster_app/core/services/sfx/game_sfx.dart';
import 'package:taskcaster_app/core/theme/app_theme.dart';
import 'package:taskcaster_app/features/party/domain/party_tasks.dart';
import 'package:taskcaster_app/features/party/presentation/screens/party_play_screen.dart';
import 'package:taskcaster_app/features/party/presentation/screens/party_setup_screen.dart';
import 'package:taskcaster_app/features/party/presentation/widgets/party_stage.dart';

import '../../helpers/recording_game_sfx.dart';

void _phone(WidgetTester tester, Size size) {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

Widget _app(Widget home, {Brightness b = Brightness.light}) => MaterialApp(
      theme: b == Brightness.light ? AppTheme.lightTheme : AppTheme.darkTheme,
      home: home,
    );

/// Label of the primary (first) stage button on screen.
String _primary(WidgetTester tester) =>
    tester.widgetList<PartyButton>(find.byType(PartyButton)).first.label;

Finder _missionTexts() => find.byWidgetPredicate(
    (w) => w is Text && kSecretMissions.contains(w.data));

/// Plays the whole party through with whatever buttons appear, ranking
/// players in seat order each time. Returns the labels it pressed.
Future<List<String>> _playThrough(WidgetTester tester, List<String> players,
    {bool missionsDone = true}) async {
  final pressed = <String>[];
  for (var guard = 0; guard < 300; guard++) {
    if (find.text('Play again').evaluate().isNotEmpty) return pressed;
    if (find.text('Rank them').evaluate().isNotEmpty) {
      for (final p in players.take(players.length - 1)) {
        await tester.ensureVisible(find.text(p));
        await tester.pump();
        await tester.tap(find.text(p));
        await tester.pump();
      }
      await tester.tap(find.text('Lock it in'));
      await tester.pump();
      pressed.add('Lock it in');
      continue;
    }
    if (find.text('Who won?').evaluate().isNotEmpty) {
      await tester.tap(find.text(players.first));
      await tester.pump();
      pressed.add('winner');
      continue;
    }
    if (find.text('Did they pull it off?').evaluate().isNotEmpty) {
      final label = missionsDone ? 'They did. +$kSecretMissionBonus' : 'Not a chance';
      await tester.tap(find.text(label));
      await tester.pump();
      pressed.add(label);
      continue;
    }
    final label = _primary(tester);
    pressed.add(label);
    if (label == 'Done early') {
      await tester.tap(find.text(label));
    } else {
      await tester.tap(find.byType(PartyButton).first);
    }
    await tester.pump();
  }
  fail('party never finished: ${pressed.join(' > ')}');
}

void main() {
  late RecordingGameSfx sfx;

  setUp(() async {
    await sl.reset();
    sfx = RecordingGameSfx();
    sl.registerSingleton<GameSfx>(sfx);
  });
  tearDown(() => sl.reset());

  group('secret missions privacy', () {
    testWidgets('a mission is only on screen after its owner asks for it',
        (tester) async {
      _phone(tester, const Size(360, 640));
      await tester.pumpWidget(_app(PartyPlayScreen(
        players: const ['Ana', 'Ben', 'Cy'],
        taskCount: 3,
        random: Random(7),
      )));

      for (final name in ['Ana', 'Ben', 'Cy']) {
        // The pass screen names the player and shows no mission.
        expect(find.text(name), findsOneWidget);
        expect(find.textContaining('look away'), findsOneWidget);
        expect(_missionTexts(), findsNothing);

        await tester.tap(find.text("I'm $name. Show me"));
        await tester.pump();
        expect(_missionTexts(), findsOneWidget);
        expect(find.text('FOR ${name.toUpperCase()} ONLY'), findsOneWidget);

        await tester.tap(find.byType(PartyButton));
        await tester.pump();
        expect(_missionTexts(), findsNothing);
      }
      expect(find.text('Everyone has a secret.'), findsOneWidget);
    });

    testWidgets('three players see three different missions', (tester) async {
      _phone(tester, const Size(360, 640));
      await tester.pumpWidget(_app(PartyPlayScreen(
        players: const ['Ana', 'Ben', 'Cy'],
        taskCount: 3,
        random: Random(11),
      )));
      final seen = <String>{};
      for (final name in ['Ana', 'Ben', 'Cy']) {
        await tester.tap(find.text("I'm $name. Show me"));
        await tester.pump();
        seen.add((tester.widget<Text>(_missionTexts())).data!);
        await tester.tap(find.byType(PartyButton));
        await tester.pump();
      }
      expect(seen.length, 3);
    });

    testWidgets('missions off skips straight to the first task',
        (tester) async {
      _phone(tester, const Size(360, 640));
      await tester.pumpWidget(_app(PartyPlayScreen(
        players: const ['Ana', 'Ben'],
        taskCount: 3,
        withMissions: false,
        random: Random(1),
      )));
      expect(find.text('TASK 1 OF 3'), findsOneWidget);
      expect(find.text('HEAD TO HEAD'), findsOneWidget);
    });
  });

  group('clock', () {
    testWidgets('runs down with GO, ticks the last 5 s, then TIME',
        (tester) async {
      _phone(tester, const Size(360, 640));
      await tester.pumpWidget(_app(PartyPlayScreen(
        players: const ['Ana', 'Ben'],
        taskCount: 3,
        withMissions: false,
        random: Random(1),
      )));
      await tester.tap(find.text('Start the clock'));
      await tester.pump();
      expect(sfx.played, containsAllInOrder(['prime', 'go']));
      expect(find.text('Done early'), findsOneWidget);

      // First task is head to head, at most two minutes.
      for (var i = 0; i < 200 && find.text('TIME').evaluate().isEmpty; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.text('TIME'), findsOneWidget);
      expect(sfx.played.where((s) => s == 'tick').length, 5);
      expect(sfx.played.last, 'fanfare');
      expect(find.text('Judge it'), findsOneWidget);
    });

    testWidgets('performance tasks give every player their own turn',
        (tester) async {
      _phone(tester, const Size(360, 640));
      await tester.pumpWidget(_app(PartyPlayScreen(
        players: const ['Ana', 'Ben', 'Cy'],
        taskCount: 3,
        withMissions: false,
        random: Random(1),
      )));
      // Advance until a performance task comes up.
      final turns = <String>[];
      for (var guard = 0; guard < 120; guard++) {
        if (find.text('PERFORMANCE').evaluate().isNotEmpty) break;
        if (find.text('Rank them').evaluate().isNotEmpty) {
          await tester.tap(find.text('Ana'));
          await tester.pump();
          await tester.tap(find.text('Ben'));
          await tester.pump();
        }
        await tester.tap(find.byType(PartyButton).first);
        await tester.pump();
      }
      expect(find.text('PERFORMANCE'), findsOneWidget);
      await tester.tap(find.text('First up: Ana'));
      await tester.pump();
      for (final name in ['Ana', 'Ben', 'Cy']) {
        expect(find.text("$name, you're up"), findsOneWidget);
        turns.add(name);
        await tester.tap(find.text('Start'));
        await tester.pump();
        await tester.tap(find.text('Done early'));
        await tester.pump();
        expect(find.text('TIME'), findsOneWidget);
        await tester.tap(find.byType(PartyButton).first);
        await tester.pump();
      }
      expect(turns, ['Ana', 'Ben', 'Cy']);
      expect(find.text('Rank them'), findsOneWidget);
    });
  });

  group('judging and scoring', () {
    testWidgets('two players: tap the winner, scoreboard updates',
        (tester) async {
      _phone(tester, const Size(360, 640));
      await tester.pumpWidget(_app(PartyPlayScreen(
        players: const ['Ana', 'Ben'],
        taskCount: 3,
        withMissions: false,
        random: Random(1),
      )));
      await tester.tap(find.text('Start the clock'));
      await tester.pump();
      await tester.tap(find.text('Done early'));
      await tester.pump();
      await tester.tap(find.text('Judge it'));
      await tester.pump();
      expect(find.text('Who won?'), findsOneWidget);
      await tester.tap(find.text('Ben'));
      await tester.pump();
      expect(find.text('Ben takes it.'), findsOneWidget);
      expect(
          tester.widget<Text>(find.byKey(const ValueKey('party-score-1'))).data,
          '2');
      expect(
          tester.widget<Text>(find.byKey(const ValueKey('party-score-0'))).data,
          '1');
      expect(find.text('Next task'), findsOneWidget);
    });

    testWidgets('3+ players: rank in order, last place fills itself, undo',
        (tester) async {
      _phone(tester, const Size(360, 640));
      await tester.pumpWidget(_app(PartyPlayScreen(
        players: const ['Ana', 'Ben', 'Cy', 'Dee'],
        taskCount: 3,
        withMissions: false,
        random: Random(1),
      )));
      await tester.tap(find.text('Start the clock'));
      await tester.pump();
      await tester.tap(find.text('Done early'));
      await tester.pump();
      await tester.tap(find.text('Judge it'));
      await tester.pump();

      PartyButton lock() => tester.widget<PartyButton>(
          find.widgetWithText(PartyButton, 'Lock it in'));
      expect(lock().onPressed, isNull);
      await tester.tap(find.text('Cy'));
      await tester.pump();
      expect(find.text('1st'), findsOneWidget);
      await tester.tap(find.text('Start over'));
      await tester.pump();
      expect(find.text('1st'), findsNothing);

      for (final n in ['Dee', 'Ana', 'Cy']) {
        await tester.tap(find.text(n));
        await tester.pump();
      }
      expect(find.text('4th'), findsOneWidget); // Ben, automatically
      expect(lock().onPressed, isNotNull);
      await tester.tap(find.text('Lock it in'));
      await tester.pump();
      expect(find.text('Dee takes it.'), findsOneWidget);
      String score(int i) => tester
          .widget<Text>(find.byKey(ValueKey('party-score-$i')))
          .data!;
      expect([score(3), score(0), score(2), score(1)], ['4', '3', '2', '1']);
    });
  });

  group('full party', () {
    testWidgets(
        '3 players, missions on: every task, mission reveal, champion '
        'at 360x640 with no overflow', (tester) async {
      _phone(tester, const Size(360, 640));
      await tester.pumpWidget(_app(PartyPlayScreen(
        players: const ['Ana', 'Ben', 'Cy'],
        taskCount: 5,
        random: Random(4),
      )));
      final pressed = await _playThrough(tester, const ['Ana', 'Ben', 'Cy'],
          missionsDone: true);
      expect(pressed.where((p) => p == 'Lock it in').length, 5);
      expect(pressed.where((p) => p.startsWith('They did')).length, 3);
      expect(pressed, contains('Reveal the secret missions'));
      // Ana won every task (5 × 3) + mission bonus.
      expect(find.text('CHAMPION'), findsOneWidget);
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('party-champion-name')))
              .data,
          'Ana');
      expect(find.text('${15 + kSecretMissionBonus} points. '
          'Nobody is surprised. Some are upset.'), findsOneWidget);
      expect(sfx.played.last, 'fanfare');
      // Let the confetti finish.
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('2 players, no missions, dark theme: straight to champion; '
        'play again restarts', (tester) async {
      _phone(tester, const Size(360, 640));
      await tester.pumpWidget(_app(
          PartyPlayScreen(
            players: const ['Ana', 'Ben'],
            taskCount: 3,
            withMissions: false,
            random: Random(9),
          ),
          b: Brightness.dark));
      final pressed = await _playThrough(tester, const ['Ana', 'Ben']);
      expect(pressed, contains('Crown the champion'));
      expect(pressed, isNot(contains('Reveal the secret missions')));
      await tester.tap(find.text('Play again'));
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('TASK 1 OF 3'), findsOneWidget);
    });

    testWidgets('8 players with long names fit at 360x640', (tester) async {
      _phone(tester, const Size(360, 640));
      final players = List.generate(8, (i) => 'Bartholomew ${i + 1}');
      await tester.pumpWidget(_app(PartyPlayScreen(
        players: players,
        taskCount: 3,
        random: Random(5),
      )));
      await _playThrough(tester, players);
      expect(find.text('Play again'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('setup', () {
    for (final size in const [Size(360, 640), Size(390, 844)]) {
      testWidgets('add names, pick a pack, start (${size.width.toInt()}w)',
          (tester) async {
        _phone(tester, size);
        await tester.pumpWidget(_app(const PartySetupScreen()));

        PartyButton start() =>
            tester.widget<PartyButton>(find.byType(PartyButton));
        expect(start().label, 'Add 2 more players');
        expect(start().onPressed, isNull);

        await tester.enterText(
            find.byKey(const ValueKey('party-name-field')), 'Sam');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        await tester.enterText(
            find.byKey(const ValueKey('party-name-field')), 'sam');
        await tester.tap(find.byTooltip('Add player'));
        await tester.pump();
        expect(find.byKey(const ValueKey('player-chip-Sam')), findsOneWidget);
        expect(
            find.byKey(const ValueKey('player-chip-sam 2')), findsOneWidget);

        await tester.ensureVisible(find.text('+ Mum'));
        await tester.pump();
        await tester.tap(find.text('+ Mum'));
        await tester.pump();
        expect(find.text('+ Mum'), findsNothing);
        expect(start().label, 'Start the party');

        await tester.ensureVisible(find.byKey(const ValueKey('pack-3')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('pack-3')));
        await tester.pump();
        await tester.tap(find.byType(PartyButton));
        await tester.pumpAndSettle();
        expect(find.byType(PartyPlayScreen), findsOneWidget);
        expect(find.text('Sam'), findsOneWidget); // first to receive a mission
      });
    }

    testWidgets('caps at 8 players and hides the name field', (tester) async {
      _phone(tester, const Size(360, 640));
      await tester.pumpWidget(_app(const PartySetupScreen()));
      for (var i = 0; i < 8; i++) {
        await tester.ensureVisible(find.textContaining('+ Player'));
        await tester.pump();
        await tester.tap(find.textContaining('+ Player'));
        await tester.pump();
      }
      expect(find.byType(InputChip), findsNWidgets(8));
      expect(find.byKey(const ValueKey('party-name-field')), findsNothing);
      expect(find.text('WHO IS PLAYING  8/8'), findsOneWidget);
    });

    testWidgets('dark theme setup with 6 players: no overflow',
        (tester) async {
      _phone(tester, const Size(360, 640));
      await tester.pumpWidget(
          _app(const PartySetupScreen(), b: Brightness.dark));
      for (var i = 0; i < 6; i++) {
        await tester.ensureVisible(find.textContaining('+ ').first);
        await tester.pump();
        await tester.tap(find.textContaining('+ ').first);
        await tester.pump();
      }
      await tester.ensureVisible(
          find.byKey(const ValueKey('party-missions-switch')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('party-missions-switch')));
      await tester.pump();
      expect(find.byType(InputChip), findsNWidgets(6));
    });
  });
}
