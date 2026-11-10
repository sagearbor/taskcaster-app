// Goldens for the Starter Pack recap ("Your First Ten", fun audit WP-2):
// seven of ten posted, three scored by the crowd, light and dark at a
// 390x844 phone viewport, with real fonts and real photo thumbnails.
//
// Regenerate after an intentional visual change:
//   flutter test --update-goldens test/features/games/presentation/goldens/starter_recap_golden_test.dart
//
// Rendered on macOS (where the owner runs the suite); skipped elsewhere, as
// in game_screen_golden_test.dart.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taskcaster_app/core/theme/app_theme.dart';
import 'package:taskcaster_app/features/games/presentation/widgets/starter_recap_view.dart';

import '../widgets/starter_recap_fixture.dart';

Future<void> _loadFonts() async {
  Future<void> load(String family, Future<ByteData> data) async {
    final loader = FontLoader(family)..addFont(data);
    await loader.load();
  }

  await load('Fredoka', rootBundle.load('assets/fonts/Fredoka.ttf'));
  await load(
      'PlusJakartaSans', rootBundle.load('assets/fonts/PlusJakartaSans.ttf'));
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    final icons = File(
        '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      await load('MaterialIcons',
          Future.value(ByteData.view(icons.readAsBytesSync().buffer)));
    }
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
  });

  // The celebration has already played, so the golden shows the steady state.
  setUp(() => SharedPreferences.setMockInitialValues({
        StarterRecapView.celebratedKey('starter-1'): true,
      }));

  for (final b in Brightness.values) {
    testWidgets('starter recap (${b.name})', (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final f = recapFixture();
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: b == Brightness.light ? AppTheme.lightTheme : AppTheme.darkTheme,
        home: Scaffold(
          appBar: AppBar(title: const Text('Your First Ten')),
          body: StarterRecapView(
            game: f.game,
            currentUserId: recapMe,
            posts: Stream.value(f.posts),
            onPlayTask: (_) {},
            onOpenArena: () {},
            onChallengeFriends: () {},
          ),
        ),
      ));
      await tester.pump();
      // Decode the photo thumbnails for real (outside the fake clock).
      await tester.runAsync(() async {
        for (final p in f.posts.where((p) => p.photoData != null)) {
          await precacheImage(
              MemoryImage(base64Decode(p.photoData!)),
              tester.element(find.byType(StarterRecapView)));
        }
      });
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('starter_recap_${b.name}.png'),
      );
    }, skip: !Platform.isMacOS);
  }
}
