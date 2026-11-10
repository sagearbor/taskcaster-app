import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/features/arena/data/repositories/feed_repository_impl.dart';

/// House posts are seeded on Firestore by the Admin SDK
/// (functions/scripts/seed_house_posts.js) because the rules deny every client
/// write to them. That script reads functions/scripts/house_posts.json, which
/// must match what the app itself would seed. Regenerate after editing the
/// starter pack with:
///
///   UPDATE_HOUSE_SEED=1 flutter test test/features/arena/data/house_posts_seed_test.dart
void main() {
  const path = 'functions/scripts/house_posts.json';

  /// The seed fields plus the starting grade (gradeCount/gradeSum), which the
  /// script writes only when it CREATES a post; an existing post keeps its
  /// own counters. The script owns every other counter and createdAt.
  List<Map<String, dynamic>> expected() => [
        for (final post in FeedRepositoryImpl.houseEntryPosts())
          Map<String, dynamic>.fromEntries(post.entries.where((e) =>
              !const {
                'graderIds',
                'tapCount',
                'tapSeconds',
                'boosted',
                'createdAt',
              }.contains(e.key))),
      ];

  test('functions/scripts/house_posts.json matches houseEntryPosts()', () {
    final encoded = '${const JsonEncoder.withIndent('  ').convert(expected())}\n';
    final file = File(path);
    if (Platform.environment['UPDATE_HOUSE_SEED'] == '1') {
      file.writeAsStringSync(encoded);
    }
    expect(file.existsSync(), isTrue, reason: '$path is missing');
    expect(
      jsonDecode(file.readAsStringSync()),
      jsonDecode(encoded),
      reason: '$path is stale — rerun with UPDATE_HOUSE_SEED=1',
    );
  });
}
