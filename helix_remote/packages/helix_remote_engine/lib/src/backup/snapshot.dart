import 'dart:math';
import 'dart:typed_data';

import 'package:helix_remote_api/v2.dart' show CancellationToken;
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/src/backup/archive.dart';
import 'package:helix_remote_engine/src/backup/errors.dart';
import 'package:helix_remote_engine/src/backup/options.dart';
import 'package:helix_remote_engine/src/context.dart';
import 'package:helix_remote_engine/src/messaging/kinds.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// What an export wrote.
final class ExportStats {
  int messages = 0;
  int bytes = 0;

  /// Older messages were left out to fit the size budget.
  bool truncated = false;
}

/// The account's own secrets that only the full backup may carry.
final class ArchiveSecrets {
  ArchiveSecrets({
    required this.identityKeySeed,
    required this.identityKey,
    this.profileKey,
  });

  final Uint8List identityKeySeed;
  final Uint8List identityKey;
  final Uint8List? profileKey;

  @override
  String toString() => 'ArchiveSecrets(<redacted>)';
}

/// What an import did.
final class ImportReport {
  /// Messages that were new to this device.
  int messagesAdded = 0;

  /// Messages this device already had (merged, never overwritten).
  int messagesExisting = 0;

  /// Records that did not parse or failed a sanity check (skipped).
  int invalidRecords = 0;
  int conversations = 0;
  int people = 0;

  @override
  String toString() =>
      'ImportReport(added: $messagesAdded, existing: $messagesExisting, '
      'invalid: $invalidRecords)';
}

/// Reads the local database a page at a time into an archive (CRYPTO_V2.md
/// §13; the layout is [ArchiveFormat]).
///
/// What goes in: people, conversations, messages with reactions, receipts and
/// attachment references (ids, keys, digests; never file bytes), the settings
/// in [BackupOptions.settings]. What stays out, always: sessions, prekeys,
/// sender keys, device keys, tokens, the outbox, view-once messages,
/// placeholders for messages that could not be decrypted, messages that never
/// left (pending or failed) and ones whose disappearing timer ran out. The
/// account identity key and this account's profile key are written only for
/// the kinds that may carry them ([ArchiveKind.full], and the profile key in
/// [ArchiveKind.transfer]).
///
/// Messages are read newest arrival first, so a size budget drops the oldest.
final class SnapshotExporter {
  SnapshotExporter(this._ctx, this._options);

  final EngineContext _ctx;
  final BackupOptions _options;

  HelixDb get _db => _ctx.db;

  /// Whether a message is worth keeping in a backup.
  static bool included(MessageRow m, DateTime now) {
    if (m.viewOnceState != null) return false;
    if (m.kind == MessageKinds.undecryptable) return false;
    if (m.status == MessageStatus.pending || m.status == MessageStatus.failed) {
      return false;
    }
    final expires = m.expiresAt;
    return expires == null || expires.isAfter(now);
  }

