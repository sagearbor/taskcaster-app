import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/features/arena/data/repositories/firestore_montage_repository.dart';
import 'package:taskcaster_app/features/arena/data/repositories/mock_montage_repository.dart';
import 'package:taskcaster_app/features/arena/domain/models/montage.dart';

void main() {
  group('Montage', () {
    test('the document id is <scope>_<taskId> (starter tasks share the starter scope)', () {
      expect(Montage.idFor('game-1', 'starter-01'), 'starter_starter-01');
    });

    test('round-trips through the map the server writes', () {
      final montage = Montage(
        gameId: 'game-1',
        taskId: 'starter-01',
        finaleUrl: 'https://cdn.test/finale.mp4',
        momentsUrl: 'https://cdn.test/moments.mp4',
        sourcePostIds: const ['a', 'b'],
        updatedAt: DateTime.utc(2026, 9, 12, 18),
        status: MontageStatus.ready,
      );
      expect(Montage.fromMap(montage.toMap()), montage);
    });

    test('an unknown status parses as unknown, not a crash', () {
      final montage = Montage.fromMap(const {
        'gameId': 'g',
        'taskId': 't',
        'status': 'transcoding-v2',
      });
      expect(montage.status, MontageStatus.unknown);
      expect(montage.isReady, isFalse);
    });

    test('isReady needs both a ready status and a finale url', () {
      const pending = Montage(
        gameId: 'g',
        taskId: 't',
        finaleUrl: 'https://cdn.test/f.mp4',
      );
      expect(pending.isReady, isFalse);

      const noUrl = Montage(
        gameId: 'g',
        taskId: 't',
        status: MontageStatus.ready,
      );
      expect(noUrl.isReady, isFalse);

      const ready = Montage(
        gameId: 'g',
        taskId: 't',
        finaleUrl: 'https://cdn.test/f.mp4',
        status: MontageStatus.ready,
      );
      expect(ready.isReady, isTrue);
    });

    test('a missing status defaults to pending, sourcePostIds to empty', () {
      final montage = Montage.fromMap(const {'gameId': 'g', 'taskId': 't'});
      expect(montage.status, MontageStatus.unknown);
      expect(montage.sourcePostIds, isEmpty);
      expect(montage.updatedAt, isNull);
    });
  });

  group('FirestoreMontageRepository', () {
    late FakeFirebaseFirestore firestore;
    late FirestoreMontageRepository repo;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      repo = FirestoreMontageRepository(firestore: firestore);
    });

    test('is null while the server has rendered nothing', () async {
      expect(await repo.watchMontage('game-1', 'starter-01').first, isNull);
    });

    test('reads the document the server writes', () async {
      await firestore
          .collection(FirestoreMontageRepository.collection)
          .doc('starter_starter-01')
          .set({
        'gameId': 'game-1',
        'taskId': 'starter-01',
        'finaleUrl': 'https://cdn.test/finale.mp4',
        'sourcePostIds': const ['p1', 'p2'],
        'status': 'ready',
        'updatedAt': '2026-09-12T18:00:00.000Z',
      });

      final montage = await repo.watchMontage('game-1', 'starter-01').first;

      expect(montage, isNotNull);
      expect(montage!.isReady, isTrue);
      expect(montage.finaleUrl, 'https://cdn.test/finale.mp4');
      expect(montage.sourcePostIds, ['p1', 'p2']);
      expect(montage.updatedAt, DateTime.utc(2026, 9, 12, 18));
    });

    test('a pending render is not ready', () async {
      await firestore
          .collection(FirestoreMontageRepository.collection)
          .doc('starter_starter-02')
          .set({'status': 'pending', 'sourcePostIds': const <String>[]});

      final montage = await repo.watchMontage('game-1', 'starter-02').first;
      expect(montage!.status, MontageStatus.pending);
      expect(montage.isReady, isFalse);
      // The ids are filled in from the query even when the doc omits them.
      expect(montage.gameId, 'game-1');
      expect(montage.taskId, 'starter-02');
    });
  });

  group('MockMontageRepository', () {
    test('is empty by default, so no finale ever appears in mock builds',
        () async {
      final repo = MockMontageRepository();
      expect(await repo.watchMontage('g', 't').first, isNull);
    });

    test('hands back what it was seeded with', () async {
      final repo = MockMontageRepository();
      repo.seed(const Montage(
        gameId: 'g',
        taskId: 't',
        finaleUrl: 'https://cdn.test/f.mp4',
        status: MontageStatus.ready,
      ));
      final montage = await repo.watchMontage('g', 't').first;
      expect(montage!.isReady, isTrue);
      expect(await repo.watchMontage('g', 'other').first, isNull);
    });
  });
}
