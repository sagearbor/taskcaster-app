import '../models/montage.dart';

/// Read-only access to the server-rendered montages.
///
/// The app NEVER writes here: `montages/{gameId}_{taskId}` is produced by a
/// server pass that splices the last two seconds of every entry into a finale.
/// Every caller must treat "no montage" and "still rendering" as the normal
/// case and show nothing at all.
abstract class MontageRepository {
  /// The montage for one task of one game, or null while none exists.
  Stream<Montage?> watchMontage(String gameId, String taskId);
}