  /// Yields the archive's frames. With [maxBytes] the stream stops before the
  /// frame that would pass it ([stats] `truncated`); the header, people,
  /// conversations and settings must fit or this throws `tooLarge`.
  Stream<ArchiveFrame> export({
    required ArchiveKind kind,
    required ExportStats stats,
    int? maxBytes,
    String? transferId,
    ArchiveSecrets? secrets,
    CancellationToken? cancel,
  }) async* {
    if (secrets != null && kind != ArchiveKind.full) {
      throw ArgumentError('only a full backup may carry the identity key');
    }
    final self = _ctx.identity.accountId;
    final now = _ctx.now();
    // Frames are the unit a budget drops, so a small budget gets small frames.
    final frameBytes = maxBytes == null
        ? _options.frameBytes
        : min(_options.frameBytes, max(4096, maxBytes ~/ 8));
    final writer = ArchiveWriter(gzip: _options.gzip, frameBytes: frameBytes);
    var total = 0;

    // Returns the frames that fit; sets truncated when one does not.
    List<ArchiveFrame> admit(List<ArchiveFrame> frames) {
      final out = <ArchiveFrame>[];
      for (final frame in frames) {
        if (maxBytes != null && total + frame.bytes.length > maxBytes) {
          stats.truncated = true;
          break;
        }
        total += frame.bytes.length;
        stats.bytes = total;
        stats.messages += frame.messages;
        out.add(frame);
      }
      return out;
    }

    writer.add({
      't': 'header',
      'v': ArchiveFormat.version,
      'kind': kind.wire,
      'account': self,
      'created': toWireTime(now),
      'transfer': ?transferId,
    });
    if (secrets != null) {
      writer.add({
        't': 'secrets',
        'aik_seed': encodeBytes(secrets.identityKeySeed),
        'aik': encodeBytes(secrets.identityKey),
        'pkey': ?(secrets.profileKey == null
            ? null
            : encodeBytes(secrets.profileKey!)),
      });
    }
    await _writeSelf(writer, kind);
    await _writeSettings(writer);
    await _writePeople(writer, self);
    await _writeConversations(writer);

    // Everything above is small and mandatory.
    final head = writer.finish();
    final accepted = admit(head);
    if (accepted.length != head.length) {
      throw const BackupException(
        BackupFailure.tooLarge,
        'people and chats alone exceed the budget',
      );
    }
    for (final frame in accepted) {
      yield frame;
    }

    int? cursor;
    while (!stats.truncated) {
      if (cancel?.isCancelled ?? false) {
        throw const BackupException(BackupFailure.cancelled);
      }
      final rows = await HistoryStore(
        _db,
      ).messagesBefore(beforeRowid: cursor, limit: _options.pageSize);
      if (rows.isEmpty) break;
      cursor = rows.last.localRowid;
      final keep = [
        for (final row in rows)
          if (included(row, now)) row,
      ];
      if (keep.isNotEmpty) {
        final ids = [for (final row in keep) row.localRowid];
        final attachments = _group(
          await _db.messagesDao.attachmentsFor(ids),
          (AttachmentRow a) => a.messageRowid,
        );
        final reactions = _group(
          await _db.messagesDao.reactionsFor(ids),
          (ReactionRow r) => r.messageRowid,
        );
        final receipts = await HistoryStore(_db).receiptsFor(ids);
        for (final row in keep) {
          writer.add(
            _messageRecord(
              row,
              attachments[row.localRowid] ?? const [],
              reactions[row.localRowid] ?? const [],
              receipts[row.localRowid] ?? const [],
            ),
            message: true,
          );
        }
      }
      for (final frame in admit(writer.takeFrames())) {
        yield frame;
      }
      if (rows.length < _options.pageSize) break;
    }
    if (!stats.truncated) {
      for (final frame in admit(writer.finish())) {
        yield frame;
      }
    }
  }

  static Map<int, List<T>> _group<T>(Iterable<T> rows, int Function(T) key) {
    final out = <int, List<T>>{};
    for (final row in rows) {
      (out[key(row)] ??= []).add(row);
    }
    return out;
  }

  // ---------------------------------------------------------- the pieces

  Future<void> _writeSelf(ArchiveWriter writer, ArchiveKind kind) async {
    final account = await _db.accountDao.current();
    if (account == null) return;
    // The profile key is a secret: the AIK-keyed history backup (readable by
    // anyone holding the AIK) does not carry it.
    final key = kind == ArchiveKind.history ? null : account.profileKey;
    writer.add({
      't': 'self',
      'helix': ?account.helixName,
      'pname': ?account.profileName,
      'pkey': ?(key == null ? null : encodeBytes(key)),
    });
  }

  Future<void> _writeSettings(ArchiveWriter writer) async {
    for (final setting in _options.settings) {
      final value = await _db.settingsDao.get(setting);
      if (value == setting.defaultValue) continue;
      writer.add({
        't': 'setting',
        'k': setting.key,
        'v': setting.encode(value),
      });
    }
  }

