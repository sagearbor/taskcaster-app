import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taskcaster_app/core/models/submission.dart';
import 'package:taskcaster_app/core/services/moderation/moderation_service.dart';
import 'package:taskcaster_app/features/arena/domain/models/feed_post.dart';

/// The account write is refused (offline web, a rules hiccup).
class _FailingStore extends InMemoryModerationStore {
  @override
  Future<void> addBlocked(String uid, String key) async {
    throw StateError('permission-denied');
  }
}

FeedPost _post(
  String id, {
  String userId = 'troll',
  String displayName = 'Troll',
  bool isHouse = false,
  bool hidden = false,
}) =>
    FeedPost(
      id: id,
      gameId: '',
      taskId: 'starter-01',
      taskTitle: 'Task',
      userId: userId,
      displayName: displayName,
      mediaType: SubmissionMediaType.text,
      text: 'hi',
      isHouse: isHouse,
      hidden: hidden,
      createdAt: DateTime.utc(2026, 11, 1),
    );

void main() {
  late InMemoryModerationStore store;
  late InMemoryModerationCache cache;
  late ModerationService service;

  setUp(() {
    store = InMemoryModerationStore();
    cache = InMemoryModerationCache();
    service = ModerationService(store: store, cache: cache);
  });

  tearDown(() => service.dispose());

  test('reportPost hides the post at once and writes the report', () async {
    await service.load('me');
    final changes = <void>[];
    final sub = service.changes.listen(changes.add);

    await service.reportPost(
      post: _post('p1'),
      reason: ReportReason.harassment,
      reporterId: 'me',
    );
    await Future<void>.delayed(Duration.zero);

    expect(service.hides(_post('p1')), isTrue);
    expect(service.hides(_post('p2')), isFalse);
    expect(changes, isNotEmpty);
    expect(store.reports, [
      {
        'id': 'p1_me',
        'postId': 'p1',
        'authorId': 'troll',
        'reporterId': 'me',
        'reason': 'harassment',
      },
    ]);
    // ...and the hide is cached for this account on this device.
    expect((await cache.read('me')).hiddenPosts, {'p1'});
    await sub.cancel();
  });

  test('a report write failure still leaves the post hidden', () async {
    await service.load('me');
    await service.reportPost(
        post: _post('p1'), reason: ReportReason.spam, reporterId: 'me');
    // Second report of the same post: refused (as the rules would).
    await expectLater(
      service.reportPost(
          post: _post('p1'), reason: ReportReason.spam, reporterId: 'me'),
      throwsStateError,
    );
    expect(service.hides(_post('p1')), isTrue);
  });

  test('blockAuthorOf hides every post by that author and saves to the account',
      () async {
    await service.load('me');
    await service.blockAuthorOf(_post('p1'), uid: 'me');
    await Future<void>.delayed(Duration.zero);

    expect(service.hides(_post('p2')), isTrue);
    expect(service.hides(_post('p3', userId: 'friend')), isFalse);
    expect(store.blocked['me'], ['troll']);
    expect((await cache.read('me')).blocked, {'troll'});
  });

  test('blocking one house persona leaves the other personas visible',
      () async {
    await service.load('me');
    final greg =
        _post('h1', userId: 'house', displayName: 'Greg', isHouse: true);
    final alex =
        _post('h2', userId: 'house', displayName: 'Alex', isHouse: true);
    await service.blockAuthorOf(greg, uid: 'me');

    expect(store.blocked['me'], ['house:Greg']);
    expect(service.hides(greg), isTrue);
    expect(service.hides(alex), isFalse);
  });

  test('server-hidden posts are hidden for everyone', () {
    expect(service.hides(_post('p1', hidden: true)), isTrue);
  });

  test('load filters from the device cache before the account list arrives',
      () async {
    await cache.write('me',
        const ModerationSnapshot(blocked: {'troll'}, hiddenPosts: {'p9'}));
    await service.load('me');
    expect(service.hides(_post('p1')), isTrue);
    expect(service.hides(_post('p9', userId: 'x')), isTrue);
  });

  test('the account list follows the user to a new device', () async {
    store.blocked['me'] = ['troll'];
    await service.load('me'); // empty cache: a fresh install
    await Future<void>.delayed(Duration.zero);
    expect(service.hides(_post('p1')), isTrue);
    expect((await cache.read('me')).blocked, {'troll'});
  });

  test('an unblock on another device wins over the stale cache', () async {
    await cache.write('me', const ModerationSnapshot(blocked: {'troll'}));
    store.blocked['me'] = [];
    await service.load('me');
    await Future<void>.delayed(Duration.zero);
    expect(service.hides(_post('p1')), isFalse);
  });

  test('a block whose account write failed still holds on this device',
      () async {
    final failing = _FailingStore();
    final local = ModerationService(store: failing, cache: cache);
    await local.load('me');
    await expectLater(
        local.blockAuthorOf(_post('p1'), uid: 'me'), throwsStateError);
    // A later snapshot of the (unchanged) account list must not undo it.
    await failing.removeBlocked('me', 'nothing');
    await Future<void>.delayed(Duration.zero);
    expect(local.hides(_post('p1')), isTrue);
    await local.dispose();
  });

  test('unblock removes the key locally and on the account', () async {
    await service.load('me');
    await service.blockAuthorOf(_post('p1'), uid: 'me');
    await service.unblock('troll', uid: 'me');
    await Future<void>.delayed(Duration.zero);
    expect(service.hides(_post('p1')), isFalse);
    expect(store.blocked['me'], isEmpty);
  });

  test('blockedPlayers names everyone: cache, house persona, then users doc',
      () async {
    store.blocked['me'] = ['zed-uid', 'house:Greg', 'troll'];
    store.names['zed-uid'] = 'Zed';
    await cache.write(
        'me', const ModerationSnapshot(names: {'troll': 'Troll'}));
    await service.load('me');
    await Future<void>.delayed(Duration.zero);

    expect(await service.blockedPlayers(), const [
      BlockedPlayer(key: 'house:Greg', displayName: 'Greg'),
      BlockedPlayer(key: 'troll', displayName: 'Troll'),
      BlockedPlayer(key: 'zed-uid', displayName: 'Zed'),
    ]);
  });

  test('switching accounts does not leak one account\'s blocks into another',
      () async {
    await service.load('me');
    await service.blockAuthorOf(_post('p1'), uid: 'me');
    await service.load('someone-else');
    await Future<void>.delayed(Duration.zero);
    expect(service.hides(_post('p1')), isFalse);
  });

  test('the report reasons are exactly the four the rules accept', () {
    expect(ReportReason.values.map((r) => r.value),
        ['inappropriate', 'spam', 'harassment', 'other']);
    expect(ModerationService.reportDocId('p1', 'u1'), 'p1_u1');
  });

  group('SharedPrefsModerationCache', () {
    test('round-trips per account', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = SharedPrefsModerationCache();
      await prefs.write(
        'me',
        const ModerationSnapshot(
          blocked: {'troll'},
          hiddenPosts: {'p1'},
          names: {'troll': 'Troll'},
        ),
      );
      final back = await prefs.read('me');
      expect(back.blocked, {'troll'});
      expect(back.hiddenPosts, {'p1'});
      expect(back.names, {'troll': 'Troll'});
      expect((await prefs.read('other')).blocked, isEmpty);
    });
  });
}
