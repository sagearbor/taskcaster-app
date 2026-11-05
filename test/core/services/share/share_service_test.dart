import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/models/submission.dart';
import 'package:taskcaster_app/core/services/invite/invite_link_parser.dart';
import 'package:taskcaster_app/core/services/share/share_links.dart';
import 'package:taskcaster_app/core/services/share/share_service.dart';
import 'package:taskcaster_app/features/arena/domain/models/feed_post.dart';

FeedPost post({
  String id = 'post1',
  String taskId = 'starter-09-v2',
  bool? shareable,
  bool isHouse = false,
}) =>
    FeedPost(
      id: id,
      gameId: 'g1',
      taskId: taskId,
      taskTitle: 'The face of someone who has just remembered the oven is on',
      userId: 'me',
      displayName: 'Sage Arbor',
      mediaType: SubmissionMediaType.video,
      createdAt: DateTime.utc(2026, 11, 5),
      elapsedSeconds: 8,
      stamp: 'NO REGRETS',
      shareable: shareable,
      isHouse: isHouse,
    );

class _Recorder {
  final List<String> shared = [];
  final List<String> copied = [];
  Object? sheetError;

  Future<void> sheet(String text, {String? subject}) async {
    if (sheetError != null) throw sheetError!;
    shared.add(text);
  }

  Future<void> copy(String text) async => copied.add(text);
}

class _ThrowingStore implements ShareStore {
  @override
  Future<void> recordAttribution({
    required String uid,
    required String fromPostId,
    required String postId,
    required String taskId,
  }) async =>
      throw Exception('permission-denied');

  @override
  Future<void> setShareable(String postId, bool shareable) async =>
      throw Exception('offline');
}

ShareService serviceWith(_Recorder r,
        {ShareStore? store, bool hasShareSheet = true}) =>
    ShareService(
      store: store ?? InMemoryShareStore(),
      sheet: r.sheet,
      copyToClipboard: r.copy,
      hasShareSheet: hasShareSheet,
    );