  Future<void> _writePeople(ArchiveWriter writer, String self) async {
    for (final p in await _db.peopleDao.all()) {
      if (p.accountId == self) continue;
      // Not carried: the phone-book name and the discovery hash (this
      // device's own), the profile key and avatar (the person re-shares them).
      writer.add({
        't': 'person',
        'id': p.accountId,
        'helix': ?p.helixName,
        'phone': ?p.phoneNumber,
        'nick': ?p.nickname,
        'pname': ?p.profileName,
        'pver': ?p.profileVersion,
        'aik': ?(p.identityKey == null ? null : encodeBytes(p.identityKey!)),
        if (p.identityVerified) 'verified': true,
        'changed': ?p.identityChangedAt?.millisecondsSinceEpoch,
        if (p.blocked) 'blocked': true,
        'at': p.updatedAt.millisecondsSinceEpoch,
      });
    }
  }

  Future<void> _writeConversations(ArchiveWriter writer) async {
    final store = HistoryStore(_db);
    for (final c in await store.conversations()) {
      final members = await _db.conversationsDao.membersOf(c.id);
      writer.add({
        't': 'conv',
        'id': c.id,
        'kind': c.kind.name,
        'title': ?c.title,
        'pinned': ?c.pinnedAt?.millisecondsSinceEpoch,
        'muted': ?c.mutedUntil?.millisecondsSinceEpoch,
        if (c.archived) 'archived': true,
        'draft': ?c.draft,
        'timer': ?c.disappearingSeconds,
        'created': c.createdAt.millisecondsSinceEpoch,
        'read': ?c.lastReadSortKey,
        if (members.isNotEmpty) 'members': members,
      });
    }
  }

  JsonMap _messageRecord(
    MessageRow m,
    List<AttachmentRow> media,
    List<ReactionRow> reactions,
    List<ReceiptRow> receipts,
  ) => {
    't': 'msg',
    'id': m.messageId,
    'conv': m.conversationId,
    'from': m.sender,
    'sent': m.sentAt.millisecondsSinceEpoch,
    'recv': m.receivedAt.millisecondsSinceEpoch,
    'kind': m.kind,
    'body': ?m.body,
    'payload': ?m.payload,
    'reply_id': ?m.replyToId,
    'reply_author': ?m.replyToAuthor,
    if (m.forwarded) 'fwd': true,
    if (m.mentionsMe) 'mention': true,
    'status': m.status.name,
    'edited': ?m.editedAt?.millisecondsSinceEpoch,
    'deleted': ?m.deletedAt?.millisecondsSinceEpoch,
    'exp_s': ?m.expireSeconds,
    'exp_at': ?m.expiresAt?.millisecondsSinceEpoch,
    if (reactions.isNotEmpty)
      'reactions': [
        for (final r in reactions)
          {
            'by': r.reactor,
            'emoji': r.emoji,
            'at': r.reactedAt.millisecondsSinceEpoch,
          },
      ],
    if (receipts.isNotEmpty)
      'receipts': [
        for (final r in receipts)
          {
            'acct': r.accountId,
            'delivered': ?r.deliveredAt?.millisecondsSinceEpoch,
            'read': ?r.readAt?.millisecondsSinceEpoch,
            'viewed': ?r.viewedAt?.millisecondsSinceEpoch,
          },
      ],
    if (media.isNotEmpty)
      'media': [
        for (final a in media)
          {
            'pos': a.position,
            'kind': a.kind,
            'id': a.mediaId,
            'key': encodeBytes(a.mediaKey),
            'digest': encodeBytes(a.digest),
            'mime': a.mime,
            'size': a.size,
            'name': ?a.name,
            'w': ?a.width,
            'h': ?a.height,
            'dur': ?a.durationMs,
            'wave': ?(a.waveform == null ? null : encodeBytes(a.waveform!)),
            'blur': ?a.blurhash,
            'caption': ?a.caption,
            'thumb': ?a.thumbnail,
          },
      ],
  };
}

