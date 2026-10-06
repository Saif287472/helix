import 'package:helix_remote_server/src/platform/db/db.dart';

/// The media module's facade (ADR-026).
abstract interface class MediaApi {
  /// Restarts the 90-day retention of an account's backup media objects
  /// (a new full backup still references them). Returns how many.
  Future<int> extendBackupMedia(
    SqlSession db,
    String accountId,
    List<String> ids,
  );
}
