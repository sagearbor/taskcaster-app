import '../../domain/models/montage.dart';
import '../../domain/repositories/montage_repository.dart';

/// Mock-mode / widget-test double.
///
/// Empty by default — mock builds show no finale card at all, which is exactly
/// what a build with no server render behind it should do. Tests seed
/// [montages] (keyed by `Montage.idFor`) when they want one.
class MockMontageRepository implements MontageRepository {
  final Map<String, Montage> montages;

  MockMontageRepository([Map<String, Montage>? montages])
      : montages = montages ?? <String, Montage>{};

  void seed(Montage montage) {
    montages[Montage.idFor(montage.gameId, montage.taskId)] = montage;
  }

  @override
  Stream<Montage?> watchMontage(String gameId, String taskId) {
    return Stream.value(montages[Montage.idFor(gameId, taskId)]);
  }
}