/// Applies an archive to the local database, a frame at a time. Safe to run
/// again: a message is identified by `(id, author)` and an existing one is
/// merged, never overwritten (local wins; a newer edit, a delete-for-everyone,
/// a reaction or receipt this device lacks, a later status and the read
/// position are taken from the archive). Each frame is one transaction in
/// which the affected chat summaries are recomputed and the FTS index follows
/// by its triggers, so an interrupted import leaves a consistent database
/// that the next run completes.
///
/// A fresh session has to see the `header` first; [ImportSession.resumed]
/// continues one whose header an earlier run already checked.
final class SnapshotImporter {
  SnapshotImporter(this._ctx, this._options);

  final EngineContext _ctx;
  final BackupOptions _options;

  ImportSession begin({
    required ArchiveKind kind,
    String? transferId,
    bool headerChecked = false,
  }) => ImportSession._(
    _ctx,
    _options,
    kind,
    transferId,
    headerChecked: headerChecked,
  );

  /// Imports whole archive [bytes] (a history backup's plaintext).
  Future<ImportSession> importBytes(
    List<int> bytes, {
    required ArchiveKind kind,
    void Function(ImportReport report)? onProgress,
  }) async {
    final session = begin(kind: kind);
    for (final frame in ArchiveReader.frames(bytes, gzip: _options.gzip)) {
      await session.addFrame(frame);
      onProgress?.call(session.report);
    }
    session.finish();
    return session;
  }
}

final class ImportSession {
  ImportSession._(
    this._ctx,
    this._options,
    this.kind,
    this._transferId, {
    required bool headerChecked,
  }) : _headerSeen = headerChecked;

  final EngineContext _ctx;
  final BackupOptions _options;
  final ArchiveKind kind;
  final String? _transferId;

  final ImportReport report = ImportReport();

  /// The identity secrets of a full backup, once its header was read.
  ArchiveSecrets? secrets;

  bool _headerSeen;
  final Set<String> _knownChats = {};

  HelixDb get _db => _ctx.db;

  /// Applies one frame (its NDJSON text, from [ArchiveReader.frames]).
  Future<void> addFrame(Uint8List frame) async {
    final records = ArchiveReader.records(frame).toList();
    await _db.transaction(() async {
      final readUpTo = <String, String>{};
      final touched = <String>{};
      for (final r in records) {
        try {
          await _apply(r, readUpTo, touched);
        } on FormatException {
          report.invalidRecords++;
        }
      }
      for (final chat in readUpTo.entries) {
        await _db.messagesDao.markReadUpTo(chat.key, chat.value);
      }
      for (final chat in touched) {
        await _db.messagesDao.refreshSummary(chat);
      }
    });
  }

  /// Checks that the archive was complete enough to be one: a header was
  /// read.
  void finish() {
    if (!_headerSeen) {
      throw const BackupException(BackupFailure.corrupt, 'no header');
    }
  }

  Future<void> _apply(
    JsonReader r,
    Map<String, String> readUpTo,
    Set<String> touched,
  ) async {
    final type = r.string('t');
    if (!_headerSeen) {
      if (type != 'header') {
        throw const BackupException(BackupFailure.corrupt, 'no header');
      }
      _checkHeader(r);
      _headerSeen = true;
      return;
    }
    switch (type) {
      case 'header':
        // A second header is not part of any archive this engine writes.
        throw const BackupException(BackupFailure.corrupt, 'second header');
      case 'secrets':
        if (kind != ArchiveKind.full) {
          throw const BackupException(
            BackupFailure.corrupt,
            'secrets in an archive that may not carry them',
          );
        }
        secrets = ArchiveSecrets(
          identityKeySeed: r.bytes('aik_seed'),
          identityKey: r.bytes('aik'),
          profileKey: r.optBytes('pkey'),
        );
      case 'self':
        await _self(r);
      case 'setting':
        await _setting(r);
      case 'person':
        await _person(r);
      case 'conv':
        await _conversation(r);
      case 'msg':
        await _message(r, readUpTo, touched);
      default:
      // A record type from a newer version: skipped, like unknown fields.
    }
  }

