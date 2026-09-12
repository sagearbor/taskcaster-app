import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/models/submission.dart';
import 'package:taskcaster_app/features/arena/domain/models/feed_post.dart';
import 'package:taskcaster_app/features/arena/presentation/widgets/post_card.dart';
import 'package:taskcaster_app/features/arena/presentation/widgets/post_badge.dart';
import 'package:taskcaster_app/features/arena/presentation/widgets/stamp_sticker.dart';

// A valid 1x1 black PNG, so Image.memory has real bytes to decode.
const _tinyPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';

FeedPost _post({
  String id = 'post-1',
  SubmissionMediaType mediaType = SubmissionMediaType.photo,
  String? photoData,
  String? text,
  String? videoUrl,
  String? stamp = 'NAILED IT',
  bool isLate = false,
  bool isHouse = false,
  int tapCount = 0,
  String? caption = 'Done in 41 s',
}) {
  return FeedPost(
    id: id,
    gameId: 'game-1',
    taskId: 'starter-01',
    taskTitle: 'A vegetable that has just received terrible news',
    rubric: 'Emotional truth of the vegetable',
    userId: 'user-1',
    displayName: 'Sophie',
    mediaType: mediaType,
    photoData: photoData,
    text: text,
    videoUrl: videoUrl,
    caption: caption,
    stamp: stamp,
    isLate: isLate,
    isHouse: isHouse,
    createdAt: DateTime(2026, 1, 1),
    elapsedSeconds: 41,
    gradeCount: 0,
    gradeSum: 0,
    boosted: false,
    tapCount: tapCount,
  );
}

// PostCard is always embedded in a scrollable container in the real app
// (the Arena queue, Watch together) so it never needs to fit an unbounded
// height on its own; give it the same here.
Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))),
  );
}

void main() {
  testWidgets('photo entry renders an Image from base64 photoData',
      (tester) async {
    await _pump(
      tester,
      PostCard(post: _post(photoData: _tinyPngBase64)),
    );
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('text entry renders the text large on the gradient',
      (tester) async {
    await _pump(
      tester,
      PostCard(
        post: _post(
          mediaType: SubmissionMediaType.text,
          text: 'The Fridge-inator 3000',
        ),
      ),
    );

    expect(find.text('The Fridge-inator 3000'), findsOneWidget);
  });

  testWidgets('link entry shows a chip to open the video externally',
      (tester) async {
    await _pump(
      tester,
      PostCard(
        post: _post(
          mediaType: SubmissionMediaType.link,
          videoUrl: 'https://example.com/clip.mp4',
        ),
      ),
    );

    expect(find.text('Watch video'), findsOneWidget);
    expect(find.byType(ActionChip), findsOneWidget);
  });

  testWidgets('LATE badge shows only when isLate', (tester) async {
    await _pump(tester, PostCard(post: _post(isLate: true)));
    expect(find.byType(PostBadge), findsOneWidget);
    expect(find.text('LATE'), findsOneWidget);
  });

  testWidgets('HOUSE badge shows only when isHouse', (tester) async {
    await _pump(tester, PostCard(post: _post(isHouse: true)));
    expect(find.text('HOUSE'), findsOneWidget);
  });

  testWidgets('renders the auto-stamp sticker', (tester) async {
    await _pump(tester, PostCard(post: _post(stamp: 'ART')));
    expect(find.byType(StampSticker), findsOneWidget);
    expect(find.text('ART'), findsOneWidget);
  });

  testWidgets('no stamp sticker when stamp is null', (tester) async {
    await _pump(tester, PostCard(post: _post(stamp: null)));
    expect(find.byType(StampSticker), findsNothing);
  });

  testWidgets('footer shows displayName, task title and caption',
      (tester) async {
    await _pump(tester, PostCard(post: _post()));
    expect(find.text('Sophie'), findsOneWidget);
    expect(
      find.text('A vegetable that has just received terrible news'),
      findsOneWidget,
    );
    expect(find.text('Done in 41 s'), findsOneWidget);
  });

  testWidgets('shows the tap counter only when tapCount > 0', (tester) async {
    await _pump(tester, PostCard(post: _post(tapCount: 0)));
    expect(find.textContaining('\u{1F525}'), findsNothing);

    await _pump(tester, PostCard(post: _post(tapCount: 3)));
    expect(find.text('\u{1F525} 3'), findsOneWidget);
  });

  testWidgets('tapping the media calls onTap and shows a brief burst',
      (tester) async {
    var tapped = false;
    await _pump(
      tester,
      PostCard(post: _post(), onTap: () => tapped = true),
    );

    await tester.tap(find.byType(PostCard));
    await tester.pump();

    expect(tapped, isTrue);
    // The burst emoji is present right after the tap...
    expect(find.text('\u{1F525}'), findsOneWidget);

    // ...and gone once its ~400ms animation finishes.
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('\u{1F525}'), findsNothing);
  });

  testWidgets('tapping never throws when onTap is not supplied',
      (tester) async {
    await _pump(tester, PostCard(post: _post()));

    await tester.tap(find.byType(PostCard));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
  });
}
