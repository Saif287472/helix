import 'package:drift/drift.dart';
import 'package:helix_remote_db/src/tables/conversations.dart';
import 'package:helix_remote_db/src/tables/messages.dart';
import 'package:helix_remote_db/src/values.dart';

/// Mailbox position (REALTIME_V2.md). One row (`id = 1`).
@DataClassName('InboxCursorRow')
class InboxCursor extends Table {
  IntColumn get id => integer()();

  /// Highest `seq` durably processed (sent as `after` on reconnect).
  IntColumn get lastProcessedSeq => integer().withDefault(const Constant(0))();

  /// Highest `seq` acked to the server.
  IntColumn get lastAckedSeq => integer().withDefault(const Constant(0))();
  IntColumn get updatedAt => integer().map(const EpochMs())();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => ['CHECK (id = 1)'];
}

/// Envelopes already processed, for de-duplicating replays by envelope id
/// plus sender device (REALTIME_V2.md). Written in the same transaction as
/// the envelope's effects; pruned after the replay window.
@DataClassName('ProcessedEnvelopeRow')
@TableIndex(name: 'processed_envelopes_at', columns: {#processedAt})
class ProcessedEnvelopes extends Table {
  TextColumn get envelopeId => text()();

  /// Empty for envelopes the server generates.
  TextColumn get senderDevice => text().withDefault(const Constant(''))();
  IntColumn get seq => integer().nullable()();
  TextColumn get outcome => textEnum<EnvelopeOutcome>()();
  IntColumn get processedAt => integer().map(const EpochMs())();

  @override
  Set<Column> get primaryKey => {envelopeId, senderDevice};
}

/// Outbound work (plan §6.3): written with the optimistic row in one
/// transaction, encrypted at send time, sent with [idempotencyKey].
@DataClassName('OutboxOpRow')
@TableIndex(name: 'outbox_ops_due', columns: {#state, #nextAttemptAt})
class OutboxOps extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// What to do (`send_message`, `send_receipt`, …); the engine defines it.
  TextColumn get kind => text()();
  TextColumn get conversationId => text().nullable().references(
    Conversations,
    #id,
    onDelete: KeyAction.cascade,
  )();
  IntColumn get messageRowid => integer().nullable().references(
    Messages,
    #localRowid,
    onDelete: KeyAction.cascade,
  )();
  TextColumn get idempotencyKey => text().unique()();

  /// Plaintext to encrypt at send time (JSON).
  TextColumn get payload => text()();
  TextColumn get state => textEnum<OutboxState>()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  IntColumn get nextAttemptAt => integer().map(const EpochMs())();
  IntColumn get leaseUntil => integer().nullable().map(const EpochMs())();

  /// An error code only, never content.
  TextColumn get lastError => text().nullable()();
  IntColumn get createdAt => integer().map(const EpochMs())();
}

/// Actions (reaction, edit, delete, vote, RSVP, receipt) whose target
/// message has not arrived yet; applied when it does, dropped after
/// [expiresAt] (7 days, CONTENT_V2.md §3).
@DataClassName('DeferredActionRow')
@TableIndex(
  name: 'deferred_actions_target',
  columns: {#targetMessageId, #targetAuthor},
)
@TableIndex(name: 'deferred_actions_expiry', columns: {#expiresAt})
class DeferredActions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get targetMessageId => text()();
  TextColumn get targetAuthor => text()();
  TextColumn get sender => text()();
  TextColumn get senderDevice => text().nullable()();

  /// The content `type` of the action.
  TextColumn get kind => text()();

  /// The decoded content message as JSON.
  TextColumn get payload => text()();
  IntColumn get receivedAt => integer().map(const EpochMs())();
  IntColumn get expiresAt => integer().map(const EpochMs())();
}