  void _checkHeader(JsonReader r) {
    if (r.integer('v') > ArchiveFormat.version) {
      throw const BackupException(BackupFailure.newerFormat, 'archive version');
    }
    final wire = r.string('kind');
    if (wire != kind.wire) {
      throw BackupException(
        ArchiveKind.values.any((k) => k.wire == wire)
            ? BackupFailure.corrupt
            : BackupFailure.newerFormat,
        'archive kind',
      );
    }
    if (r.string('account') != _ctx.identity.accountId) {
      throw const BackupException(BackupFailure.accountMismatch);
    }
    final expected = _transferId;
    if (expected != null && r.optString('transfer') != expected) {
      throw const BackupException(BackupFailure.corrupt, 'transfer id');
    }
  }

  // --------------------------------------------------------------- pieces

  Future<void> _self(JsonReader r) => HistoryStore(_db).fillSelfProfile(
    helixName: r.optString('helix'),
    profileName: r.optString('pname'),
    // The AIK-keyed history backup never carries the profile key; one that
    // claims to is not believed.
    profileKey: kind == ArchiveKind.history ? null : r.optBytes('pkey'),
  );

  Future<void> _setting(JsonReader r) async {
    final key = r.string('k');
    for (final setting in _options.settings) {
      if (setting.key != key) continue;
      final current = await _db.settingsDao.get(setting);
      if (current == setting.defaultValue) {
        await _db.settingsDao.set(
          setting,
          setting.decode(r.string('v')),
          now: _ctx.now(),
        );
      }
    }
  }

  Future<void> _person(JsonReader r) async {
    final id = _id(r, 'id');
    if (id == _ctx.identity.accountId) return;
    final at = r.optTime('at') ?? _ctx.now();
    final aik = r.optBytes('aik');
    final existing = await _db.peopleDao.byAccount(id);
    if (existing == null) {
      await _db.peopleDao.upsertPerson(
        PeopleCompanion.insert(
          accountId: id,
          updatedAt: at,
          helixName: Value(r.optString('helix')),
          phoneNumber: Value(r.optString('phone')),
          nickname: Value(r.optString('nick')),
          profileName: Value(r.optString('pname')),
          profileVersion: Value(r.optInt('pver')),
          identityKey: Value(aik),
          identityVerified: Value(aik != null && r.flag('verified')),
          identityChangedAt: Value(r.optTime('changed')),
          blocked: Value(r.flag('blocked')),
        ),
      );
      report.people++;
      return;
    }
    // Local wins: fill what is empty. An identity key is pinned only where
    // none is, and "verified" carries over only for the same key.
    await _db.peopleDao.upsertPerson(
      PeopleCompanion.insert(
        accountId: id,
        updatedAt: existing.updatedAt,
        helixName: existing.helixName == null && r.has('helix')
            ? Value(r.string('helix'))
            : const Value.absent(),
        phoneNumber: existing.phoneNumber == null && r.has('phone')
            ? Value(r.string('phone'))
            : const Value.absent(),
        nickname: existing.nickname == null && r.has('nick')
            ? Value(r.string('nick'))
            : const Value.absent(),
        profileName: existing.profileName == null && r.has('pname')
            ? Value(r.string('pname'))
            : const Value.absent(),
        profileVersion: existing.profileVersion == null && r.has('pver')
            ? Value(r.integer('pver'))
            : const Value.absent(),
        identityKey: existing.identityKey == null && aik != null
            ? Value(aik)
            : const Value.absent(),
        identityVerified:
            !existing.identityVerified &&
                r.flag('verified') &&
                aik != null &&
                _same(existing.identityKey ?? aik, aik)
            ? const Value(true)
            : const Value.absent(),
      ),
    );
  }

  Future<void> _conversation(JsonReader r) async {
    final id = _id(r, 'id');
    final chatKind = ConversationKind.values.asNameMap()[r.string('kind')];
    if (chatKind == null) throw ProtocolFormatException('conversation kind');
    await HistoryStore(_db).mergeConversation(
      id: id,
      kind: chatKind,
      createdAt: r.optTime('created') ?? _ctx.now(),
      title: r.optString('title'),
      pinnedAt: r.optTime('pinned'),
      mutedUntil: r.optTime('muted'),
      archived: r.flag('archived'),
      draft: r.optString('draft'),
      disappearingSeconds: r.optInt('timer'),
      lastReadSortKey: r.optString('read'),
      members: r.has('members') ? r.strings('members') : const [],
    );
    _knownChats.add(id);
    report.conversations++;
  }

