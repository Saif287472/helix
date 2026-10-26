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

  /// In [tx], marks these backup objects of the account to expire now, so a
  /// delete the caller cannot finish stays the sweep's. Only `backup`-kind
  /// objects of [accountId] are touched. Returns the ids it marked.
  Future<List<String>> expireBackupMedia(
    Tx tx,
    String accountId,
    List<String> ids,
  );

  /// In [tx], marks the account's backup objects whose id is not in [keep]
  /// and which were created no later than [createdBy] to expire now - the
  /// media a replacement full backup dropped. Returns the ids, so the caller
  /// can delete them at once.
  ///
  /// [createdBy] is when the backup being replaced was stored: what it
  /// referenced already existed, while an upload another device or a quicker
  /// re-backup has under way is newer and is not this replacement's to
  /// delete. Those age out like any unreferenced object.
  Future<List<String>> expireBackupMediaExcept(
    Tx tx,
    String accountId,
    List<String> keep, {
    required DateTime createdBy,
  });

  /// Deletes backup-kind objects of [accountId] among [ids] now: blob, then
  /// row, releasing quota. Stops at a short budget; the caller has already
  /// expired every id, so whatever is left is the expiry sweep's. A row
  /// whose blob cannot be deleted stays for that retry. Returns how many
  /// were deleted.
  Future<int> deleteBackupMedia(
    SqlSession db,
    String accountId,
    List<String> ids,
  );
}