void main() {
  group('ShareLinks', () {
    test('builds the four public URLs on the hosting domain', () {
      expect(ShareLinks.challengeUrl('abc'),
          'https://taskmaster-app-3d480.web.app/c/abc');
      expect(ShareLinks.postUrl('abc'),
          'https://taskmaster-app-3d480.web.app/p/abc');
      expect(ShareLinks.taskUrl('starter-03', fromPostId: 'abc'),
          'https://taskmaster-app-3d480.web.app/t/starter-03?from=abc');
      expect(ShareLinks.finaleUrl('starter_starter-03'),
          'https://taskmaster-app-3d480.web.app/f/starter_starter-03');
    });

    test('the links it builds route back to the right deep link', () {
      expect(InviteLinks.parse(Uri.parse(ShareLinks.challengeUrl('abc'))),
          const ChallengeLink('abc'));
      expect(
        InviteLinks.parse(
            Uri.parse(ShareLinks.taskUrl('starter-03', fromPostId: 'abc'))),
        const TaskLink('starter-03', fromPostId: 'abc'),
      );
    });

    test('captions are deterministic per seed and carry the stamp', () {
      final a = ShareCaptions.forAttempt(
          seed: 'x1', taskTitle: 'Task', elapsedSeconds: 8, stamp: 'ART');
      final b = ShareCaptions.forAttempt(
          seed: 'x1', taskTitle: 'Task', elapsedSeconds: 8, stamp: 'ART');
      expect(a, b);
      expect(a, startsWith('ART. '));
      expect(a, isNot(contains('{')));
      expect(ShareCaptions.forFinale(seed: 'm', taskTitle: 'Egg'),
          contains('Egg'));
    });
  });

  group('ShareService.shareAttempt', () {
    test('a starter post is already public: no write; sheet gets caption + /c/',
        () async {
      final store = InMemoryShareStore();
      final r = _Recorder();
      final outcome = await serviceWith(r, store: store).shareAttempt(post());

      expect(outcome, ShareOutcome.sheet);
      expect(store.shareable, isEmpty);
      expect(r.shared.single,
          endsWith('\nhttps://taskmaster-app-3d480.web.app/c/post1'));
      expect(r.shared.single, contains('NO REGRETS'));
    });

    test('sharing your own friend-game post is consent: shareable flips on',
        () async {
      final store = InMemoryShareStore();
      final r = _Recorder();
      await serviceWith(r, store: store)
          .shareAttempt(post(id: 'fg', taskId: 'friend-task'));

      expect(store.shareable, {'fg': true});
      expect(r.shared, hasLength(1));
    });

    test('an explicit opt-out is overridden only by sharing again', () async {
      final store = InMemoryShareStore();
      expect(ShareService.isPublic(post(shareable: false)), isFalse);
      await serviceWith(_Recorder(), store: store)
          .shareAttempt(post(shareable: false));
      expect(store.shareable, {'post1': true});
    });

    test('no share sheet (desktop web): the message is copied instead',
        () async {
      final r = _Recorder();
      expect(await serviceWith(r, hasShareSheet: false).shareAttempt(post()),
          ShareOutcome.copied);
      expect(r.shared, isEmpty);
      expect(r.copied.single, contains('/c/post1'));
    });

    test('a failing sheet falls back to copying', () async {
      final r = _Recorder()..sheetError = Exception('no navigator.share');
      expect(await serviceWith(r).shareAttempt(post()), ShareOutcome.copied);
    });

    test('a failed shareable write reports failure (the link would 404)',
        () async {
      final r = _Recorder();
      expect(
        await serviceWith(r, store: _ThrowingStore())
            .shareAttempt(post(taskId: 'friend-task')),
        ShareOutcome.failed,
      );
    });
  });

  group('ShareService.isPublic mirrors the server rule', () {
    test('starter + house default public, friend games default private', () {
      expect(ShareService.isPublic(post()), isTrue);
      expect(ShareService.isPublic(post(taskId: 'friend-task')), isFalse);
      expect(
          ShareService.isPublic(post(taskId: 'friend-task', isHouse: true)),
          isTrue);
      expect(
          ShareService.isPublic(post(taskId: 'friend-task', shareable: true)),
          isTrue);
    });
  });

  group('ShareService.shareFinale + attribution', () {
    test('finale shares the /f/ link', () async {
      final r = _Recorder();
      await serviceWith(r).shareFinale(
          montageId: 'starter_starter-01-v2', taskTitle: 'Egg on a spoon');
      expect(
          r.shared.single,
          endsWith(
              'https://taskmaster-app-3d480.web.app/f/starter_starter-01-v2'));
    });

    test('attribution keeps the first challenge and never throws', () async {
      final store = InMemoryShareStore();
      final service = ShareService(store: store, hasShareSheet: false);
      await service.recordChallengeAttribution(
          uid: 'new', fromPostId: 'theirs', postId: 'mine', taskId: 't');
      await service.recordChallengeAttribution(
          uid: 'new', fromPostId: 'other', postId: 'mine2', taskId: 't');
      expect(store.attributions['new']!['fromPostId'], 'theirs');

      final failing =
          ShareService(store: _ThrowingStore(), hasShareSheet: false);
      await failing.recordChallengeAttribution(
          uid: 'new', fromPostId: 'theirs', postId: 'mine', taskId: 't');
    });
  });

  group('FeedPost.shareable', () {
    test('round-trips; absent stays absent; junk reads as null', () {
      final withFlag = post(shareable: true);
      expect(withFlag.toMap()['shareable'], isTrue);
      expect(FeedPost.fromMap(withFlag.toMap()).shareable, isTrue);
      expect(post().toMap().containsKey('shareable'), isFalse);
      expect(
          FeedPost.fromMap({...post().toMap(), 'shareable': 'yes'}).shareable,
          isNull);
    });
  });
}