  Future<void> _ensureChat(String id, DateTime at) async {
    if (_knownChats.contains(id)) return;
    if (await _db.conversationsDao.byId(id) == null) {
      final direct = id.startsWith('direct:');
      await HistoryStore(_db).mergeConversation(
        id: id,
        kind: direct ? ConversationKind.direct : ConversationKind.group,
        createdAt: at,
        members: direct ? [id.substring('direct:'.length)] : const [],
      );
    }
    _knownChats.add(id);
  }

  Future<void> _message(
    JsonReader r,
    Map<String, String> readUpTo,
    Set<String> touched,
  ) async {
    final self = _ctx.identity.accountId;
    final now = _ctx.now();
    final id = _id(r, 'id');
    final chat = _id(r, 'conv');
    final from = _id(r, 'from');
    final limit = now.add(const Duration(minutes: 1));
    var sentAt = r.time('sent');
    if (sentAt.isAfter(limit)) sentAt = limit;
    final receivedAt = r.optTime('recv') ?? sentAt;
    final type = r.string('kind');
    if (type.isEmpty || type.length > 64) {
      throw ProtocolFormatException('message kind');
    }
    final body = r.optString('body');
    if (body != null && body.length > ContentLimits.maxTextLength) {
      throw ProtocolFormatException('message body');
    }
    final expiresAt = r.optTime('exp_at');
    if (expiresAt != null && !expiresAt.isAfter(now)) return;
    final outgoing = from == self;
    final status = _status(r.optString('status'), outgoing: outgoing);
    final deletedAt = r.optTime('deleted');
    final editedAt = r.optTime('edited');
    final payload = r.optString('payload');

    await _ensureChat(chat, sentAt);
    touched.add(chat);
    final existing = await _db.messagesDao.find(id, sender: from);
    if (existing != null) {
      report.messagesExisting++;
      await _mergeExisting(
        existing,
        r,
        status,
        deletedAt,
        editedAt,
        body,
        payload,
      );
    } else {
      final media = deletedAt == null
          ? _media(r)
          : const <AttachmentsCompanion>[];
      final row = await _db.messagesDao.insertMessage(
        MessagesCompanion.insert(
          messageId: id,
          conversationId: chat,
          sender: from,
          outgoing: outgoing,
          sortKey: SortKey.of(sentAt, id),
          sentAt: sentAt,
          receivedAt: receivedAt,
          kind: type,
          status: status,
          body: Value(deletedAt == null ? body : null),
          payload: Value(deletedAt == null ? payload : null),
          replyToId: Value(r.optString('reply_id')),
          replyToAuthor: Value(r.optString('reply_author')),
          forwarded: Value(r.flag('fwd')),
          mentionsMe: Value(r.flag('mention')),
          editedAt: Value(editedAt),
          deletedAt: Value(deletedAt),
          expireSeconds: Value(r.optInt('exp_s')),
          expiresAt: Value(expiresAt),
        ),
        media: media,
      );
      report.messagesAdded++;
      if (deletedAt == null) await _reactions(row.localRowid, r);
      await _receipts(row.localRowid, r);
    }
    if (!outgoing && status == MessageStatus.read) {
      final key = SortKey.of(sentAt, id);
      final best = readUpTo[chat];
      if (best == null || key.compareTo(best) > 0) readUpTo[chat] = key;
    }
  }

  Future<void> _mergeExisting(
    MessageRow row,
    JsonReader r,
    MessageStatus status,
    DateTime? deletedAt,
    DateTime? editedAt,
    String? body,
    String? payload,
  ) async {
    if (row.deletedAt != null) return;
    if (deletedAt != null) {
      await _db.messagesDao.deleteForEveryone(
        row.localRowid,
        deletedAt: deletedAt,
      );
      return;
    }
    final localEdit = row.editedAt;
    if (editedAt != null &&
        (localEdit == null || editedAt.isAfter(localEdit))) {
      await _db.messagesDao.editMessage(
        row.localRowid,
        body: body,
        payload: payload,
        editedAt: editedAt,
      );
    }
    await _reactions(row.localRowid, r);
    await _receipts(row.localRowid, r);
    if (row.outgoing) {
      await _db.messagesDao.advanceStatus(row.localRowid, status);
    }
  }

