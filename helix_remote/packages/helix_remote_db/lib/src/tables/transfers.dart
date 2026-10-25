import 'package:drift/drift.dart';
import 'package:helix_remote_db/src/tables/messages.dart';
import 'package:helix_remote_db/src/values.dart';

/// An attachment transfer in progress (plan §6.3).
///
/// The queue is durable so a transfer survives the app being closed: a large
/// upload or download resumes from [offset] rather than starting again. The
/// file itself lives outside the database, under a random name; only its path
/// is stored, and the bytes stay encrypted by the attachment key at rest on a
/// platform that offers it.
@DataClassName('TransferRow')
@TableIndex(name: 'transfer_jobs_state', columns: {#state, #nextAttemptAt})
// One job per standalone purpose (a group avatar, a backup blob), so two
// racing calls cannot both queue it. Attachment jobs leave `purpose` null,
// which SQLite treats as distinct, so they are not touched.
@TableIndex(name: 'transfer_jobs_purpose', columns: {#purpose}, unique: true)
class TransferJobs extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// `upload`, `download`, `thumbnail` or `delete`.
  TextColumn get kind => text()();

  /// The attachment this moves. Null for a standalone transfer (a group
  /// avatar, a backup blob).
  IntColumn get attachmentRowid => integer().nullable().references(
    Attachments,
    #id,
    onDelete: KeyAction.cascade,
  )();

  /// Server object id, once the upload target has been created.
  TextColumn get mediaId => text().nullable()();

  /// Where the bytes are, on this device.
  TextColumn get localPath => text().nullable()();
  IntColumn get size => integer().withDefault(const Constant(0))();

  /// How many bytes are already uploaded or downloaded, so a resumed transfer
  /// continues rather than restarting.
  IntColumn get offset => integer().withDefault(const Constant(0))();

  /// The key that decrypts the object (CRYPTO_V2.md §12), so a resumed
  /// download does not have to re-read the message row.
  BlobColumn get mediaKey => blob().nullable()();

  /// What this is for when it is not a plain attachment: `history_backup`,
  /// `full_backup`, `group_avatar`.
  TextColumn get purpose => text().nullable()();

  TextColumn get state => textEnum<TransferState>()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  IntColumn get nextAttemptAt => integer().map(const EpochMs())();
  IntColumn get leaseUntil => integer().nullable().map(const EpochMs())();

  /// The claim token (AUD-10-3). `claim` raises it and gives it to the worker;
  /// every write the worker makes to its job (`setProgress`, `renewLease`,
  /// `resetProgress`, `release`, `reschedule`, `fail`, `markDone`) is
  /// `WHERE id = ? AND version = ?`, so a worker that held the row as a
  /// thumbnail cannot complete it after it became a download. The same shape
  /// as `sessions.version` and `sender_keys.version`, and for the same reason:
  /// two engines over one file. Rows written before schema 5 sit at 0 and the
  /// first claim moves them to 1.
  IntColumn get version => integer().withDefault(const Constant(0))();

  /// An error code only, never content.
  TextColumn get lastError => text().nullable()();
  IntColumn get createdAt => integer().map(const EpochMs())();

  @override
  List<Set<Column>> get uniqueKeys => [
    // One live job per attachment: a second request updates the existing row
    // rather than racing a second transfer of the same bytes.
    {attachmentRowid},
  ];
}

/// A chunk of a device-to-device transfer (F2).
///
/// History can be moved to a new phone either by asking this device over the
/// normal pairwise session or from a history backup. Both share one format, so
/// the layout is written once and tested by the same cases.
@DataClassName('TransferChunkRow')
@TableIndex(name: 'transfer_chunks_transfer', columns: {#transferId, #sequence})
class TransferChunks extends Table {
  TextColumn get transferId => text()();
  IntColumn get sequence => integer()();
  BlobColumn get payload => blob()();

  /// Total chunks, so a gap is detectable rather than silently accepted.
  IntColumn get total => integer()();
  BoolColumn get isFinal => boolean().withDefault(const Constant(false))();
  IntColumn get receivedAt => integer().map(const EpochMs())();

  @override
  Set<Column> get primaryKey => {transferId, sequence};
}
