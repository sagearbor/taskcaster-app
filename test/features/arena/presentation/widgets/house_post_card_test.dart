import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/models/submission.dart';
import 'package:taskcaster_app/core/theme/app_theme.dart';
import 'package:taskcaster_app/features/arena/data/repositories/feed_repository_impl.dart';
import 'package:taskcaster_app/features/arena/domain/models/feed_post.dart';
import 'package:taskcaster_app/features/arena/presentation/widgets/post_card.dart';

/// Every seeded house entry (WP-7: four per starter task) must fit its card
/// at the smallest phone we support, with the real fonts, in both themes:
/// the text sits on the 4:5 gradient between the HOUSE badge and the stamp.
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
  setUpAll(_loadFonts);

  final textPosts = [
    for (final row in FeedRepositoryImpl.houseEntryPosts())
      FeedPost.fromMap(row),
  ].where((p) => p.mediaType == SubmissionMediaType.text).toList();

  Future<void> pumpCard(WidgetTester tester, FeedPost post, ThemeData theme,
      Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: PostCard(post: post),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  test('there are persona text entries to check', () {
    expect(textPosts.length, greaterThanOrEqualTo(30));
  });

  for (final size in const [Size(360, 640), Size(390, 844)]) {
    for (final (name, theme) in [
      ('light', AppTheme.lightTheme),
      ('dark', AppTheme.darkTheme),
    ]) {
      testWidgets(
          'every house text entry fits its card at '
          '${size.width.toInt()}x${size.height.toInt()} ($name)',
          (tester) async {
        for (final post in textPosts) {
          await pumpCard(tester, post, theme, size);
          expect(tester.takeException(), isNull, reason: post.id);

          final paragraph = tester.renderObject<RenderParagraph>(
              find.text(post.text!));
          final box = tester.getSize(find.byType(AspectRatio));
          // The gradient has 24 px padding; keep clear of the badge/stamp
          // row (about 44 px) at the top, and mirror it at the bottom since
          // the text is centred.
          final room = box.height - 2 * 24 - 2 * 44;
          final needed =
              paragraph.getMaxIntrinsicHeight(paragraph.size.width);
          expect(needed, lessThanOrEqualTo(room),
              reason: '${post.id} needs ${needed.toStringAsFixed(0)} px, '
                  'has ${room.toStringAsFixed(0)} px: "${post.text}"');
        }
      });
    }
  }
}
