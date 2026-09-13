import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/montage.dart';
import '../../domain/repositories/montage_repository.dart';

/// `montages/{gameId}_{taskId}`, read-only. A single document watch — no
/// query, so no index.
class FirestoreMontageRepository implements MontageRepository {
  final FirebaseFirestore _firestore;

  FirestoreMontageRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  static const String collection = 'montages';

  @override
  Stream<Montage?> watchMontage(String gameId, String taskId) {
    return _firestore
        .collection(collection)
        .doc(Montage.idFor(gameId, taskId))
        .snapshots()
        .map((doc) {
      final data = doc.data();
      if (!doc.exists || data == null) return null;
      return Montage.fromMap({
        'gameId': gameId,
        'taskId': taskId,
        ...data,
      });
    });
  }
}