  Future<void> _reactions(int rowid, JsonReader r) async {
    if (!r.has('reactions')) return;
    final local = {
      for (final x in await _db.messagesDao.reactionsFor([rowid])) x.reactor: x,
    };
    for (final item in r.objects('reactions', (j) => j)) {
      final by = _id(item, 'by');
      final emoji = item.string('emoji');
      if (emoji.isEmpty || emoji.length > ContentLimits.maxEmojiLength) {
        throw ProtocolFormatException('reaction');
      }
      final at = item.time('at');
      final existing = local[by];
      if (existing == null || at.isAfter(existing.reactedAt)) {
        await _db.messagesDao.setReaction(
          rowid,
          reactor: by,
          emoji: emoji,
          at: at,
        );
      }
    }
  }

  Future<void> _receipts(int rowid, JsonReader r) async {
    if (!r.has('receipts')) return;
    for (final item in r.objects('receipts', (j) => j)) {
      final account = _id(item, 'acct');
      for (final (key, kind) in const [
        ('delivered', ReceiptKind.delivered),
        ('read', ReceiptKind.read),
        ('viewed', ReceiptKind.viewed),
      ]) {
        final at = item.optTime(key);
        if (at != null) {
          await _db.messagesDao.recordReceipt(
            rowid,
            account: account,
            kind: kind,
            at: at,
          );
        }
      }
    }
  }

  List<AttachmentsCompanion> _media(JsonReader r) {
    if (!r.has('media')) return const [];
    final items = r.objects('media', (j) => j)
      ..sort((a, b) => a.integer('pos').compareTo(b.integer('pos')));
    return [
      for (final a in items)
        AttachmentsCompanion.insert(
          messageRowid: 0,
          position: 0,
          kind: a.string('kind'),
          mediaId: _id(a, 'id'),
          mediaKey: _fixed(a.bytes('key')),
          digest: _fixed(a.bytes('digest')),
          mime: a.string('mime'),
          size: a.integer('size'),
          name: Value(a.optString('name')),
          width: Value(a.optInt('w')),
          height: Value(a.optInt('h')),
          durationMs: Value(a.optInt('dur')),
          waveform: Value(a.optBytes('wave')),
          blurhash: Value(a.optString('blur')),
          caption: Value(a.optString('caption')),
          thumbnail: Value(a.optString('thumb')),
          // The bytes are not in a backup: the attachment is fetched again
          // while the relay still has it.
          transfer: AttachmentTransfer.remote,
        ),
    ];
  }

  // -------------------------------------------------------------- helpers

  static String _id(JsonReader r, String key) {
    final value = r.nonEmpty(key);
    if (value.length > 256) throw ProtocolFormatException('id', path: key);
    return value;
  }

  static Uint8List _fixed(Uint8List bytes) {
    if (bytes.length != 32) throw ProtocolFormatException('key length');
    return bytes;
  }

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// A status that makes sense for the direction; anything else falls back to
  /// the settled one (a backup never restores "sending" or "failed").
  static MessageStatus _status(String? name, {required bool outgoing}) {
    final parsed = name == null ? null : MessageStatus.values.asNameMap()[name];
    if (outgoing) {
      return switch (parsed) {
        MessageStatus.delivered ||
        MessageStatus.read ||
        MessageStatus.viewed => parsed!,
        _ => MessageStatus.sent,
      };
    }
    return parsed == MessageStatus.read
        ? MessageStatus.read
        : MessageStatus.received;
  }
}

/// Concatenates [frames] into one archive.
Uint8List joinFrames(Iterable<ArchiveFrame> frames) {
  final out = BytesBuilder(copy: false);
  for (final frame in frames) {
    out.add(frame.bytes);
  }
  return out.takeBytes();
}
