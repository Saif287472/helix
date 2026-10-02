import 'package:drift/drift.dart';
import 'package:helix_remote_db/src/values.dart';

/// A group this device is in (CRYPTO_V2.md §7, plan §6.2).
///
/// The **roster is the server's**, not this device's: it is what the group
/// module returns, and every message is encrypted to exactly those devices. The
/// [state] blob is the group's own encrypted settings, which only members can
/// read; the optimistic copy in [stateVersion] is what the UI shows while the
/// real one is still being fetched.
@DataClassName('GroupRow')
@TableIndex(name: 'groups_list', columns: {#archived})
class Groups extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  BlobColumn get avatar => blob().nullable()();

  /// `GroupRole` wire name (`owner`, `admin`, `member`).
  TextColumn get role => text()();

  /// The server's monotonic roster version. A send presenting an older roster
  /// is refused (`device_list_stale`), so it is stored and compared.
  IntColumn get epoch => integer().withDefault(const Constant(0))();

  /// The group's encrypted state blob and its version.
  BlobColumn get state => blob().nullable()();
  IntColumn get stateVersion => integer().withDefault(const Constant(0))();

  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  BoolColumn get muted => boolean().withDefault(const Constant(false))();

  /// `messages.local_rowid` of the newest message, kept as with a direct chat
  /// so the chat list reads one table.
  IntColumn get lastMessageRowid => integer().nullable()();
  TextColumn get lastMessageSortKey => text().nullable()();
  IntColumn get lastMessageAt => integer().nullable().map(const EpochMs())();
  TextColumn get lastMessagePreview => text().nullable()();
  IntColumn get unreadCount => integer().withDefault(const Constant(0))();
  IntColumn get mentionCount => integer().withDefault(const Constant(0))();

  IntColumn get createdAt => integer().map(const EpochMs())();

  @override
  Set<Column> get primaryKey => {id};
}

/// A group's members, as the server last reported them.
///
/// Storing the roster is what lets a send name the exact devices to encrypt
/// to, and what lets the sender-key fan-out decide who is missing the key.
/// [devicesJson] is the member's device list the server returned, kept as the
/// fan-out digest compares against it.
@DataClassName('GroupMemberRow')
@TableIndex(name: 'group_members_account', columns: {#accountId})
class GroupMembers extends Table {
  TextColumn get groupId =>
      text().references(Groups, #id, onDelete: KeyAction.cascade)();
  TextColumn get accountId => text()();

  /// `uuid@domain` for a member on another server (federation, S6c).
  TextColumn get qualifiedId => text()();
  TextColumn get displayName => text().nullable()();

  /// `GroupRole` wire name.
  TextColumn get role => text()();
  BoolColumn get isSelf => boolean().withDefault(const Constant(false))();

  /// The server's device list for this member, as JSON. Compared by digest, so
  /// a stale send can be detected without this device learning anything about
  /// anybody's devices beyond their ids.
  TextColumn get devicesJson => text()();
  IntColumn get devicesFetchedAt => integer().nullable().map(const EpochMs())();

  IntColumn get joinedAt => integer().nullable().map(const EpochMs())();

  @override
  Set<Column> get primaryKey => {groupId, accountId};
}

/// A ban, so a removed member cannot rejoin through an invite link.
@DataClassName('GroupBanRow')
class GroupBans extends Table {
  TextColumn get groupId =>
      text().references(Groups, #id, onDelete: KeyAction.cascade)();
  TextColumn get accountId => text()();
  IntColumn get bannedAt => integer().map(const EpochMs())();

  @override
  Set<Column> get primaryKey => {groupId, accountId};
}

/// A call this device was part of, for the Calls tab.
///
/// The log holds the *fact* of the call and its direction, never audio, never
/// the SDP. Signaling payloads are ephemeral and are not kept.
@DataClassName('CallLogRow')
@TableIndex(name: 'call_log_at', columns: {#startedAt})
class CallLog extends Table {
  TextColumn get callId => text()();
  TextColumn get peerAccountId => text()();
  TextColumn get peerDisplayName => text().nullable()();

  /// `direct` or `group`. Group calls are deferred from v2 (plan §13), but the
  /// column exists so adding them is a data change, not a redesign.
  TextColumn get kind => text()();

  /// `incoming`, `outgoing`, `missed`, `declined`, `failed`.
  TextColumn get direction => text()();
  BoolColumn get video => boolean().withDefault(const Constant(false))();

  /// `active`, `ended`, `declined`, `missed`, `cancelled`, `unanswered`.
  TextColumn get state => text()();

  IntColumn get startedAt => integer().map(const EpochMs())();
  IntColumn get answeredAt => integer().nullable().map(const EpochMs())();
  IntColumn get endedAt => integer().nullable().map(const EpochMs())();

  @override
  Set<Column> get primaryKey => {callId};
}
